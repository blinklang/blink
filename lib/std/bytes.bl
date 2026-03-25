@module("")

@ffi("pact_bytes_new")
@trusted
fn bytes_new() -> Bytes ! FFI {}

@ffi("pact_bytes_from_str")
@trusted
fn bytes_from_str(s: Str) -> Bytes ! FFI {}

@ffi("pact_bytes_push")
@trusted
fn bytes_push(b: Bytes, byte: Int) ! FFI {}

@ffi("pact_bytes_get")
@trusted
fn bytes_get(b: Bytes, index: Int) -> Int ! FFI {}

@ffi("pact_bytes_set")
@trusted
fn bytes_set(b: Bytes, index: Int, byte: Int) ! FFI {}

@ffi("pact_bytes_len")
@trusted
fn bytes_len(b: Bytes) -> Int ! FFI {}

@ffi("pact_bytes_is_empty")
@trusted
fn bytes_is_empty(b: Bytes) -> Int ! FFI {}

@ffi("pact_bytes_concat")
@trusted
fn bytes_concat(a: Bytes, b: Bytes) -> Bytes ! FFI {}

@ffi("pact_bytes_slice")
@trusted
fn bytes_slice(b: Bytes, start: Int, end: Int) -> Bytes ! FFI {}

@ffi("pact_bytes_to_hex")
@trusted
fn bytes_to_hex(b: Bytes) -> Str ! FFI {}
