// Keeps the Rust FFI symbols from being dead-stripped out of the final iOS
// binary. Nothing in Swift/ObjC calls into Rust directly — Dart resolves the
// symbols at runtime via DynamicLibrary.process() — so without an explicit
// reference the linker may drop the whole static archive. Touching one symbol
// per object pulls them in.

#include <stdint.h>

// Declared in rust/include/qdrant_edge_flutter.h.
extern void *qe_open(const char *, const char *);
extern int32_t qe_add(void *, uint64_t, const char *, const char *);
extern char *qe_search(void *, const char *, uint32_t);
extern int32_t qe_delete(void *, uint64_t);
extern int64_t qe_count(void *);
extern int32_t qe_flush(void *);
extern void qe_close(void *);
extern char *qe_last_error(void);
extern void qe_string_free(char *);

__attribute__((used)) static void *qdrant_edge_flutter_keepalive[] = {
    (void *)qe_open,    (void *)qe_add,        (void *)qe_search,
    (void *)qe_delete,  (void *)qe_count,      (void *)qe_flush,
    (void *)qe_close,   (void *)qe_last_error, (void *)qe_string_free,
};
