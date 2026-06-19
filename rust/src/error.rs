//! Thread-local last-error storage, mirroring the common C errno pattern.

use std::cell::RefCell;
use std::os::raw::c_char;

use crate::ffi::string_to_c;

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

/// Stash an error message for the current thread.
pub(crate) fn set_last_error(msg: String) {
    LAST_ERROR.with(|e| *e.borrow_mut() = Some(msg));
}

/// Return the last error message for the calling thread (or null if none).
/// The caller must free the returned string with `qe_string_free`.
#[no_mangle]
pub extern "C" fn qe_last_error() -> *mut c_char {
    LAST_ERROR.with(|e| match e.borrow_mut().take() {
        Some(msg) => string_to_c(msg),
        None => std::ptr::null_mut(),
    })
}
