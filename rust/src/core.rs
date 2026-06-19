//! High-level, safe wrapper around `qdrant-edge`.
//!
//! A [`Db`] bundles one `EdgeShard` (the on-disk vector store) with one
//! `EdgeBm25` embedder and, optionally, a dense neural [`TextEmbedder`].
//!
//! - Without a model: text is BM25-embedded into a sparse vector — lexical
//!   search, no model, no network.
//! - With a model: each document is *also* embedded into a dense vector, and
//!   search runs a hybrid query that fuses the sparse (BM25) and dense
//!   (semantic) results with Reciprocal Rank Fusion — all on device.

use std::collections::HashMap;
use std::path::Path;

use qdrant_edge::bm25_embed::{EdgeBm25, EdgeBm25Config};
use qdrant_edge::{
    Distance, EdgeConfig, EdgeShard, EdgeSparseVectorParams, EdgeVectorParams, Fusion, Modifier,
    NamedQuery, PointId, PointStruct, Prefetch, QueryEnum, QueryRequest, ScoringQuery, Vector,
    VectorInternal, Vectors, WithPayloadInterface, WithVector,
};
use qdrant_edge::{PointInsertOperations, PointOperations, UpdateOperation};
use serde::{Deserialize, Serialize};

/// Sparse (BM25) vector slot name.
pub const SPARSE_NAME: &str = "text";
/// Dense (neural) vector slot name.
pub const DENSE_NAME: &str = "dense";

/// A handle to an on-device vector database.
pub struct Db {
    shard: EdgeShard,
    bm25: EdgeBm25,
    #[cfg(feature = "dense")]
    embedder: Option<crate::embed::TextEmbedder>,
}

/// One search hit, serialized to JSON for the FFI boundary.
#[derive(Serialize, Deserialize)]
pub struct Hit {
    pub id: String,
    pub score: f32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub payload: Option<serde_json::Value>,
}

impl Db {
    /// Open the database at `path`. If `model_dir` is `Some(dir)` (and the
    /// `dense` feature is on), load the neural model from that directory and
    /// enable hybrid semantic search; otherwise the database is BM25-only.
    pub fn open(path: &str, model_dir: Option<&str>) -> Result<Self, String> {
        let p = Path::new(path);

        let bm25 = EdgeBm25::new(EdgeBm25Config::default()).map_err(|e| e.to_string())?;

        #[cfg(feature = "dense")]
        let embedder = match model_dir {
            Some(d) if !d.is_empty() => Some(crate::embed::TextEmbedder::load(d)?),
            _ => None,
        };
        #[cfg(not(feature = "dense"))]
        let _ = model_dir;

        let existing = EdgeConfig::load(p).is_some();
        let shard = if existing {
            EdgeShard::load(p, None).map_err(|e| format!("load shard: {e}"))?
        } else {
            std::fs::create_dir_all(p).map_err(|e| format!("create dir: {e}"))?;

            // Sparse (BM25) slot is always present. IDF modifier supplies the
            // query-time inverse-document-frequency half of the BM25 score.
            let sparse = EdgeSparseVectorParams::builder()
                .modifier(Modifier::Idf)
                .build();
            let mut builder = EdgeConfig::builder()
                .sparse_vectors(HashMap::from([(SPARSE_NAME.into(), sparse)]));

            // Dense slot only when a model is loaded.
            #[cfg(feature = "dense")]
            if embedder.is_some() {
                let dense =
                    EdgeVectorParams::builder(crate::embed::DENSE_DIM, Distance::Cosine).build();
                builder = builder.vectors(HashMap::from([(DENSE_NAME.into(), dense)]));
            }

            EdgeShard::new(p, builder.build()).map_err(|e| format!("create shard: {e}"))?
        };

        Ok(Db {
            shard,
            bm25,
            #[cfg(feature = "dense")]
            embedder,
        })
    }

    /// Whether hybrid (dense) search is active.
    pub fn is_hybrid(&self) -> bool {
        #[cfg(feature = "dense")]
        {
            self.embedder.is_some()
        }
        #[cfg(not(feature = "dense"))]
        {
            false
        }
    }

    /// Add (upsert) a document. `payload_json` may be empty for no payload.
    pub fn add(&self, id: u64, text: &str, payload_json: &str) -> Result<(), String> {
        let sparse = self.bm25.embed_document(text);
        let sparse_vec = Vector::new_sparse(sparse.indices, sparse.values)
            .map_err(|e| format!("sparse vector: {e}"))?;

        let mut named: Vec<(&str, Vector)> = vec![(SPARSE_NAME, sparse_vec)];

        #[cfg(feature = "dense")]
        if let Some(embedder) = &self.embedder {
            let dense = embedder.embed(text)?;
            named.push((DENSE_NAME, Vector::new_dense(dense)));
        }

        let vectors = Vectors::new_named(named);

        let payload: serde_json::Value = if payload_json.trim().is_empty() {
            serde_json::json!({})
        } else {
            serde_json::from_str(payload_json).map_err(|e| format!("payload json: {e}"))?
        };

        let point_id: PointId =
            serde_json::from_value(serde_json::json!(id)).map_err(|e| e.to_string())?;
        let point = PointStruct::new(point_id, vectors, payload);
        let persisted = point.into();

        let op = UpdateOperation::PointOperation(PointOperations::UpsertPoints(
            PointInsertOperations::PointsList(vec![persisted]),
        ));
        self.shard.update(op).map_err(|e| format!("upsert: {e}"))
    }

    /// Search the database for the `limit` documents most similar to `query`.
    /// Hybrid (BM25 + dense, RRF-fused) when a model is loaded, lexical
    /// otherwise. Returns a JSON array of [`Hit`]s.
    pub fn search(&self, query: &str, limit: usize) -> Result<String, String> {
        let sparse = self.bm25.embed_query(query);
        let sparse_internal = VectorInternal::from(
            Vector::new_sparse(sparse.indices, sparse.values)
                .map_err(|e| format!("sparse vector: {e}"))?,
        );

        #[cfg(feature = "dense")]
        if let Some(embedder) = &self.embedder {
            let dense = embedder.embed(query)?;
            let dense_internal = VectorInternal::from(Vector::new_dense(dense));

            // Each branch retrieves a wider candidate set, then RRF fuses them.
            let candidates = (limit * 5).max(20);
            let pf_sparse = nearest_prefetch(sparse_internal, SPARSE_NAME, candidates);
            let pf_dense = nearest_prefetch(dense_internal, DENSE_NAME, candidates);

            let req = QueryRequest {
                prefetches: vec![pf_sparse, pf_dense],
                query: Some(ScoringQuery::Fusion(Fusion::Rrf {
                    k: 60,
                    weights: None,
                })),
                filter: None,
                score_threshold: None,
                limit,
                offset: 0,
                params: None,
                with_vector: WithVector::Bool(false),
                with_payload: WithPayloadInterface::Bool(true),
            };
            return self.run_query(req);
        }

        // Lexical-only.
        let req = QueryRequest {
            prefetches: vec![],
            query: Some(ScoringQuery::Vector(QueryEnum::Nearest(NamedQuery {
                query: sparse_internal,
                using: Some(SPARSE_NAME.to_string()),
            }))),
            filter: None,
            score_threshold: None,
            limit,
            offset: 0,
            params: None,
            with_vector: WithVector::Bool(false),
            with_payload: WithPayloadInterface::Bool(true),
        };
        self.run_query(req)
    }

    fn run_query(&self, req: QueryRequest) -> Result<String, String> {
        let results = self.shard.query(req).map_err(|e| format!("query: {e}"))?;
        let hits: Vec<Hit> = results
            .into_iter()
            .map(|sp| Hit {
                id: format!("{}", sp.id),
                score: sp.score,
                payload: sp
                    .payload
                    .map(|p| serde_json::to_value(p).unwrap_or_default()),
            })
            .collect();
        serde_json::to_string(&hits).map_err(|e| e.to_string())
    }

    /// Delete a point by numeric id.
    pub fn delete(&self, id: u64) -> Result<(), String> {
        let point_id: PointId =
            serde_json::from_value(serde_json::json!(id)).map_err(|e| e.to_string())?;
        let op = UpdateOperation::PointOperation(PointOperations::DeletePoints {
            ids: vec![point_id],
        });
        self.shard.update(op).map_err(|e| format!("delete: {e}"))
    }

    /// Number of points currently stored.
    pub fn count(&self) -> usize {
        self.shard.info().points_count
    }

    /// Flush pending writes to disk.
    pub fn flush(&self) {
        self.shard.flush();
    }
}

/// Build a `Prefetch` that retrieves the nearest `limit` points on `using`.
fn nearest_prefetch(query: VectorInternal, using: &str, limit: usize) -> Prefetch {
    Prefetch {
        prefetches: vec![],
        query: Some(ScoringQuery::Vector(QueryEnum::Nearest(NamedQuery {
            query,
            using: Some(using.to_string()),
        }))),
        limit,
        params: None,
        filter: None,
        score_threshold: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_add_search_roundtrip() {
        let dir = std::env::temp_dir().join(format!("qe_flutter_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let path = dir.to_str().unwrap();

        let db = Db::open(path, None).expect("open");
        db.add(1, "the quick brown fox jumps over the lazy dog", r#"{"title":"fox"}"#)
            .expect("add 1");
        db.add(2, "a fast auburn fox leaps above a sleepy hound", r#"{"title":"fox2"}"#)
            .expect("add 2");
        db.add(3, "stock markets rallied on strong earnings reports", r#"{"title":"finance"}"#)
            .expect("add 3");
        db.flush();

        assert_eq!(db.count(), 3, "all three points stored");

        let json = db.search("quick brown fox", 5).expect("search");
        let hits: Vec<Hit> = serde_json::from_str(&json).expect("parse hits");
        assert!(!hits.is_empty(), "expected at least one hit");
        assert_eq!(hits[0].id, "1", "doc 1 is the best lexical match");

        // Reload from disk and confirm persistence.
        drop(db);
        let db2 = Db::open(path, None).expect("reopen");
        assert_eq!(db2.count(), 3, "points survive reload");

        // Drop the shard (which flushes) before deleting its directory.
        drop(db2);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[cfg(feature = "dense")]
    #[test]
    fn hybrid_finds_semantic_match() {
        // rust/ -> qdrant_edge_flutter/ -> repo root -> second_brain assets
        let model_dir = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../second_brain/assets/models/minilm"
        );
        if !std::path::Path::new(&format!("{model_dir}/model.safetensors")).exists() {
            eprintln!("SKIP: model not found");
            return;
        }

        let dir = std::env::temp_dir().join(format!("qe_hybrid_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let path = dir.to_str().unwrap();

        let db = Db::open(path, Some(model_dir)).expect("open hybrid");
        assert!(db.is_hybrid());
        db.add(1, "a feline is napping on the couch", "{}").unwrap();
        db.add(2, "the central bank raised interest rates", "{}").unwrap();
        db.add(3, "photosynthesis turns sunlight into energy", "{}").unwrap();
        db.flush();

        // No shared keywords with doc 1 — only a lexical engine would miss it.
        let json = db.search("a cat sleeping on a sofa", 3).unwrap();
        let hits: Vec<Hit> = serde_json::from_str(&json).unwrap();
        eprintln!("hybrid hits: {:?}", hits.iter().map(|h| &h.id).collect::<Vec<_>>());
        assert_eq!(hits[0].id, "1", "semantic match (cat~feline, sofa~couch) ranks first");

        drop(db);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
