/*
 * qdrant_edge_flutter — C ABI for on-device vector search.
 *
 * All embedding (BM25) happens inside Rust; callers only pass strings.
 * Hand-written to match src/lib.rs. Keep the two in sync.
 *
 * Memory / error conventions:
 *   - Strings returned by this library are heap-allocated by Rust; free them
 *     with qe_string_free().
 *   - i32 returns: 0 = ok, -1 = error.
 *   - pointer returns: non-NULL = ok, NULL = error.
 *   - After any error, qe_last_error() returns a (caller-freed) message, or
 *     NULL if there was none on this thread.
 */

#ifndef QDRANT_EDGE_FLUTTER_H
#define QDRANT_EDGE_FLUTTER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque database handle. */
typedef struct QeHandle QeHandle;

/* Open (or create) a database at `path`. If `model_dir` is non-empty, load the
 * neural model there for hybrid semantic search; pass "" for BM25-only.
 * NULL on error. */
QeHandle *qe_open(const char *path, const char *model_dir);

/* Upsert a document. `payload_json` may be "" for none. 0 ok / -1 error. */
int32_t qe_add(QeHandle *handle, uint64_t id, const char *text,
               const char *payload_json);

/* Search for `limit` nearest documents to `query`.
 * Returns a JSON array string: [{"id","score","payload"?}, ...]
 * Free with qe_string_free(). NULL on error. */
char *qe_search(QeHandle *handle, const char *query, uint32_t limit);

/* Delete a point by numeric id. 0 ok / -1 error. */
int32_t qe_delete(QeHandle *handle, uint64_t id);

/* Delete all points matching a JSON filter. 0 ok / -1 error. */
int32_t qe_delete_by_filter(QeHandle *handle, const char *filter_json);

/* Number of stored points, or -1 on error. */
int64_t qe_count(QeHandle *handle);

/* Flush pending writes to disk. 0 ok / -1 error. */
int32_t qe_flush(QeHandle *handle);

/* Close and free a handle. Invalid afterwards. */
void qe_close(QeHandle *handle);

/* Last error message for the calling thread (caller frees), or NULL. */
char *qe_last_error(void);

/* Free a string returned by this library. */
void qe_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* QDRANT_EDGE_FLUTTER_H */
