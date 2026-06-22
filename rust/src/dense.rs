//! On-device dense embedding — text in, JSON float array out.
//!
//! Wraps the candle MiniLM [`TextEmbedder`] behind the same opaque-handle C ABI
//! style as `bm25`. The model is loaded once and reused across many texts and
//! shards; free it with `qe_dense_destroy`. This module (and `embed`) are only
//! built with the `dense` cargo feature.

use std::os::raw::c_char;
use std::ptr;

use qdrant_edge::external::serde_json;

use crate::embed::TextEmbedder;
use crate::error::set_last_error;
use crate::ffi_strings::{cstr_to_str, string_to_c};

/// Opaque handle to a dense [`TextEmbedder`].
pub struct QeDenseHandle {
    embedder: TextEmbedder,
}

/// Load a dense embedder from a model directory containing config.json,
/// tokenizer.json and model.safetensors (an all-MiniLM-L6-v2-style BERT).
/// Returns an opaque handle, or null on error (check `qe_last_error`).
///
/// # Safety
/// `model_dir` must be a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_dense_create(model_dir: *const c_char) -> *mut QeDenseHandle {
    let dir = unsafe { cstr_to_str(model_dir) };
    match TextEmbedder::load(dir) {
        Ok(embedder) => Box::into_raw(Box::new(QeDenseHandle { embedder })),
        Err(e) => {
            set_last_error(format!("Failed to load dense model: {e}"));
            ptr::null_mut()
        }
    }
}

/// Free a dense handle.
///
/// # Safety
/// `handle` must come from [`qe_dense_create`] and not already be freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_dense_destroy(handle: *mut QeDenseHandle) {
    if handle.is_null() {
        return;
    }
    drop(unsafe { Box::from_raw(handle) });
}

/// Embed `text` into an L2-normalized dense vector. Returns a JSON array of
/// floats (`[0.1, 0.2, …]`) suitable for a point/search `vector`, or null on
/// error. Free the returned string with `qe_free_string`.
///
/// # Safety
/// `handle` must come from [`qe_dense_create`]; `text` must be valid UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_dense_embed(
    handle: *mut QeDenseHandle,
    text: *const c_char,
) -> *mut c_char {
    if handle.is_null() {
        set_last_error("null dense handle".to_string());
        return ptr::null_mut();
    }
    let text_str = unsafe { cstr_to_str(text) };
    match unsafe { &(*handle).embedder }.embed(text_str) {
        Ok(vec) => string_to_c(serde_json::to_string(&vec).unwrap_or_default()),
        Err(e) => {
            set_last_error(format!("dense embed failed: {e}"));
            ptr::null_mut()
        }
    }
}
