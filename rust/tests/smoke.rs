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
