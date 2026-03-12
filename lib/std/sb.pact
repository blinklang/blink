@module("")

@ffi("pact_sb_new")
@trusted
fn sb_new() -> StringBuilder ! FFI {}

@ffi("pact_sb_with_capacity")
@trusted
fn sb_with_capacity(cap: Int) -> StringBuilder ! FFI {}

@ffi("pact_sb_write")
@trusted
fn sb_write(sb: StringBuilder, s: Str) ! FFI {}

@ffi("pact_sb_write_char")
@trusted
fn sb_write_char(sb: StringBuilder, ch: Str) ! FFI {}

@ffi("pact_sb_write_int")
@trusted
fn sb_write_int(sb: StringBuilder, val: Int) ! FFI {}

@ffi("pact_sb_write_float")
@trusted
fn sb_write_float(sb: StringBuilder, val: Float) ! FFI {}

@ffi("pact_sb_write_bool")
@trusted
fn sb_write_bool(sb: StringBuilder, val: Int) ! FFI {}

@ffi("pact_sb_to_str")
@trusted
fn sb_to_str(sb: StringBuilder) -> Str ! FFI {}

@ffi("pact_sb_len")
@trusted
fn sb_len(sb: StringBuilder) -> Int ! FFI {}

@ffi("pact_sb_capacity")
@trusted
fn sb_capacity(sb: StringBuilder) -> Int ! FFI {}

@ffi("pact_sb_clear")
@trusted
fn sb_clear(sb: StringBuilder) ! FFI {}

@ffi("pact_sb_is_empty")
@trusted
fn sb_is_empty(sb: StringBuilder) -> Int ! FFI {}
