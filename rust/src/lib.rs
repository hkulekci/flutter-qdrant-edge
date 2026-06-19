//! C ABI for `qdrant_edge_flutter`, consumed from Dart via `dart:ffi`.
//!
//! The surface is deliberately tiny: open a database, add text, search text,
//! delete, count, flush, close. All embedding happens inside Rust (BM25), so
//! Dart only ever passes strings across the boundary.
//!
//! Conventions:
//!   * Opaque `*mut QeHandle` is the database handle.
//!   * Strings in are NUL-terminated UTF-8 (`*const c_char`).
//!   * Strings out are heap-allocated by Rust; free them with `qe_string_free`.
//!   * `i32` returns: `0` = ok, `-1` = error (call `qe_last_error`).
//!   * Pointer returns: non-null = ok, null = error (call `qe_last_error`).

mod core;
#[cfg(feature = "dense")]
#[allow(dead_code)]
mod embed;
mod error;
mod ffi;

use std::os::raw::c_char;

use parking_lot::Mutex;

use crate::core::Db;
use crate::error::set_last_error;
use crate::ffi::{cstr_to_str, string_to_c};

pub use crate::error::qe_last_error;
pub use crate::ffi::qe_string_free;

/// Opaque, thread-safe handle wrapping a [`Db`].
pub struct QeHandle {
    db: Mutex<Db>,
}

/// Open (or create) a database at `path`. If `model_dir` is a non-empty path
/// (and the build has the `dense` feature), the neural model in that directory
/// is loaded and hybrid semantic search is enabled; pass an empty string for
/// lexical (BM25) only. Returns a handle, or null on error.
///
/// # Safety
/// `path` and `model_dir` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn qe_open(
    path: *const c_char,
    model_dir: *const c_char,
) -> *mut QeHandle {
    let path = cstr_to_str(path);
    let model_dir = cstr_to_str(model_dir);
    let model = if model_dir.is_empty() { None } else { Some(model_dir) };
    match Db::open(path, model) {
        Ok(db) => Box::into_raw(Box::new(QeHandle { db: Mutex::new(db) })),
        Err(e) => {
            set_last_error(format!("open failed: {e}"));
            std::ptr::null_mut()
        }
    }
}

/// Add (upsert) a document. `payload_json` may be empty. Returns 0/-1.
///
/// # Safety
/// `handle` must come from [`qe_open`] and not be closed; the strings must be
/// valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn qe_add(
    handle: *mut QeHandle,
    id: u64,
    text: *const c_char,
    payload_json: *const c_char,
) -> i32 {
    let Some(h) = handle.as_ref() else {
        set_last_error("null handle".into());
        return -1;
    };
    let text = cstr_to_str(text);
    let payload = cstr_to_str(payload_json);
    match h.db.lock().add(id, text, payload) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(e);
            -1
        }
    }
}

/// Search for the `limit` documents most similar to `query`. Returns a JSON
/// array string (free with [`qe_string_free`]) or null on error.
///
/// # Safety
/// See [`qe_add`].
#[no_mangle]
pub unsafe extern "C" fn qe_search(
    handle: *mut QeHandle,
    query: *const c_char,
    limit: u32,
) -> *mut c_char {
    let Some(h) = handle.as_ref() else {
        set_last_error("null handle".into());
        return std::ptr::null_mut();
    };
    let query = cstr_to_str(query);
    match h.db.lock().search(query, limit as usize) {
        Ok(json) => string_to_c(json),
        Err(e) => {
            set_last_error(e);
            std::ptr::null_mut()
        }
    }
}

/// Delete a point by numeric id. Returns 0/-1.
///
/// # Safety
/// See [`qe_add`].
#[no_mangle]
pub unsafe extern "C" fn qe_delete(handle: *mut QeHandle, id: u64) -> i32 {
    let Some(h) = handle.as_ref() else {
        set_last_error("null handle".into());
        return -1;
    };
    match h.db.lock().delete(id) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(e);
            -1
        }
    }
}

/// Number of stored points, or -1 on error.
///
/// # Safety
/// See [`qe_add`].
#[no_mangle]
pub unsafe extern "C" fn qe_count(handle: *mut QeHandle) -> i64 {
    match handle.as_ref() {
        Some(h) => h.db.lock().count() as i64,
        None => {
            set_last_error("null handle".into());
            -1
        }
    }
}

/// Flush pending writes to disk. Returns 0/-1.
///
/// # Safety
/// See [`qe_add`].
#[no_mangle]
pub unsafe extern "C" fn qe_flush(handle: *mut QeHandle) -> i32 {
    match handle.as_ref() {
        Some(h) => {
            h.db.lock().flush();
            0
        }
        None => {
            set_last_error("null handle".into());
            -1
        }
    }
}

/// Close and free a database handle. The handle is invalid afterwards.
///
/// # Safety
/// `handle` must come from [`qe_open`] and not have been closed already.
#[no_mangle]
pub unsafe extern "C" fn qe_close(handle: *mut QeHandle) {
    if handle.is_null() {
        return;
    }
    // Dropping the Db flushes the shard.
    drop(Box::from_raw(handle));
}
