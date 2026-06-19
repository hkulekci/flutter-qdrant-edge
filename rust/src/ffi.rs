//! Small helpers for moving strings across the C ABI boundary.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Borrow a C string as `&str`, treating null / invalid UTF-8 as empty.
///
/// # Safety
/// `ptr` must be null or a valid NUL-terminated C string that outlives the
/// returned reference.
pub(crate) unsafe fn cstr_to_str<'a>(ptr: *const c_char) -> &'a str {
    if ptr.is_null() {
        return "";
    }
    CStr::from_ptr(ptr).to_str().unwrap_or("")
}

/// Move a Rust `String` into a heap C string owned by the caller.
/// Returns null if the string contains an interior NUL byte.
pub(crate) fn string_to_c(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a string previously returned by this library.
///
/// # Safety
/// `ptr` must be null or a pointer returned by one of this library's functions
/// and not already freed.
#[no_mangle]
pub unsafe extern "C" fn qe_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
