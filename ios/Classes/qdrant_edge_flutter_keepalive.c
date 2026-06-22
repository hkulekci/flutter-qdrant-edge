// Keeps the Rust FFI symbols from being dead-stripped out of the final binary.
// Nothing in Swift/ObjC calls into Rust directly — Dart resolves the symbols at
// runtime via DynamicLibrary.process() — so without an explicit reference the
// linker may drop objects from the static archive. We touch at least one symbol
// from every FFI module so the whole surface is retained.
//
// Declared in rust/include/qdrant_edge_flutter.h.

#include <stdint.h>

extern void *qe_shard_create(const char *, const char *);
extern int32_t qe_shard_upsert(void *, const char *);
extern char *qe_shard_search(void *, const char *);
extern char *qe_shard_query(void *, const char *);
extern int64_t qe_shard_count(void *, const char *);
extern int32_t qe_shard_set_payload(void *, const char *);
extern int32_t qe_shard_create_field_index(void *, const char *, const char *);
extern int32_t qe_shard_set_hnsw_config(void *, const char *);
extern char *qe_shard_facet(void *, const char *);
extern char *qe_shard_info(void *);
extern int32_t qe_unpack_snapshot(const char *, const char *);
extern void *qe_bm25_create(const char *);
extern void *qe_dense_create(const char *);
extern char *qe_last_error(void);
extern void qe_free_string(char *);

__attribute__((used)) static void *qdrant_edge_flutter_keepalive[] = {
    (void *)qe_shard_create,
    (void *)qe_shard_upsert,
    (void *)qe_shard_search,
    (void *)qe_shard_query,
    (void *)qe_shard_count,
    (void *)qe_shard_set_payload,
    (void *)qe_shard_create_field_index,
    (void *)qe_shard_set_hnsw_config,
    (void *)qe_shard_facet,
    (void *)qe_shard_info,
    (void *)qe_unpack_snapshot,
    (void *)qe_bm25_create,
    (void *)qe_dense_create,
    (void *)qe_last_error,
    (void *)qe_free_string,
};
