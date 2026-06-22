//! Smoke test for the vendored FFI surface, exercised through the C ABI exactly
//! as Dart will: create -> upsert -> flush -> count -> search -> reload.

use std::ffi::{CStr, CString};

use qdrant_edge_flutter::{
    qe_free_string, qe_last_error, qe_shard_close, qe_shard_count, qe_shard_create, qe_shard_flush,
    qe_shard_load, qe_shard_search, qe_shard_upsert,
};

fn cs(s: &str) -> CString {
    CString::new(s).unwrap()
}

unsafe fn take_error() -> String {
    let p = qe_last_error();
    if p.is_null() {
        return "(no error)".into();
    }
    let s = unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned();
    unsafe { qe_free_string(p) };
    s
}

#[test]
fn create_upsert_search_roundtrip() {
    unsafe {
        let dir = std::env::temp_dir().join(format!("qe_ffi_smoke_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("create shard dir");
        let path = cs(dir.to_str().unwrap());
        let empty = cs("");

        let config = cs(r#"{"vectors":{"":{"size":4,"distance":"Cosine"}}}"#);
        let shard = qe_shard_create(path.as_ptr(), config.as_ptr());
        assert!(!shard.is_null(), "create failed: {}", take_error());

        let points = cs(r#"[
            {"id":1,"vector":[1.0,0.0,0.0,0.0],"payload":{"title":"a"}},
            {"id":2,"vector":[0.0,1.0,0.0,0.0],"payload":{"title":"b"}}
        ]"#);
        assert_eq!(
            qe_shard_upsert(shard, points.as_ptr()),
            0,
            "upsert failed: {}",
            take_error()
        );

        qe_shard_flush(shard);
        assert_eq!(
            qe_shard_count(shard, empty.as_ptr()),
            2,
            "count: {}",
            take_error()
        );

        let req = cs(r#"{"vector":[1.0,0.0,0.0,0.0],"limit":5,"with_payload":true}"#);
        let res = qe_shard_search(shard, req.as_ptr());
        assert!(!res.is_null(), "search failed: {}", take_error());
        let json = CStr::from_ptr(res).to_string_lossy().into_owned();
        qe_free_string(res);

        let hits: serde_json::Value = serde_json::from_str(&json).unwrap();
        let arr = hits.as_array().expect("hits is an array");
        assert!(!arr.is_empty(), "expected hits, got: {json}");
        assert_eq!(
            hits[0]["payload"]["title"].as_str(),
            Some("a"),
            "nearest of [1,0,0,0] should be point 'a': {json}"
        );

        qe_shard_close(shard);

        // Reload from disk and confirm persistence.
        let shard2 = qe_shard_load(path.as_ptr(), empty.as_ptr());
        assert!(!shard2.is_null(), "load failed: {}", take_error());
        assert_eq!(
            qe_shard_count(shard2, empty.as_ptr()),
            2,
            "points survive reload"
        );
        qe_shard_close(shard2);

        let _ = std::fs::remove_dir_all(&dir);
    }
}

#[cfg(feature = "dense")]
unsafe fn take_str(p: *mut std::os::raw::c_char) -> String {
    let s = unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned();
    unsafe { qe_free_string(p) };
    s
}

/// Dense + BM25 hybrid: embed both vector kinds on-device, upsert mixed points,
/// and run an RRF-fused query. Skips if the local MiniLM model is absent.
#[cfg(feature = "dense")]
#[test]
fn dense_and_hybrid_query() {
    use qdrant_edge_flutter::{
        qe_bm25_create, qe_bm25_destroy, qe_bm25_embed_document, qe_bm25_embed_query,
        qe_dense_create, qe_dense_destroy, qe_dense_embed, qe_shard_query,
    };
    unsafe {
        let model_dir = concat!(env!("CARGO_MANIFEST_DIR"), "/.models/minilm");
        if !std::path::Path::new(&format!("{model_dir}/model.safetensors")).exists() {
            eprintln!("SKIP: dense model not found at {model_dir}");
            return;
        }

        let dense = qe_dense_create(cs(model_dir).as_ptr());
        assert!(!dense.is_null(), "dense create: {}", take_error());
        let bm25 = qe_bm25_create(cs("").as_ptr());
        assert!(!bm25.is_null(), "bm25 create: {}", take_error());

        let dir = std::env::temp_dir().join(format!("qe_hybrid_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = cs(dir.to_str().unwrap());
        let config = cs(
            r#"{"vectors":{"dense":{"size":384,"distance":"Cosine"}},"sparse_vectors":{"bm25":{"modifier":"idf"}}}"#,
        );
        let shard = qe_shard_create(path.as_ptr(), config.as_ptr());
        assert!(!shard.is_null(), "shard create: {}", take_error());

        let cat = "a cat is sleeping on the sofa";
        let docs = [(1u64, cat), (2, "quarterly tax revenue rose sharply")];
        for (id, text) in docs {
            let dvec = qe_dense_embed(dense, cs(text).as_ptr());
            assert!(!dvec.is_null(), "dense embed: {}", take_error());
            let svec = qe_bm25_embed_document(bm25, cs(text).as_ptr());
            assert!(!svec.is_null(), "bm25 embed: {}", take_error());
            let point = cs(&format!(
                r#"[{{"id":{id},"vector":{{"dense":{},"bm25":{}}},"payload":{{"title":"{text}"}}}}]"#,
                take_str(dvec),
                take_str(svec),
            ));
            assert_eq!(
                qe_shard_upsert(shard, point.as_ptr()),
                0,
                "upsert {id}: {}",
                take_error()
            );
        }
        qe_shard_flush(shard);

        // Paraphrase of the cat doc — shares almost no words, so dense semantics
        // must carry it. RRF fuses the dense + BM25 prefetches.
        let q = "a feline naps on the couch";
        let qd = take_str(qe_dense_embed(dense, cs(q).as_ptr()));
        let qs = take_str(qe_bm25_embed_query(bm25, cs(q).as_ptr()));
        let query = cs(&format!(
            r#"{{"prefetch":[{{"query":{qd},"using":"dense","limit":10}},{{"query":{qs},"using":"bm25","limit":10}}],"query":{{"fusion":"rrf"}},"limit":5,"with_payload":true}}"#
        ));
        let res = qe_shard_query(shard, query.as_ptr());
        assert!(!res.is_null(), "query failed: {}", take_error());
        let hits: serde_json::Value = serde_json::from_str(&take_str(res)).unwrap();
        let arr = hits.as_array().expect("hits array");
        assert!(!arr.is_empty(), "expected hits");
        assert_eq!(
            hits[0]["payload"]["title"].as_str(),
            Some(cat),
            "hybrid top hit should be the semantically-matching cat doc: {hits}"
        );

        qe_shard_close(shard);
        qe_dense_destroy(dense);
        qe_bm25_destroy(bm25);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
