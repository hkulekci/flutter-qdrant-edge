//! C FFI bindings for `qdrant-edge`, consumed from Dart via `dart:ffi`.
//!
//! Complex types are passed as JSON strings across the FFI boundary. The Rust
//! side deserializes JSON into intermediate types (see [`serde_types`]) and
//! converts to the actual `qdrant_edge` types — many of the core types
//! (`SearchRequest`, `QueryRequest`, …) don't implement `Deserialize` directly.
//!
//! The shard/BM25 FFI surface here is adapted from `qdrant-edge-ffi` in
//! rust-dd/react-native-qdrant-edge (MIT). See THIRD_PARTY_NOTICES.md.
//! Our on-device dense embedder (`embed`) is an addition on top.

mod bm25;
mod config;
#[cfg(feature = "dense")]
mod dense;
#[cfg(feature = "dense")]
mod embed;
mod error;
mod facet;
mod ffi_strings;
mod field_index;
mod handle;
mod info;
mod lifecycle;
mod payload;
mod points;
mod retrieve_scroll;
mod search_query;
mod serde_types;
mod snapshot;

pub use bm25::{
    QeBm25Handle, qe_bm25_create, qe_bm25_destroy, qe_bm25_embed_document, qe_bm25_embed_query,
};
pub use config::{
    qe_shard_create_vector_name, qe_shard_delete_vector_name, qe_shard_set_hnsw_config,
    qe_shard_set_optimizers_config, qe_shard_set_vector_hnsw_config,
};
#[cfg(feature = "dense")]
pub use dense::{QeDenseHandle, qe_dense_create, qe_dense_destroy, qe_dense_embed};
pub use error::qe_last_error;
pub use facet::qe_shard_facet;
pub use ffi_strings::qe_free_string;
pub use field_index::{qe_shard_create_field_index, qe_shard_delete_field_index};
pub use handle::QeShardHandle;
pub use info::qe_shard_info;
pub use lifecycle::{
    qe_shard_close, qe_shard_create, qe_shard_flush, qe_shard_load, qe_shard_optimize,
};
pub use payload::{
    qe_shard_clear_payload, qe_shard_delete_payload, qe_shard_overwrite_payload,
    qe_shard_set_payload,
};
pub use points::{qe_shard_delete_points, qe_shard_upsert};
pub use retrieve_scroll::{qe_shard_count, qe_shard_retrieve, qe_shard_scroll};
pub use search_query::{qe_shard_query, qe_shard_search};
pub use snapshot::{qe_recover_partial_snapshot, qe_shard_snapshot_manifest, qe_unpack_snapshot};
