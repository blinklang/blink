import tokens
import ast
import parser
import diagnostics

effect Codegen {
    effect Emit
    effect Register
    effect Scope
}

// codegen_types.pact — Type constants, global state, scope/registry helpers
//
// Minimal subset: enough to compile hello_compiled.pact via the
// Python C backend. Reads the parallel-array AST node pool produced
// by parser.pact and emits C source as a list of strings.
//
// Constraints: same as lexer/parser — parallel arrays, no struct-in-list,
// no closures, no imports. Constants duplicated for self-contained compilation.

// ── C type constants ────────────────────────────────────────────────
// Instead of enums, plain ints.

pub let CT_INT = 0
pub let CT_FLOAT = 1
pub let CT_BOOL = 2
pub let CT_STRING = 3
pub let CT_LIST = 4
pub let CT_VOID = 5
pub let CT_CLOSURE = 6
pub let CT_OPTION = 7
pub let CT_RESULT = 8
pub let CT_ITERATOR = 9
pub let CT_HANDLE = 10
pub let CT_CHANNEL = 11
let CT_TAGGED_ENUM = 12
pub let CT_MAP = 13
pub let CT_BYTES = 14
pub let CT_INSTANT = 15
pub let CT_DURATION = 16
pub let CT_PTR = 17
pub let CT_FFI_SCOPE = 18
pub let CT_STRINGBUILDER = 19
pub let CT_SET = 20

// ── Type node pool (interned, parallel arrays) ─────────────────────
// Recursive type representation: each type is an integer handle into
// these arrays. Constructed bottom-up, interned for O(1) equality.
// Coexists with CT_* during migration; will eventually replace it.

let mut tp_kind: List[Int] = []
let mut tp_child1: List[Int] = []
let mut tp_child2: List[Int] = []
let mut tp_sname: List[Str] = []
let mut tp_intern: Map[Str, Int] = Map()

fn tp_intern_key(kind: Int, c1: Int, c2: Int, sname: Str) -> Str {
    "{kind}:{c1}:{c2}:{sname}"
}

fn tp_alloc(kind: Int, c1: Int, c2: Int, sname: Str) -> Int {
    let key = tp_intern_key(kind, c1, c2, sname)
    if tp_intern.has(key) {
        return tp_intern.get(key)
    }
    let id = tp_kind.len()
    tp_kind.push(kind)
    tp_child1.push(c1)
    tp_child2.push(c2)
    tp_sname.push(sname)
    tp_intern.set(key, id)
    id
}

fn type_int() -> Int {
    tp_alloc(CT_INT, -1, -1, "")
}

fn type_float() -> Int {
    tp_alloc(CT_FLOAT, -1, -1, "")
}

fn type_bool() -> Int {
    tp_alloc(CT_BOOL, -1, -1, "")
}

fn type_string() -> Int {
    tp_alloc(CT_STRING, -1, -1, "")
}

fn type_void() -> Int {
    tp_alloc(CT_VOID, -1, -1, "")
}

fn type_bytes() -> Int {
    tp_alloc(CT_BYTES, -1, -1, "")
}

fn type_instant() -> Int {
    tp_alloc(CT_INSTANT, -1, -1, "")
}

fn type_duration() -> Int {
    tp_alloc(CT_DURATION, -1, -1, "")
}

fn type_list(elem: Int) -> Int {
    tp_alloc(CT_LIST, elem, -1, "")
}

fn type_option(inner: Int) -> Int {
    tp_alloc(CT_OPTION, inner, -1, "")
}

fn type_result(ok: Int, err: Int) -> Int {
    tp_alloc(CT_RESULT, ok, err, "")
}

fn type_map(key: Int, value: Int) -> Int {
    tp_alloc(CT_MAP, key, value, "")
}

fn type_set(elem: Int) -> Int {
    tp_alloc(CT_SET, elem, -1, "")
}

fn type_iterator(inner: Int) -> Int {
    tp_alloc(CT_ITERATOR, inner, -1, "")
}

fn type_handle(inner: Int) -> Int {
    tp_alloc(CT_HANDLE, inner, -1, "")
}

fn type_channel(inner: Int) -> Int {
    tp_alloc(CT_CHANNEL, inner, -1, "")
}

fn type_closure(sig: Str) -> Int {
    tp_alloc(CT_CLOSURE, -1, -1, sig)
}

fn type_struct(name: Str) -> Int {
    tp_alloc(CT_TAGGED_ENUM, -1, -1, name)
}

fn type_enum(name: Str) -> Int {
    tp_alloc(CT_TAGGED_ENUM, -1, -1, name)
}

fn type_ptr(inner: Int) -> Int {
    tp_alloc(CT_PTR, inner, -1, "")
}

fn type_ffi_scope() -> Int {
    tp_alloc(CT_FFI_SCOPE, -1, -1, "")
}

fn type_stringbuilder() -> Int {
    tp_alloc(CT_STRINGBUILDER, -1, -1, "")
}

pub fn tp_get_kind(id: Int) -> Int {
    let k = tp_kind.get(id).unwrap()
    if k == CT_TAGGED_ENUM { return CT_VOID }
    k
}

fn tp_get_child1(id: Int) -> Int {
    tp_child1.get(id).unwrap()
}

fn tp_get_child2(id: Int) -> Int {
    tp_child2.get(id).unwrap()
}

pub fn tp_get_sname(id: Int) -> Str {
    tp_sname.get(id).unwrap()
}

pub fn tp_child1_kind(id: Int) -> Int {
    let c1 = tp_child1.get(id).unwrap()
    if c1 >= 0 { return tp_get_kind(c1) }
    -1
}

pub fn tp_child2_kind(id: Int) -> Int {
    let c2 = tp_child2.get(id).unwrap()
    if c2 >= 0 { return tp_get_kind(c2) }
    -1
}

fn tp_display(id: Int) -> Str {
    if id < 0 {
        return "?"
    }
    let k = tp_kind.get(id).unwrap()
    if k == CT_INT { return "Int" }
    if k == CT_FLOAT { return "Float" }
    if k == CT_BOOL { return "Bool" }
    if k == CT_STRING { return "Str" }
    if k == CT_VOID { return "Void" }
    if k == CT_BYTES { return "Bytes" }
    if k == CT_INSTANT { return "Instant" }
    if k == CT_DURATION { return "Duration" }
    if k == CT_FFI_SCOPE { return "FFIScope" }
    if k == CT_STRINGBUILDER { return "StringBuilder" }
    let c1 = tp_child1.get(id).unwrap()
    let c2 = tp_child2.get(id).unwrap()
    let sn = tp_sname.get(id).unwrap()
    if k == CT_LIST { return "List[{tp_display(c1)}]" }
    if k == CT_OPTION { return "Option[{tp_display(c1)}]" }
    if k == CT_RESULT { return "Result[{tp_display(c1)}, {tp_display(c2)}]" }
    if k == CT_MAP { return "Map[{tp_display(c1)}, {tp_display(c2)}]" }
    if k == CT_ITERATOR { return "Iterator[{tp_display(c1)}]" }
    if k == CT_HANDLE { return "Handle[{tp_display(c1)}]" }
    if k == CT_CHANNEL { return "Channel[{tp_display(c1)}]" }
    if k == CT_PTR { return "Ptr[{tp_display(c1)}]" }
    if k == CT_CLOSURE { return "Fn({sn})" }
    if k == CT_TAGGED_ENUM { return sn }
    "Unknown"
}

// ── Codegen state ───────────────────────────────────────────────────

pub let mut cg_lines: List[Str] = []
pub let mut cg_indent: Int = 0
pub let mut cg_temp_counter: Int = 0
pub let mut cg_global_inits: List[Str] = []
pub let mut closure_param_names: List[Str] = []
pub let mut struct_reg_names: List[Str] = []
pub type EnumReg {
    name: Str
    has_data: Int
}

pub type EnumVariant {
    name: Str
    enum_idx: Int
    field_names: Str
    field_types: Str
    field_count: Int
}

pub let mut enum_regs: List[EnumReg] = []
pub let mut enum_variants: List[EnumVariant] = []
pub type VarEnumEntry {
    name: Str
    enum_type: Str
}
pub let mut var_enums: List[VarEnumEntry] = []
pub type FnEnumRetEntry {
    name: Str
    enum_type: Str
}
pub let mut fn_enum_rets: List[FnEnumRetEntry] = []
pub let mut emitted_let_names: List[Str] = []
pub let mut emitted_fn_names: List[Str] = []
pub let mut struct_reg_set: Map[Str, Int] = Map()
pub let mut enum_reg_set: Map[Str, Int] = Map()
pub let mut emitted_fn_set: Map[Str, Int] = Map()
pub let mut emitted_let_set: Map[Str, Int] = Map()
pub let mut emitted_option_set: Map[Str, Int] = Map()
pub let mut emitted_result_set: Map[Str, Int] = Map()
pub let mut emitted_iter_set: Map[Str, Int] = Map()
pub let mut cg_closure_defs: List[Str] = []
pub let mut cg_closure_counter: Int = 0
pub let mut cg_closure_param_type_hint: Int = -1

pub let mut cg_ffi_libs: List[Str] = []
pub let mut cg_ffi_lib_set: Map[Str, Int] = Map()

pub let mut mod_fn_prefix: Map[Str, Str] = Map()
pub let mut mod_type_prefix: Map[Str, Str] = Map()

pub let mut type_alias_base: Map[Str, Str] = Map()
pub let mut type_where_preds: Map[Str, Int] = Map()
pub let mut cg_where_self_var: Str = ""

// C reserved words and problematic libc names — identifiers that must be mangled
let mut c_reserved_set: Map[Str, Int] = Map()
let mut c_reserved_init_done: Int = 0

fn init_c_reserved() {
    if c_reserved_init_done != 0 {
        return
    }
    c_reserved_init_done = 1
    // C keywords
    c_reserved_set.set("auto", 1)
    c_reserved_set.set("break", 1)
    c_reserved_set.set("case", 1)
    c_reserved_set.set("char", 1)
    c_reserved_set.set("const", 1)
    c_reserved_set.set("continue", 1)
    c_reserved_set.set("default", 1)
    c_reserved_set.set("do", 1)
    c_reserved_set.set("double", 1)
    c_reserved_set.set("else", 1)
    c_reserved_set.set("enum", 1)
    c_reserved_set.set("extern", 1)
    c_reserved_set.set("float", 1)
    c_reserved_set.set("for", 1)
    c_reserved_set.set("goto", 1)
    c_reserved_set.set("if", 1)
    c_reserved_set.set("inline", 1)
    c_reserved_set.set("int", 1)
    c_reserved_set.set("long", 1)
    c_reserved_set.set("register", 1)
    c_reserved_set.set("restrict", 1)
    c_reserved_set.set("return", 1)
    c_reserved_set.set("short", 1)
    c_reserved_set.set("signed", 1)
    c_reserved_set.set("sizeof", 1)
    c_reserved_set.set("static", 1)
    c_reserved_set.set("struct", 1)
    c_reserved_set.set("switch", 1)
    c_reserved_set.set("typedef", 1)
    c_reserved_set.set("union", 1)
    c_reserved_set.set("unsigned", 1)
    c_reserved_set.set("void", 1)
    c_reserved_set.set("volatile", 1)
    c_reserved_set.set("while", 1)
    // C99/C11
    c_reserved_set.set("_Bool", 1)
    c_reserved_set.set("_Complex", 1)
    c_reserved_set.set("_Imaginary", 1)
    c_reserved_set.set("_Alignas", 1)
    c_reserved_set.set("_Alignof", 1)
    c_reserved_set.set("_Atomic", 1)
    c_reserved_set.set("_Generic", 1)
    c_reserved_set.set("_Noreturn", 1)
    c_reserved_set.set("_Static_assert", 1)
    c_reserved_set.set("_Thread_local", 1)
    // Common libc/POSIX names that would conflict
    c_reserved_set.set("errno", 1)
    c_reserved_set.set("stdin", 1)
    c_reserved_set.set("stdout", 1)
    c_reserved_set.set("stderr", 1)
    c_reserved_set.set("printf", 1)
    c_reserved_set.set("fprintf", 1)
    c_reserved_set.set("sprintf", 1)
    c_reserved_set.set("snprintf", 1)
    c_reserved_set.set("scanf", 1)
    c_reserved_set.set("malloc", 1)
    c_reserved_set.set("calloc", 1)
    c_reserved_set.set("realloc", 1)
    c_reserved_set.set("free", 1)
    c_reserved_set.set("exit", 1)
    c_reserved_set.set("abort", 1)
    c_reserved_set.set("strlen", 1)
    c_reserved_set.set("strcmp", 1)
    c_reserved_set.set("strcpy", 1)
    c_reserved_set.set("strcat", 1)
    c_reserved_set.set("memcpy", 1)
    c_reserved_set.set("memset", 1)
    c_reserved_set.set("memmove", 1)
    c_reserved_set.set("memcmp", 1)
    c_reserved_set.set("strncmp", 1)
    c_reserved_set.set("strncpy", 1)
    c_reserved_set.set("strncat", 1)
    c_reserved_set.set("strstr", 1)
    c_reserved_set.set("strchr", 1)
    c_reserved_set.set("strdup", 1)
    c_reserved_set.set("strtok", 1)
    c_reserved_set.set("fopen", 1)
    c_reserved_set.set("fclose", 1)
    c_reserved_set.set("fread", 1)
    c_reserved_set.set("fwrite", 1)
    c_reserved_set.set("atoi", 1)
    c_reserved_set.set("atof", 1)
    c_reserved_set.set("strtol", 1)
    c_reserved_set.set("strtod", 1)
    c_reserved_set.set("getenv", 1)
    c_reserved_set.set("system", 1)
    c_reserved_set.set("qsort", 1)
    c_reserved_set.set("read", 1)
    c_reserved_set.set("write", 1)
    c_reserved_set.set("close", 1)
    c_reserved_set.set("sleep", 1)
    c_reserved_set.set("fork", 1)
    c_reserved_set.set("pipe", 1)
    c_reserved_set.set("socket", 1)
    c_reserved_set.set("bind", 1)
    c_reserved_set.set("listen", 1)
    c_reserved_set.set("accept", 1)
    c_reserved_set.set("connect", 1)
    c_reserved_set.set("send", 1)
    c_reserved_set.set("recv", 1)
    c_reserved_set.set("time", 1)
    c_reserved_set.set("clock", 1)
    c_reserved_set.set("log", 1)
    c_reserved_set.set("round", 1)
    c_reserved_set.set("NULL", 1)
    c_reserved_set.set("main", 1)
    c_reserved_set.set("true", 1)
    c_reserved_set.set("false", 1)
}

let mut runtime_header_fns: Map[Str, Int] = Map()
let mut runtime_header_init_done: Int = 0

fn init_runtime_header_fns() {
    if runtime_header_init_done != 0 {
        return
    }
    runtime_header_init_done = 1
    // Functions from headers included by runtime.h that must not get duplicate extern declarations
    // stdio.h
    runtime_header_fns.set("printf", 1)
    runtime_header_fns.set("fprintf", 1)
    runtime_header_fns.set("sprintf", 1)
    runtime_header_fns.set("snprintf", 1)
    runtime_header_fns.set("fopen", 1)
    runtime_header_fns.set("fclose", 1)
    runtime_header_fns.set("fread", 1)
    runtime_header_fns.set("fwrite", 1)
    runtime_header_fns.set("fgets", 1)
    runtime_header_fns.set("fputs", 1)
    runtime_header_fns.set("puts", 1)
    runtime_header_fns.set("scanf", 1)
    runtime_header_fns.set("fflush", 1)
    runtime_header_fns.set("fseek", 1)
    runtime_header_fns.set("ftell", 1)
    runtime_header_fns.set("rewind", 1)
    runtime_header_fns.set("remove", 1)
    runtime_header_fns.set("rename", 1)
    runtime_header_fns.set("perror", 1)
    // stdlib.h
    runtime_header_fns.set("malloc", 1)
    runtime_header_fns.set("calloc", 1)
    runtime_header_fns.set("realloc", 1)
    runtime_header_fns.set("free", 1)
    runtime_header_fns.set("exit", 1)
    runtime_header_fns.set("abort", 1)
    runtime_header_fns.set("atoi", 1)
    runtime_header_fns.set("atol", 1)
    runtime_header_fns.set("atof", 1)
    runtime_header_fns.set("strtol", 1)
    runtime_header_fns.set("strtod", 1)
    runtime_header_fns.set("abs", 1)
    runtime_header_fns.set("labs", 1)
    runtime_header_fns.set("llabs", 1)
    runtime_header_fns.set("rand", 1)
    runtime_header_fns.set("srand", 1)
    runtime_header_fns.set("getenv", 1)
    runtime_header_fns.set("system", 1)
    runtime_header_fns.set("qsort", 1)
    runtime_header_fns.set("bsearch", 1)
    // string.h
    runtime_header_fns.set("strlen", 1)
    runtime_header_fns.set("strcmp", 1)
    runtime_header_fns.set("strncmp", 1)
    runtime_header_fns.set("strcpy", 1)
    runtime_header_fns.set("strncpy", 1)
    runtime_header_fns.set("strcat", 1)
    runtime_header_fns.set("strncat", 1)
    runtime_header_fns.set("memcpy", 1)
    runtime_header_fns.set("memset", 1)
    runtime_header_fns.set("memmove", 1)
    runtime_header_fns.set("memcmp", 1)
    runtime_header_fns.set("strstr", 1)
    runtime_header_fns.set("strchr", 1)
    runtime_header_fns.set("strdup", 1)
    runtime_header_fns.set("strtok", 1)
    // time.h
    runtime_header_fns.set("time", 1)
    runtime_header_fns.set("clock", 1)
    runtime_header_fns.set("difftime", 1)
    runtime_header_fns.set("mktime", 1)
    runtime_header_fns.set("strftime", 1)
    runtime_header_fns.set("localtime", 1)
    runtime_header_fns.set("gmtime", 1)
    // unistd.h
    runtime_header_fns.set("read", 1)
    runtime_header_fns.set("write", 1)
    runtime_header_fns.set("close", 1)
    runtime_header_fns.set("sleep", 1)
    runtime_header_fns.set("usleep", 1)
    runtime_header_fns.set("getcwd", 1)
    runtime_header_fns.set("chdir", 1)
    runtime_header_fns.set("fork", 1)
    runtime_header_fns.set("execvp", 1)
    runtime_header_fns.set("pipe", 1)
    runtime_header_fns.set("dup2", 1)
    runtime_header_fns.set("access", 1)
    runtime_header_fns.set("unlink", 1)
    runtime_header_fns.set("rmdir", 1)
    // pthread.h
    runtime_header_fns.set("pthread_create", 1)
    runtime_header_fns.set("pthread_join", 1)
    runtime_header_fns.set("pthread_mutex_init", 1)
    runtime_header_fns.set("pthread_mutex_lock", 1)
    runtime_header_fns.set("pthread_mutex_unlock", 1)
    // socket/network
    runtime_header_fns.set("socket", 1)
    runtime_header_fns.set("bind", 1)
    runtime_header_fns.set("listen", 1)
    runtime_header_fns.set("accept", 1)
    runtime_header_fns.set("connect", 1)
    runtime_header_fns.set("send", 1)
    runtime_header_fns.set("recv", 1)
    runtime_header_fns.set("getaddrinfo", 1)
    runtime_header_fns.set("freeaddrinfo", 1)
    // sqlite3.h
    runtime_header_fns.set("sqlite3_open", 1)
    runtime_header_fns.set("sqlite3_close", 1)
    runtime_header_fns.set("sqlite3_exec", 1)
    runtime_header_fns.set("sqlite3_prepare_v2", 1)
    runtime_header_fns.set("sqlite3_step", 1)
    runtime_header_fns.set("sqlite3_finalize", 1)
    runtime_header_fns.set("sqlite3_errmsg", 1)
    // math.h (linked via -lm)
    runtime_header_fns.set("sqrt", 1)
    runtime_header_fns.set("pow", 1)
    runtime_header_fns.set("sin", 1)
    runtime_header_fns.set("cos", 1)
    runtime_header_fns.set("tan", 1)
    runtime_header_fns.set("log", 1)
    runtime_header_fns.set("exp", 1)
    runtime_header_fns.set("ceil", 1)
    runtime_header_fns.set("floor", 1)
    runtime_header_fns.set("fabs", 1)
    runtime_header_fns.set("round", 1)
    // runtime_core.h string functions
    runtime_header_fns.set("pact_str_len", 1)
    runtime_header_fns.set("pact_str_char_at", 1)
    runtime_header_fns.set("pact_str_substr", 1)
    runtime_header_fns.set("pact_str_from_char_code", 1)
    runtime_header_fns.set("pact_str_concat", 1)
    runtime_header_fns.set("pact_str_eq", 1)
    runtime_header_fns.set("pact_str_contains", 1)
    runtime_header_fns.set("pact_str_starts_with", 1)
    runtime_header_fns.set("pact_str_ends_with", 1)
    runtime_header_fns.set("pact_str_slice", 1)
    runtime_header_fns.set("pact_str_index_of", 1)
    runtime_header_fns.set("pact_sb_new", 1)
    runtime_header_fns.set("pact_sb_with_capacity", 1)
    runtime_header_fns.set("pact_sb_write", 1)
    runtime_header_fns.set("pact_sb_write_char", 1)
    runtime_header_fns.set("pact_sb_write_int", 1)
    runtime_header_fns.set("pact_sb_write_float", 1)
    runtime_header_fns.set("pact_sb_write_bool", 1)
    runtime_header_fns.set("pact_sb_to_str", 1)
    runtime_header_fns.set("pact_sb_len", 1)
    runtime_header_fns.set("pact_sb_capacity", 1)
    runtime_header_fns.set("pact_sb_clear", 1)
    runtime_header_fns.set("pact_sb_is_empty", 1)
    // runtime_core.h bytes functions
    runtime_header_fns.set("pact_bytes_new", 1)
    runtime_header_fns.set("pact_bytes_from_str", 1)
    runtime_header_fns.set("pact_bytes_push", 1)
    runtime_header_fns.set("pact_bytes_get", 1)
    runtime_header_fns.set("pact_bytes_set", 1)
    runtime_header_fns.set("pact_bytes_len", 1)
    runtime_header_fns.set("pact_bytes_is_empty", 1)
    runtime_header_fns.set("pact_bytes_concat", 1)
    runtime_header_fns.set("pact_bytes_slice", 1)
    runtime_header_fns.set("pact_bytes_to_str_checked", 1)
    runtime_header_fns.set("pact_bytes_to_hex", 1)
}

pub fn is_runtime_header_fn(name: Str) -> Bool {
    init_runtime_header_fns()
    runtime_header_fns.has(name)
}

pub fn c_safe_name(name: Str) -> Str {
    init_c_reserved()
    if c_reserved_set.has(name) {
        return "_pact_{name}"
    }
    name
}

pub fn c_fn_name(name: Str) -> Str {
    if mod_fn_prefix.has(name) {
        let prefix = mod_fn_prefix.get(name)
        if prefix != "" {
            return "pact_{prefix}_{name}"
        }
    }
    "pact_{name}"
}

pub fn c_type_c_name(name: Str) -> Str {
    if mod_type_prefix.has(name) {
        let prefix = mod_type_prefix.get(name)
        if prefix != "" {
            return "pact_{prefix}_{name}"
        }
    }
    "pact_{name}"
}

// Capture analysis: per-capture info (flat list) and per-closure start/count
pub type CaptureEntry {
    name: Str
    is_mut: Int
    tp_id: Int
}

pub type ClosureCapInfo {
    start: Int
    count: Int
}

pub let mut closure_captures: List[CaptureEntry] = []
pub let mut closure_cap_infos: List[ClosureCapInfo] = []

// Active closure context: set while emitting a closure body, -1 otherwise
pub let mut cg_closure_cap_start: Int = -1
pub let mut cg_closure_cap_count: Int = 0

// Variables in the outer scope that are heap-boxed because a closure captures them mutably
pub let mut mut_captured_vars: List[Str] = []

// Trait registry: maps trait name -> method names
pub type TraitEntry {
    name: Str
    method_sl: Int
}
pub let mut trait_entries: List[TraitEntry] = []

// Impl registry: maps (trait, type) -> method FnDef nodes
pub type ImplEntry {
    trait_name: Str
    type_name: Str
    methods_sl: Int
}
pub let mut impl_entries: List[ImplEntry] = []

// Builtin trait impl registry: maps (trait, ct_type) for builtin types
pub type BuiltinTraitImpl {
    trait_name: Str
    ct_type: Int
}
pub let mut builtin_trait_impls: List[BuiltinTraitImpl] = []

// From impl registry: (source_type, target_type) -> methods sublist
pub type FromImplEntry {
    source: Str
    target: Str
    method_sl: Int
}
pub let mut from_entries: List[FromImplEntry] = []

// TryFrom impl registry: (source_type, target_type) -> methods sublist
pub type TryFromImplEntry {
    source: Str
    target: Str
    method_sl: Int
}
pub let mut tryfrom_entries: List[TryFromImplEntry] = []

// Struct field type registry: (struct_name, field_name) -> field C type
pub type StructFieldEntry {
    struct_name: Str
    field_name: Str
    field_type: Int
    stype: Str
    tp_id: Int
}
pub let mut sf_entries: List[StructFieldEntry] = []

pub type StructFieldDefault {
    struct_name: Str
    field_name: Str
    default_node: Int
}
pub let mut struct_field_defaults: List[StructFieldDefault] = []

pub type StructFieldClosureSig {
    struct_name: Str
    field_name: Str
    sig: Str
}
pub let mut sf_closure_sigs: List[StructFieldClosureSig] = []

// Struct field list-element-type registry: for List[SomeStruct] fields
pub type StructFieldListElem {
    struct_name: Str
    field_name: Str
    elem_struct: Str
    elem_type: Int
}
pub let mut sf_list_elems: List[StructFieldListElem] = []

pub fn get_struct_field_list_elem(sname: Str, fname: Str) -> Str {
    let mut i = 0
    while i < sf_list_elems.len() {
        let e = sf_list_elems.get(i).unwrap()
        if e.struct_name == sname && e.field_name == fname {
            return e.elem_struct
        }
        i = i + 1
    }
    ""
}

pub fn get_struct_field_list_elem_type(sname: Str, fname: Str) -> Int {
    let mut i = 0
    while i < sf_list_elems.len() {
        let e = sf_list_elems.get(i).unwrap()
        if e.struct_name == sname && e.field_name == fname {
            return e.elem_type
        }
        i = i + 1
    }
    CT_INT
}

// @invariant registry
pub type StructInvariant {
    struct_name: Str
    expr_node: Int
}
pub let mut struct_invariants: List[StructInvariant] = []

// @derive(Serialize/Deserialize) registries
pub let mut derive_serialize_types: List[Str] = []
pub let mut derive_deserialize_types: List[Str] = []

pub type DeriveMethodEntry {
    type_name: Str
    method_name: Str
    ret_type: Int
}
pub let mut derive_method_entries: List[DeriveMethodEntry] = []

pub fn has_derive_method(type_name: Str, method: Str) -> Int {
    let mut i = 0
    while i < derive_method_entries.len() {
        let e = derive_method_entries.get(i).unwrap()
        if e.type_name == type_name && e.method_name == method {
            return 1
        }
        i = i + 1
    }
    0
}

fn get_derive_method_ret(type_name: Str, method: Str) -> Int {
    let mut i = 0
    while i < derive_method_entries.len() {
        let e = derive_method_entries.get(i).unwrap()
        if e.type_name == type_name && e.method_name == method {
            return e.ret_type
        }
        i = i + 1
    }
    CT_VOID
}

// Function AST node registry: fn_name -> fn_node for all functions
type FnNodeEntry {
    name: Str
    node: Int
}
let mut fn_node_registry: List[FnNodeEntry] = []

pub fn codegen_types_pool_len() -> Int {
    tp_kind.len()
}

pub fn codegen_fn_registry_len() -> Int {
    fn_node_registry.len()
}

pub fn reg_fn_node(name: Str, node: Int) {
    fn_node_registry.push(FnNodeEntry { name: name, node: node })
}

pub fn get_fn_node(name: Str) -> Int {
    let mut i = 0
    while i < fn_node_registry.len() {
        let entry = fn_node_registry.get(i).unwrap()
        if entry.name == name {
            return entry.node
        }
        i = i + 1
    }
    -1
}

// Generic function definition registry: fn_name -> fn_node for generic fns
pub type GenericFnEntry {
    name: Str
    node: Int
}
pub let mut generic_fns: List[GenericFnEntry] = []

// Mono function instances to emit: (base_fn_name, concrete_args)
type MonoFnInstance {
    base: Str
    args: Str
}
pub let mut mono_fns: List[MonoFnInstance] = []

// Generic monomorphic instance registry
type MonoInstance {
    base: Str
    args: Str
    c_name: Str
}
pub let mut mono_instances: List[MonoInstance] = []

pub let mut emitted_option_types: List[Int] = []
pub let mut emitted_result_types: List[Str] = []
pub let mut emitted_struct_option_types: List[Str] = []
pub let mut emitted_struct_result_types: List[Str] = []

type FnRetStructInner {
    name: Str
    ok_struct: Str
    err_struct: Str
}
pub let mut fn_ret_struct_inners: List[FnRetStructInner] = []
pub let mut emitted_iter_types: List[Int] = []
pub let mut emitted_range_iter: Int = 0
pub let mut emitted_str_iter: Int = 0

pub let mut emitted_map_iters: List[Int] = []
pub let mut emitted_filter_iters: List[Int] = []
pub let mut emitted_take_iters: List[Int] = []
pub let mut emitted_skip_iters: List[Int] = []
pub let mut emitted_chain_iters: List[Int] = []
pub let mut emitted_flat_map_iters: List[Int] = []

// Tuple type registry
type TupleEntry {
    c_name: Str
    arity: Int
    elem_types: Str
    elem_structs: Str
}
pub let mut emitted_tuple_set: Map[Str, Int] = Map()
pub let mut emitted_tuple_entries: List[TupleEntry] = []

// Assignment context for .into() type inference
pub let mut cg_let_target_type: Int = 0
pub let mut cg_let_target_name: Str = ""
pub let mut cg_let_target_ann: Int = -1

// Handler vtable field set by emit_handler_expr for emit_with_block
pub let mut cg_handler_vtable_field: Str = ""
pub let mut cg_handler_is_user_effect: Int = 0
// Tracks the current handler's vtable type and field for default delegation
pub let mut cg_in_handler_body: Int = 0
pub let mut cg_handler_body_vtable_type: Str = ""
pub let mut cg_handler_body_field: Str = ""
pub let mut cg_handler_body_is_ue: Int = 0
pub let mut cg_handler_body_idx: Int = 0

// Scope: unified variable tracking with parameterized type info.
// inner1: List elem, Option inner, Result ok, Map key, Iterator/Handle/Channel inner
// inner2: Result err, Map value
// sname: struct type, closure sig, Option inner_struct, Result ok_struct
// sname2: alias target (iter), list elem struct, Result err_struct, Map value_struct
// extra: iterator next_fn, list nested elem struct, option inner2 struct
type ScopeVar {
    name: Str
    ctype: Int
    is_mut: Int
    inner1: Int
    inner2: Int
    sname: Str
    sname2: Str
    extra: Str
    tp_id: Int
}

// Bridge: compute tp pool ID from CT_* flat fields
pub fn sv_tp(ctype: Int, inner1: Int, inner2: Int, sname: Str) -> Int {
    if ctype == CT_LIST {
        if inner1 >= 0 { return type_list(sv_tp(inner1, inner2, -1, sname)) }
        return type_list(type_int())
    }
    if ctype == CT_OPTION {
        if inner1 >= 0 { return type_option(sv_tp(inner1, inner2, -1, sname)) }
        return type_option(type_int())
    }
    if ctype == CT_RESULT {
        let ok = if inner1 >= 0 { sv_tp(inner1, -1, -1, "") } else { type_int() }
        let err = if inner2 >= 0 { sv_tp(inner2, -1, -1, "") } else { type_string() }
        return type_result(ok, err)
    }
    if ctype == CT_MAP {
        let k = if inner1 >= 0 { sv_tp(inner1, -1, -1, "") } else { type_string() }
        let v = if inner2 >= 0 { sv_tp(inner2, -1, -1, "") } else { type_int() }
        return type_map(k, v)
    }
    if ctype == CT_SET {
        let elem = if inner1 >= 0 { sv_tp(inner1, -1, -1, "") } else { type_string() }
        return type_set(elem)
    }
    if ctype == CT_ITERATOR {
        if inner1 >= 0 { return type_iterator(sv_tp(inner1, inner2, -1, sname)) }
        return type_iterator(type_int())
    }
    if ctype == CT_HANDLE {
        if inner1 >= 0 { return type_handle(sv_tp(inner1, inner2, -1, sname)) }
        return type_handle(type_int())
    }
    if ctype == CT_CHANNEL {
        if inner1 >= 0 { return type_channel(sv_tp(inner1, inner2, -1, sname)) }
        return type_channel(type_int())
    }
    if ctype == CT_CLOSURE { return type_closure(sname) }
    if ctype == CT_TAGGED_ENUM || ctype == CT_VOID {
        if sname != "" { return type_struct(sname) }
        return tp_alloc(ctype, -1, -1, "")
    }
    if ctype == CT_PTR {
        if inner1 >= 0 { return type_ptr(sv_tp(inner1, inner2, -1, sname)) }
        return type_ptr(type_int())
    }
    tp_alloc(ctype, -1, -1, "")
}
pub let mut scope_vars: List[ScopeVar] = []
pub let mut scope_frame_starts: List[Int] = []

// Function registry: parallel lists (fn name -> return type, param count)
type FnRegEntry {
    name: Str
    ret: Int
    effect_sl: Int
    tp_id: Int
}
pub let mut fn_regs: List[FnRegEntry] = []

// Function return struct type tracking
type FnRetStructEntry {
    name: Str
    stype: Str
}
pub let mut fn_ret_structs: List[FnRetStructEntry] = []

// Function return type tracking — unified struct
type RetType {
    name: Str
    kind: Int
    inner1: Int
    inner2: Int
    tp_id: Int
}

pub let mut fn_ret_types: List[RetType] = []

// Effect registry: name -> parent index (-1 = top-level)
type EffectEntry {
    name: Str
    parent: Int
}
pub let mut effect_entries: List[EffectEntry] = []

// User-defined effect registry
pub type UeEffect {
    name: Str
    handle: Str
}

pub type UeMethod {
    name: Str
    params: Str
    ret: Str
    effect_handle: Str
}

pub let mut ue_effects: List[UeEffect] = []
pub let mut ue_methods: List[UeMethod] = []

// @capabilities budget: allowed effects for the module (-1 = no budget)
pub let mut cap_budget_names: List[Str] = []
let mut cap_budget_active: Int = 0

// Current function being emitted (for effect propagation checking)
pub let mut cg_current_fn_name: Str = ""
pub let mut cg_current_fn_ret: Int = 0
let mut cg_current_fn_node: Int = -1
pub let mut cg_current_fn_option_inner: Int = 0

// Scratch space for tuple match scrutinee temps
pub let mut cg_program_node: Int = 0
pub let mut cg_uses_async: Int = 0
pub let mut cg_uses_sqlite: Int = 0
pub let mut cg_async_wrapper_counter: Int = 0

// Async scope tracking: stack of scope handle list variable names
pub let mut cg_async_scope_stack: List[Str] = []
pub let mut cg_async_scope_counter: Int = 0

pub type MatchScrutEntry {
    str_val: Str
    scrut_type: Int
}
pub let mut match_scruts: List[MatchScrutEntry] = []
pub let mut match_scrut_enum: Str = ""

// Debug mode: 0 = release (strip debug_assert), 1 = debug (emit checks)
pub let mut cg_debug_mode: Int = 0

// Trace mode: 0 = no trace instrumentation, 1 = emit trace enter/exit calls
pub let mut cg_trace_codegen: Int = 0

// Inlined runtime.h content; if non-empty, emitted directly instead of #include
pub let mut cg_runtime_header: Str = ""

pub fn push_scope() ! Codegen.Scope {
    scope_frame_starts.push(scope_vars.len())
}

pub fn pop_scope() ! Codegen.Scope {
    let start = scope_frame_starts.get(scope_frame_starts.len() - 1).unwrap()
    scope_frame_starts.pop()
    while scope_vars.len() > start {
        scope_vars.pop()
    }
}

pub fn set_var(name: Str, ctype: Int, is_mut: Int) ! Codegen.Scope {
    scope_vars.push(ScopeVar { name: name, ctype: ctype, is_mut: is_mut, inner1: -1, inner2: -1, sname: "", sname2: "", extra: "", tp_id: sv_tp(ctype, -1, -1, "") })
}

pub fn get_var_tp(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name {
            return sv.tp_id
        }
        i = i - 1
    }
    type_int()
}

pub fn get_var_type(name: Str) -> Int {
    tp_get_kind(get_var_tp(name))
}

fn get_var_mut(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name {
            return sv.is_mut
        }
        i = i - 1
    }
    0
}

fn get_sv_inner1(name: Str, ctype: Int) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == ctype {
            return tp_child1_kind(sv.tp_id)
        }
        i = i - 1
    }
    -1
}

fn get_sv_inner2(name: Str, ctype: Int) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == ctype {
            return tp_child2_kind(sv.tp_id)
        }
        i = i - 1
    }
    -1
}

fn get_sv_sname(name: Str, ctype: Int) -> Str {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == ctype {
            return sv.sname
        }
        i = i - 1
    }
    ""
}

fn get_sv_sname2(name: Str, ctype: Int) -> Str {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == ctype {
            return sv.sname2
        }
        i = i - 1
    }
    ""
}

fn get_sv_extra(name: Str, ctype: Int) -> Str {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == ctype {
            return sv.extra
        }
        i = i - 1
    }
    ""
}

fn update_sv_sname(name: Str, ctype: Int, val: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == ctype {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: sv.inner2, sname: val, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, sv.inner1, sv.inner2, val) })
            return
        }
        i = i - 1
    }
}

fn update_sv_sname2(name: Str, ctype: Int, val: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == ctype {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: sv.inner2, sname: sv.sname, sname2: val, extra: sv.extra, tp_id: sv.tp_id })
            return
        }
        i = i - 1
    }
}

fn set_var_full(name: Str, ctype: Int, is_mut: Int, inner1: Int, inner2: Int, sname: Str, sname2: Str, extra: Str) ! Codegen.Scope {
    scope_vars.push(ScopeVar { name: name, ctype: ctype, is_mut: is_mut, inner1: inner1, inner2: inner2, sname: sname, sname2: sname2, extra: extra, tp_id: sv_tp(ctype, inner1, inner2, sname) })
}

pub fn is_mut_captured(name: Str) -> Int {
    let mut i = 0
    while i < mut_captured_vars.len() {
        if mut_captured_vars.get(i).unwrap() == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn get_capture_index(name: Str) -> Int {
    if cg_closure_cap_start < 0 {
        return -1
    }
    let mut i = 0
    while i < cg_closure_cap_count {
        if closure_captures.get(cg_closure_cap_start + i).unwrap().name == name {
            return i
        }
        i = i + 1
    }
    -1
}

pub fn capture_cast_expr(idx: Int) -> Str {
    let ct = tp_get_kind(closure_captures.get(cg_closure_cap_start + idx).unwrap().tp_id)
    if ct == CT_INT {
        "(int64_t)(intptr_t)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_FLOAT {
        "*(double*)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_STRING {
        "(const char*)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_BOOL {
        "(int)(intptr_t)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_LIST {
        "(pact_list*)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_MAP {
        "(pact_map*)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_BYTES {
        "(pact_bytes*)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_CLOSURE {
        "(pact_closure*)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_VOID {
        let sname = tp_get_sname(closure_captures.get(cg_closure_cap_start + idx).unwrap().tp_id)
        if sname != "" {
            "(*(({c_type_c_name(sname)}*)pact_closure_get_capture(__self, {idx})))"
        } else {
            "pact_closure_get_capture(__self, {idx})"
        }
    } else {
        "pact_closure_get_capture(__self, {idx})"
    }
}

pub fn reg_fn(name: Str, ret: Int) ! Codegen.Register {
    fn_regs.push(FnRegEntry { name: name, ret: ret, effect_sl: -1, tp_id: sv_tp(ret, -1, -1, "") })
}

pub fn reg_fn_with_effects(name: Str, ret: Int, effects_sl: Int) ! Codegen.Register {
    fn_regs.push(FnRegEntry { name: name, ret: ret, effect_sl: effects_sl, tp_id: sv_tp(ret, -1, -1, "") })
}

fn get_fn_effect_sl(name: Str) -> Int {
    let mut i = 0
    while i < fn_regs.len() {
        let fr = fn_regs.get(i).unwrap()
        if fr.name == name {
            return fr.effect_sl
        }
        i = i + 1
    }
    -1
}

pub fn reg_fn_struct_ret(name: Str, stype: Str) ! Codegen.Register {
    fn_ret_structs.push(FnRetStructEntry { name: name, stype: stype })
}

pub fn get_fn_ret_struct(name: Str) -> Str {
    let mut i = fn_ret_structs.len() - 1
    while i >= 0 {
        let frs = fn_ret_structs.get(i).unwrap()
        if frs.name == name {
            return frs.stype
        }
        i = i - 1
    }
    ""
}

pub fn reg_fn_ret_type(name: Str, kind: Int, inner1: Int, inner2: Int) ! Codegen.Register {
    fn_ret_types.push(RetType { name: name, kind: kind, inner1: inner1, inner2: inner2, tp_id: sv_tp(kind, inner1, inner2, "") })
}

pub fn get_fn_ret_type(name: Str) -> RetType {
    let mut i = fn_ret_types.len() - 1
    while i >= 0 {
        let rt = fn_ret_types.get(i).unwrap()
        if rt.name == name {
            return rt
        }
        i = i - 1
    }
    RetType { name: "", kind: CT_VOID, inner1: -1, inner2: -1, tp_id: sv_tp(CT_VOID, -1, -1, "") }
}

pub fn resolve_option_inner_from_ann(fn_node: Int) -> Int {
    let ta = np_type_ann.get(fn_node).unwrap()
    if ta != -1 {
        let elems_sl = np_elements.get(ta).unwrap()
        if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
            let inner_ann = sublist_get(elems_sl, 0)
            let inner_name = np_name.get(inner_ann).unwrap()
            return type_from_name(inner_name)
        }
    }
    CT_INT
}

pub fn resolve_ret_type_from_ann(fn_node: Int) -> Str {
    let ret_str = np_return_type.get(fn_node).unwrap()
    let ta = np_type_ann.get(fn_node).unwrap()
    if ret_str == "Result" {
        if ta != -1 {
            let elems_sl = np_elements.get(ta).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
                let ok_ann = sublist_get(elems_sl, 0)
                let err_ann = sublist_get(elems_sl, 1)
                let ok_name = np_name.get(ok_ann).unwrap()
                let err_name = np_name.get(err_ann).unwrap()
                let ok_t = type_from_name(ok_name)
                let err_t = type_from_name(err_name)
                let ok_is_type = is_struct_type(ok_name) != 0 || is_enum_type(ok_name) != 0
                let err_is_type = is_struct_type(err_name) != 0 || is_enum_type(err_name) != 0
                if ok_is_type || err_is_type {
                    let ok_tag = if ok_is_type { ok_name } else { c_type_tag(ok_t) }
                    let err_tag = if err_is_type { err_name } else { c_type_tag(err_t) }
                    return "pact_Result_{ok_tag}_{err_tag}"
                }
                return result_c_type(ok_t, err_t)
            }
        }
        return result_c_type(CT_INT, CT_STRING)
    }
    if ret_str == "Option" {
        if ta != -1 {
            let elems_sl = np_elements.get(ta).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
                let inner_ann = sublist_get(elems_sl, 0)
                let inner_name = np_name.get(inner_ann).unwrap()
                let inner_t = type_from_name(inner_name)
                if is_struct_type(inner_name) != 0 || is_enum_type(inner_name) != 0 {
                    return "pact_Option_{inner_name}"
                }
                if is_compound_ct(inner_t) != 0 {
                    let compound_name = compound_name_from_ann(inner_ann)
                    return struct_option_c_type(compound_name)
                }
                return option_c_type(inner_t)
            }
        }
        return option_c_type(CT_INT)
    }
    if ret_str == "Tuple" {
        if ta != -1 {
            let tn = resolve_tuple_ann(ta).unwrap()
            return c_type_c_name(tn)
        }
    }
    if ret_str == "Ptr" {
        if ta != -1 {
            let elems_sl = np_elements.get(ta).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) > 0 {
                let inner_ann = sublist_get(elems_sl, 0)
                let inner_name = np_name.get(inner_ann).unwrap()
                return "{ptr_inner_c_type(inner_name)}*"
            }
        }
        return "void*"
    }
    ""
}

pub fn resolve_tuple_ann(ta: Int) -> Option[Str] {
    let elems_sl = np_elements.get(ta).unwrap()
    if elems_sl == -1 {
        return None
    }
    let arity = sublist_length(elems_sl)
    let mut tags = ""
    let mut elem_types_enc = ""
    let mut elem_structs_enc = ""
    let mut i = 0
    while i < arity {
        let elem_ann = sublist_get(elems_sl, i)
        let elem_name = np_name.get(elem_ann).unwrap()
        let elem_t = type_from_name(elem_name)
        if i > 0 {
            tags = tags.concat("_")
            elem_types_enc = elem_types_enc.concat(",")
            elem_structs_enc = elem_structs_enc.concat(",")
        }
        if is_struct_type(elem_name) != 0 || is_enum_type(elem_name) != 0 {
            tags = tags.concat(elem_name)
            elem_structs_enc = elem_structs_enc.concat(elem_name)
        } else {
            tags = tags.concat(c_type_tag(elem_t))
            elem_structs_enc = elem_structs_enc.concat("-")
        }
        elem_types_enc = elem_types_enc.concat("{elem_t}")
        i = i + 1
    }
    let tup_name = tuple_c_type_name(tags, arity)
    ensure_tuple_type(tup_name, arity, elem_types_enc, elem_structs_enc)
    Some(tup_name)
}

pub fn reg_fn_ret_from_ann(name: Str, fn_node: Int) ! Codegen.Register {
    let ret_str = np_return_type.get(fn_node).unwrap()
    let ta = np_type_ann.get(fn_node).unwrap()
    if ret_str == "Result" {
        if ta != -1 {
            let elems_sl = np_elements.get(ta).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
                let ok_ann = sublist_get(elems_sl, 0)
                let err_ann = sublist_get(elems_sl, 1)
                let ok_name = np_name.get(ok_ann).unwrap()
                let err_name = np_name.get(err_ann).unwrap()
                let ok_t = type_from_name(ok_name)
                let err_t = type_from_name(err_name)
                let ok_is_type = is_struct_type(ok_name) != 0 || is_enum_type(ok_name) != 0
                let err_is_type = is_struct_type(err_name) != 0 || is_enum_type(err_name) != 0
                reg_fn_ret_type(name, CT_RESULT, ok_t, err_t)
                if ok_is_type || err_is_type {
                    let ok_s = if ok_is_type { ok_name } else { "" }
                    let err_s = if err_is_type { err_name } else { "" }
                    fn_ret_struct_inners.push(FnRetStructInner { name: name, ok_struct: ok_s, err_struct: err_s })
                    let ok_tag = if ok_is_type { ok_name } else { c_type_tag(ok_t) }
                    let err_tag = if err_is_type { err_name } else { c_type_tag(err_t) }
                    ensure_struct_result_type(ok_tag, err_tag)
                } else {
                    ensure_result_type(ok_t, err_t)
                }
            }
        } else {
            reg_fn_ret_type(name, CT_RESULT, CT_INT, CT_STRING)
            ensure_result_type(CT_INT, CT_STRING)
        }
    }
    if ret_str == "Option" {
        if ta != -1 {
            let elems_sl = np_elements.get(ta).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
                let inner_ann = sublist_get(elems_sl, 0)
                let inner_name = np_name.get(inner_ann).unwrap()
                let inner_t = type_from_name(inner_name)
                reg_fn_ret_type(name, CT_OPTION, inner_t, -1)
                if is_struct_type(inner_name) != 0 || is_enum_type(inner_name) != 0 {
                    fn_ret_struct_inners.push(FnRetStructInner { name: name, ok_struct: inner_name, err_struct: "" })
                    ensure_struct_option_type(inner_name)
                } else if is_compound_ct(inner_t) != 0 {
                    let compound_name = compound_name_from_ann(inner_ann)
                    fn_ret_struct_inners.push(FnRetStructInner { name: name, ok_struct: compound_name, err_struct: "" })
                    ensure_struct_option_type(compound_name)
                } else {
                    ensure_option_type(inner_t)
                }
            }
        } else {
            reg_fn_ret_type(name, CT_OPTION, CT_INT, -1)
            ensure_option_type(CT_INT)
        }
    }
    if ret_str == "List" && ta != -1 {
        let elems_sl = np_elements.get(ta).unwrap()
        if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
            let elem_ann = sublist_get(elems_sl, 0)
            let elem_name = np_name.get(elem_ann).unwrap()
            let elem_t = type_from_name(elem_name)
            reg_fn_ret_type(name, CT_LIST, elem_t, -1)
            if is_struct_type(elem_name) != 0 || is_enum_type(elem_name) != 0 {
                fn_ret_struct_inners.push(FnRetStructInner { name: name, ok_struct: elem_name, err_struct: "" })
            }
        }
    }
    if ret_str == "Map" && ta != -1 {
        let elems_sl = np_elements.get(ta).unwrap()
        if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
            let key_ann = sublist_get(elems_sl, 0)
            let val_ann = sublist_get(elems_sl, 1)
            let key_t = type_from_name(np_name.get(key_ann).unwrap())
            let val_t = type_from_name(np_name.get(val_ann).unwrap())
            reg_fn_ret_type(name, CT_MAP, key_t, val_t)
        }
    }
    if ret_str == "Tuple" && ta != -1 {
        let tup_c_name = resolve_tuple_ann(ta)
        if tup_c_name.is_some() {
            fn_ret_structs.push(FnRetStructEntry { name: name, stype: tup_c_name.unwrap() })
        }
    }
}

pub fn reg_fn_ret_struct_inner(name: Str, ok_s: Str, err_s: Str) {
    fn_ret_struct_inners.push(FnRetStructInner { name: name, ok_struct: ok_s, err_struct: err_s })
}

pub fn get_fn_ret_struct_inner(name: Str) -> FnRetStructInner {
    let mut i = fn_ret_struct_inners.len() - 1
    while i >= 0 {
        let fsi = fn_ret_struct_inners.get(i).unwrap()
        if fsi.name == name {
            return fsi
        }
        i = i - 1
    }
    FnRetStructInner { name: "", ok_struct: "", err_struct: "" }
}

pub fn reg_effect(name: Str, parent: Int) -> Int ! Codegen.Register {
    let idx = effect_entries.len()
    effect_entries.push(EffectEntry { name: name, parent: parent })
    idx
}

fn get_effect_idx(name: Str) -> Int {
    let mut i = 0
    while i < effect_entries.len() {
        if effect_entries.get(i).unwrap().name == name {
            return i
        }
        i = i + 1
    }
    -1
}

fn effect_satisfies(caller_effect: Str, callee_effect: Str) -> Int {
    if caller_effect == callee_effect {
        return 1
    }
    let callee_idx = get_effect_idx(callee_effect)
    if callee_idx == -1 {
        return 0
    }
    let parent_idx = effect_entries.get(callee_idx).unwrap().parent
    if parent_idx == -1 {
        return 0
    }
    let parent_name = effect_entries.get(parent_idx).unwrap().name
    if parent_name == caller_effect {
        return 1
    }
    0
}

pub fn check_effect_propagation(callee_name: Str) ! Diag.Report {
    if cg_current_fn_name == "main" || cg_current_fn_name.starts_with("__test_") {
        return
    }
    let callee_sl = get_fn_effect_sl(callee_name)
    if callee_sl == -1 {
        return
    }
    let callee_count = sublist_length(callee_sl)
    if callee_count == 0 {
        return
    }
    let caller_sl = get_fn_effect_sl(cg_current_fn_name)
    let mut ci = 0
    while ci < callee_count {
        let callee_eff_node = sublist_get(callee_sl, ci)
        let callee_eff = np_name.get(callee_eff_node).unwrap()
        let mut satisfied = 0
        if caller_sl != -1 {
            let caller_count = sublist_length(caller_sl)
            let mut ki = 0
            while ki < caller_count {
                let caller_eff_node = sublist_get(caller_sl, ki)
                let caller_eff = np_name.get(caller_eff_node).unwrap()
                if effect_satisfies(caller_eff, callee_eff) != 0 {
                    satisfied = 1
                }
                ki = ki + 1
            }
        }
        if satisfied == 0 {
            diag_error_no_loc("UndeclaredEffect", "E0500", "function '{callee_name}' requires effect '{callee_eff}' but caller '{cg_current_fn_name}' does not declare it", "add '! {callee_eff}' to the function signature of '{cg_current_fn_name}'")
            diag_set_last_fix("insert", "! {callee_eff}")
        }
        ci = ci + 1
    }
}

pub fn check_capabilities_budget(fn_name: Str, effects_sl: Int) ! Diag.Report {
    if cap_budget_active == 0 {
        return
    }
    if fn_name == "main" || fn_name.starts_with("__test_") {
        return
    }
    if effects_sl == -1 {
        return
    }
    let count = sublist_length(effects_sl)
    let mut ei = 0
    while ei < count {
        let eff_node = sublist_get(effects_sl, ei)
        let eff_name = np_name.get(eff_node).unwrap()
        let mut allowed = 0
        let mut bi = 0
        while bi < cap_budget_names.len() {
            let budget_eff = cap_budget_names.get(bi).unwrap()
            if effect_satisfies(budget_eff, eff_name) != 0 {
                allowed = 1
            }
            bi = bi + 1
        }
        if allowed == 0 {
            diag_error_no_loc("InsufficientCapability", "E0501", "function '{fn_name}' uses effect '{eff_name}' which is not in @capabilities budget", "add the effect to @capabilities")
            diag_set_last_fix("insert", "{eff_name}")
        }
        ei = ei + 1
    }
}

pub fn init_builtin_effects() ! Codegen.Register {
    let io_idx = reg_effect("IO", -1)
    reg_effect("IO.Print", io_idx)
    reg_effect("IO.Log", io_idx)
    let fs_idx = reg_effect("FS", -1)
    reg_effect("FS.Read", fs_idx)
    reg_effect("FS.Write", fs_idx)
    reg_effect("FS.Delete", fs_idx)
    reg_effect("FS.Watch", fs_idx)
    let net_idx = reg_effect("Net", -1)
    reg_effect("Net.Connect", net_idx)
    reg_effect("Net.Listen", net_idx)
    reg_effect("Net.DNS", net_idx)
    let db_idx = reg_effect("DB", -1)
    reg_effect("DB.Read", db_idx)
    reg_effect("DB.Write", db_idx)
    reg_effect("DB.Admin", db_idx)
    let env_idx = reg_effect("Env", -1)
    reg_effect("Env.Read", env_idx)
    reg_effect("Env.Write", env_idx)
    let time_idx = reg_effect("Time", -1)
    reg_effect("Time.Read", time_idx)
    reg_effect("Time.Sleep", time_idx)
    reg_effect("Rand", -1)
    let crypto_idx = reg_effect("Crypto", -1)
    reg_effect("Crypto.Hash", crypto_idx)
    reg_effect("Crypto.Sign", crypto_idx)
    reg_effect("Crypto.Encrypt", crypto_idx)
    reg_effect("Crypto.Decrypt", crypto_idx)
    let proc_idx = reg_effect("Process", -1)
    reg_effect("Process.Spawn", proc_idx)
    reg_effect("Process.Signal", proc_idx)
    let async_idx = reg_effect("Async", -1)
    reg_effect("Async.Spawn", async_idx)
    reg_effect("Async.Channel", async_idx)
}

fn get_ue_handle(effect_name: Str) -> Str {
    let mut i = 0
    while i < ue_effects.len() {
        let ue = ue_effects.get(i).unwrap()
        if ue.name == effect_name {
            return ue.handle
        }
        i = i + 1
    }
    ""
}

fn get_ue_top_for_handle(handle: Str) -> Str {
    let mut i = 0
    while i < ue_effects.len() {
        let ue = ue_effects.get(i).unwrap()
        if ue.handle == handle {
            return ue.name
        }
        i = i + 1
    }
    ""
}

pub fn is_user_effect_handle(name: Str) -> Int {
    let mut i = 0
    while i < ue_effects.len() {
        if ue_effects.get(i).unwrap().handle == name {
            return 1
        }
        i = i + 1
    }
    0
}

fn ue_has_method(handle: Str, method: Str) -> Int {
    let mut i = 0
    while i < ue_methods.len() {
        let uem = ue_methods.get(i).unwrap()
        if uem.effect_handle == handle && uem.name == method {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn is_fn_registered(name: Str) -> Int {
    let mut i = 0
    while i < fn_regs.len() {
        if fn_regs.get(i).unwrap().name == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn get_fn_ret(name: Str) -> Int {
    let mut i = 0
    while i < fn_regs.len() {
        let fr = fn_regs.get(i).unwrap()
        if fr.name == name {
            return tp_get_kind(fr.tp_id)
        }
        i = i + 1
    }
    CT_VOID
}

pub fn set_list_elem_type(name: Str, elem_type: Int) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_LIST {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: elem_type, inner2: sv.inner2, sname: sv.sname, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, elem_type, sv.inner2, sv.sname) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_LIST, is_mut: 0, inner1: elem_type, inner2: -1, sname: "", sname2: "", extra: "", tp_id: sv_tp(CT_LIST, elem_type, -1, "") })
}

pub fn get_list_elem_type(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_LIST {
            return tp_child1_kind(sv.tp_id)
        }
        i = i - 1
    }
    -1
}

pub fn set_list_nested_elem_type(name: Str, nested_type: Int) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_LIST {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: nested_type, sname: sv.sname, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, sv.inner1, nested_type, sv.sname) })
            return
        }
        i = i - 1
    }
}

pub fn get_list_nested_elem_type(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_LIST {
            let c1 = tp_get_child1(sv.tp_id)
            if c1 >= 0 && tp_get_kind(c1) == CT_LIST {
                return tp_child1_kind(c1)
            }
            return -1
        }
        i = i - 1
    }
    -1
}

pub fn set_list_nested_elem_struct(name: Str, struct_name: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_LIST {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: sv.inner2, sname: sv.sname, sname2: sv.sname2, extra: struct_name, tp_id: sv.tp_id })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_LIST, is_mut: 0, inner1: -1, inner2: -1, sname: "", sname2: "", extra: struct_name, tp_id: sv_tp(CT_LIST, -1, -1, "") })
}

pub fn get_list_nested_elem_struct(name: Str) -> Str {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_LIST && sv.extra != "" {
            return sv.extra
        }
        i = i - 1
    }
    ""
}

pub fn set_list_elem_struct(name: Str, struct_name: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_LIST {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: sv.inner2, sname: sv.sname, sname2: struct_name, extra: sv.extra, tp_id: sv.tp_id })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_LIST, is_mut: 0, inner1: -1, inner2: -1, sname: "", sname2: struct_name, extra: "", tp_id: sv_tp(CT_LIST, -1, -1, "") })
}

pub fn get_list_elem_struct(name: Str) -> Str {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_LIST && sv.sname2 != "" {
            return sv.sname2
        }
        i = i - 1
    }
    ""
}

pub fn set_set_elem_type(name: Str, elem_type: Int) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_SET {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: elem_type, inner2: -1, sname: sv.sname, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, elem_type, -1, sv.sname) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_SET, is_mut: 0, inner1: elem_type, inner2: -1, sname: "", sname2: "", extra: "", tp_id: sv_tp(CT_SET, elem_type, -1, "") })
}

pub fn get_set_elem_type(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_SET {
            let c1k = tp_child1_kind(sv.tp_id)
            if c1k >= 0 { return c1k }
            return CT_STRING
        }
        i = i - 1
    }
    if cg_closure_cap_start >= 0 {
        let mut ci = 0
        while ci < cg_closure_cap_count {
            let cap = closure_captures.get(cg_closure_cap_start + ci).unwrap()
            if cap.name == name && tp_get_kind(cap.tp_id) == CT_SET {
                let c1k = tp_child1_kind(cap.tp_id)
                if c1k >= 0 { return c1k }
                return CT_STRING
            }
            ci = ci + 1
        }
    }
    CT_STRING
}

pub fn set_map_types(name: Str, key_type: Int, value_type: Int) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_MAP {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: key_type, inner2: value_type, sname: sv.sname, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, key_type, value_type, sv.sname) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_MAP, is_mut: 0, inner1: key_type, inner2: value_type, sname: "", sname2: "", extra: "", tp_id: sv_tp(CT_MAP, key_type, value_type, "") })
}

fn get_map_key_type(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_MAP {
            let c1k = tp_child1_kind(sv.tp_id)
            if c1k >= 0 { return c1k }
            return CT_STRING
        }
        i = i - 1
    }
    if cg_closure_cap_start >= 0 {
        let mut ci = 0
        while ci < cg_closure_cap_count {
            let cap = closure_captures.get(cg_closure_cap_start + ci).unwrap()
            if cap.name == name && tp_get_kind(cap.tp_id) == CT_MAP {
                let c1k = tp_child1_kind(cap.tp_id)
                if c1k >= 0 { return c1k }
                return CT_STRING
            }
            ci = ci + 1
        }
    }
    CT_STRING
}

pub fn get_map_value_type(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_MAP {
            let c2k = tp_child2_kind(sv.tp_id)
            if c2k >= 0 { return c2k }
            return CT_INT
        }
        i = i - 1
    }
    if cg_closure_cap_start >= 0 {
        let mut ci = 0
        while ci < cg_closure_cap_count {
            let cap = closure_captures.get(cg_closure_cap_start + ci).unwrap()
            if cap.name == name && tp_get_kind(cap.tp_id) == CT_MAP {
                let c2k = tp_child2_kind(cap.tp_id)
                if c2k >= 0 { return c2k }
                return CT_INT
            }
            ci = ci + 1
        }
    }
    CT_INT
}

fn set_map_value_struct(name: Str, struct_name: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_MAP {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: sv.inner2, sname: sv.sname, sname2: struct_name, extra: sv.extra, tp_id: sv.tp_id })
            return
        }
        i = i - 1
    }
}

fn get_map_value_struct(name: Str) -> Str {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_MAP {
            return sv.sname2
        }
        i = i - 1
    }
    ""
}

pub fn is_struct_type(name: Str) -> Int {
    struct_reg_set.has(name)
}

pub fn closure_sig_ret_part(sig: Str) -> Str {
    let mut ret_end = 0
    while ret_end < sig.len() && sig.char_at(ret_end) != 40 {
        ret_end = ret_end + 1
    }
    sig.substring(0, ret_end)
}

pub fn closure_ret_ct(ret_part: Str) -> Int {
    if ret_part == "int64_t" { return CT_INT }
    if ret_part == "double" { return CT_FLOAT }
    if ret_part == "const char*" { return CT_STRING }
    if ret_part == "int" { return CT_BOOL }
    CT_VOID
}

pub fn resolve_struct_from_c_name(cname: Str) -> Str {
    if struct_reg_set.has(cname) { return cname }
    let mut i = 0
    while i < cname.len() {
        if cname.char_at(i) == 95 {
            let suffix = cname.substring(i + 1, cname.len() - i - 1)
            if struct_reg_set.has(suffix) {
                return suffix
            }
        }
        i = i + 1
    }
    ""
}

pub fn is_enum_type(name: Str) -> Int {
    enum_reg_set.has(name)
}

pub fn resolve_variant(name: Str) -> Str {
    let mut i = 0
    while i < enum_variants.len() {
        let evar = enum_variants.get(i).unwrap()
        if evar.name == name {
            return enum_regs.get(evar.enum_idx).unwrap().name
        }
        i = i + 1
    }
    ""
}

pub fn get_var_enum(name: Str) -> Str {
    let mut i = 0
    while i < var_enums.len() {
        let ve = var_enums.get(i).unwrap()
        if ve.name == name {
            return ve.enum_type
        }
        i = i + 1
    }
    ""
}

pub fn is_data_enum(name: Str) -> Int {
    let mut i = 0
    while i < enum_regs.len() {
        let ereg = enum_regs.get(i).unwrap()
        if ereg.name == name {
            return ereg.has_data
        }
        i = i + 1
    }
    0
}

pub fn get_variant_index(enum_name: Str, variant_name: Str) -> Int {
    let mut i = 0
    while i < enum_variants.len() {
        let evar = enum_variants.get(i).unwrap()
        if evar.name == variant_name {
            if enum_regs.get(evar.enum_idx).unwrap().name == enum_name {
                return i
            }
        }
        i = i + 1
    }
    -1
}

pub fn get_variant_tag(enum_name: Str, variant_name: Str) -> Int {
    let mut _tag = 0
    let mut i = 0
    while i < enum_variants.len() {
        let evar = enum_variants.get(i).unwrap()
        if enum_regs.get(evar.enum_idx).unwrap().name == enum_name {
            if evar.name == variant_name {
                return _tag
            }
            _tag = _tag + 1
        }
        i = i + 1
    }
    -1
}

pub fn get_variant_field_count(variant_idx: Int) -> Int {
    if variant_idx < 0 || variant_idx >= enum_variants.len() {
        return 0
    }
    enum_variants.get(variant_idx).unwrap().field_count
}

pub fn get_variant_field_name(variant_idx: Int, field_idx: Int) -> Option[Str] {
    let names_str = enum_variants.get(variant_idx).unwrap().field_names
    if names_str == "" {
        return None
    }
    let mut _seg_start = 0
    let mut _seg_idx = 0
    let mut i = 0
    while i <= names_str.len() {
        if i == names_str.len() || names_str.char_at(i) == 44 {
            if _seg_idx == field_idx {
                return Some(names_str.substr(_seg_start, i - _seg_start))
            }
            _seg_start = i + 1
            _seg_idx = _seg_idx + 1
        }
        i = i + 1
    }
    None
}

pub fn get_variant_field_type_str(variant_idx: Int, field_idx: Int) -> Option[Str] {
    let types_str = enum_variants.get(variant_idx).unwrap().field_types
    if types_str == "" {
        return None
    }
    let mut _seg_start = 0
    let mut _seg_idx = 0
    let mut i = 0
    while i <= types_str.len() {
        if i == types_str.len() || types_str.char_at(i) == 44 {
            if _seg_idx == field_idx {
                return Some(types_str.substr(_seg_start, i - _seg_start))
            }
            _seg_start = i + 1
            _seg_idx = _seg_idx + 1
        }
        i = i + 1
    }
    None
}

pub fn get_fn_enum_ret(name: Str) -> Str {
    let mut i = 0
    while i < fn_enum_rets.len() {
        let fe = fn_enum_rets.get(i).unwrap()
        if fe.name == name {
            return fe.enum_type
        }
        i = i + 1
    }
    ""
}

pub fn set_var_struct(name: Str, type_name: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) != CT_CLOSURE {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: sv.inner2, sname: type_name, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, sv.inner1, sv.inner2, type_name) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_VOID, is_mut: 0, inner1: -1, inner2: -1, sname: type_name, sname2: "", extra: "", tp_id: sv_tp(CT_VOID, -1, -1, type_name) })
}

pub fn get_var_struct(name: Str) -> Str {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) != CT_CLOSURE {
            return sv.sname
        }
        i = i - 1
    }
    ""
}

pub fn get_struct_field_type(sname: Str, fname: Str) -> Int {
    let mut i = 0
    while i < sf_entries.len() {
        let sf = sf_entries.get(i).unwrap()
        if sf.struct_name == sname && sf.field_name == fname {
            return tp_get_kind(sf.tp_id)
        }
        i = i + 1
    }
    CT_VOID
}

pub fn get_struct_field_stype(sname: Str, fname: Str) -> Str {
    let mut i = 0
    while i < sf_entries.len() {
        let sf = sf_entries.get(i).unwrap()
        if sf.struct_name == sname && sf.field_name == fname {
            return tp_get_sname(sf.tp_id)
        }
        i = i + 1
    }
    ""
}

pub fn get_struct_field_tp_id(sname: Str, fname: Str) -> Int {
    let mut i = 0
    while i < sf_entries.len() {
        let sf = sf_entries.get(i).unwrap()
        if sf.struct_name == sname && sf.field_name == fname {
            return sf.tp_id
        }
        i = i + 1
    }
    -1
}

pub fn set_var_closure(name: Str, sig: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_CLOSURE {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: sv.inner2, sname: sig, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, sv.inner1, sv.inner2, sig) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_CLOSURE, is_mut: 0, inner1: -1, inner2: -1, sname: sig, sname2: "", extra: "", tp_id: sv_tp(CT_CLOSURE, -1, -1, sig) })
}

pub fn get_var_closure_sig(name: Str) -> Str {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_CLOSURE {
            return tp_get_sname(sv.tp_id)
        }
        i = i - 1
    }
    ""
}

pub fn get_struct_field_closure_sig(struct_name: Str, field_name: Str) -> Str {
    let mut i = 0
    while i < sf_closure_sigs.len() {
        let e = sf_closure_sigs.get(i).unwrap()
        if e.struct_name == struct_name && e.field_name == field_name {
            return e.sig
        }
        i = i + 1
    }
    ""
}

pub fn build_closure_sig_from_type_ann(ta: Int) -> Str {
    let ret_name = np_return_type.get(ta).unwrap()
    let ret_type = type_from_name(ret_name)
    let elems_sl = np_elements.get(ta).unwrap()
    let mut sig_params = "const pact_closure*"
    if elems_sl != -1 && sublist_length(elems_sl) > 0 {
        let mut i = 0
        while i < sublist_length(elems_sl) {
            let elem = sublist_get(elems_sl, i)
            let ename = np_name.get(elem).unwrap()
            sig_params = sig_params.concat(", ")
            if is_enum_type(ename) != 0 {
                sig_params = sig_params.concat(c_type_c_name(ename))
            } else if is_struct_type(ename) != 0 {
                sig_params = sig_params.concat(c_type_c_name(ename))
            } else {
                sig_params = sig_params.concat(c_type_str(type_from_name(ename)))
            }
            i = i + 1
        }
    }
    let mut ret_str = resolve_ret_type_from_ann(ta)
    if ret_str == "" {
        ret_str = c_type_str(ret_type)
        if is_struct_type(ret_name) != 0 {
            ret_str = c_type_c_name(ret_name)
        } else if is_enum_type(ret_name) != 0 {
            ret_str = c_type_c_name(ret_name)
        }
    }
    "{ret_str}(*)({sig_params})"
}

pub fn is_generic_fn(name: Str) -> Int {
    let mut i = 0
    while i < generic_fns.len() {
        if generic_fns.get(i).unwrap().name == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn get_generic_fn_node(name: Str) -> Int {
    let mut i = 0
    while i < generic_fns.len() {
        let gf = generic_fns.get(i).unwrap()
        if gf.name == name {
            return gf.node
        }
        i = i + 1
    }
    -1
}

pub fn register_mono_fn(base: Str, args: Str) ! Codegen.Register {
    let mut i = 0
    while i < mono_fns.len() {
        let mf = mono_fns.get(i).unwrap()
        if mf.base == base && mf.args == args {
            return
        }
        i = i + 1
    }
    mono_fns.push(MonoFnInstance { base: base, args: args })
}

pub fn infer_fn_type_args_from_types(fn_node: Int, arg_types: List[Int], arg_elem_types: List[Int], arg_closure_sigs: List[Str]) -> Option[Str] {
    let tparams_sl = np_type_params.get(fn_node).unwrap()
    if tparams_sl == -1 {
        return None
    }
    let num_params = sublist_length(tparams_sl)
    if num_params == 0 {
        return None
    }
    let fn_params_sl = np_params.get(fn_node).unwrap()
    if fn_params_sl == -1 {
        return None
    }
    let mut args = ""
    let mut pi = 0
    while pi < num_params {
        let param_name = np_name.get(sublist_get(tparams_sl, pi)).unwrap()
        let mut resolved = "Void"
        let mut fi = 0
        while fi < sublist_length(fn_params_sl) && fi < arg_types.len() {
            let p = sublist_get(fn_params_sl, fi)
            let ptype = np_type_name.get(p).unwrap()
            if ptype == param_name {
                resolved = type_name_from_ct(arg_types.get(fi).unwrap())
            } else if ptype == "List" {
                let ta = np_type_ann.get(p).unwrap()
                if ta != -1 {
                    let elems_sl = np_elements.get(ta).unwrap()
                    if elems_sl != -1 && sublist_length(elems_sl) > 0 {
                        let elem_ann = sublist_get(elems_sl, 0)
                        let elem_name = np_name.get(elem_ann).unwrap()
                        if elem_name == param_name {
                            let elt = arg_elem_types.get(fi).unwrap()
                            if elt >= 0 {
                                resolved = type_name_from_ct(elt)
                            }
                        }
                    }
                }
            } else if ptype == "Fn" {
                let ta = np_type_ann.get(p).unwrap()
                if ta != -1 {
                    let fn_elems_sl = np_elements.get(ta).unwrap()
                    if fn_elems_sl != -1 {
                        let mut fpi = 0
                        while fpi < sublist_length(fn_elems_sl) {
                            let fp_ann = sublist_get(fn_elems_sl, fpi)
                            let fp_name = np_name.get(fp_ann).unwrap()
                            if fp_name == param_name {
                                let csig = arg_closure_sigs.get(fi).unwrap()
                                let inner_ct = infer_closure_param_type(csig, fpi)
                                if inner_ct != CT_VOID {
                                    resolved = type_name_from_ct(inner_ct)
                                }
                            }
                            fpi = fpi + 1
                        }
                    }
                    let fn_ret = np_return_type.get(ta).unwrap()
                    if fn_ret == param_name {
                        let csig = arg_closure_sigs.get(fi).unwrap()
                        let ret_ct = infer_closure_ret_type(csig)
                        if ret_ct != CT_VOID {
                            resolved = type_name_from_ct(ret_ct)
                        }
                    }
                }
            }
            fi = fi + 1
        }
        if pi > 0 {
            args = args.concat(",")
        }
        args = args.concat(resolved)
        pi = pi + 1
    }
    Some(args)
}

fn infer_closure_param_type(sig: Str, param_idx: Int) -> Int {
    if sig == "" { return CT_VOID }
    let star_pos = sig.index_of("*)")
    if star_pos < 0 { return CT_VOID }
    let params_start = star_pos + 2
    let close_pos = sig.len() - 1
    if params_start >= close_pos { return CT_VOID }
    let params_str = sig.substring(params_start + 1, close_pos - params_start - 1)
    let parts = params_str.split(", ")
    let actual_idx = param_idx + 1
    if actual_idx >= parts.len() { return CT_VOID }
    let ctype = parts.get(actual_idx).unwrap()
    ct_from_c_type(ctype)
}

fn infer_closure_ret_type(sig: Str) -> Int {
    if sig == "" { return CT_VOID }
    let paren_pos = sig.index_of("(")
    if paren_pos <= 0 { return CT_VOID }
    let ret_str = sig.substring(0, paren_pos)
    ct_from_c_type(ret_str)
}

fn ct_from_c_type(ctype: Str) -> Int {
    if ctype == "int64_t" { CT_INT }
    else if ctype == "double" { CT_FLOAT }
    else if ctype == "const char*" { CT_STRING }
    else if ctype == "int" { CT_BOOL }
    else if ctype == "pact_list*" { CT_LIST }
    else if ctype == "pact_map*" { CT_MAP }
    else if ctype == "pact_set*" { CT_SET }
    else { CT_VOID }
}

pub fn type_name_from_ct(ct: Int) -> Str {
    if ct == CT_INT { "Int" }
    else if ct == CT_FLOAT { "Float" }
    else if ct == CT_BOOL { "Bool" }
    else if ct == CT_STRING { "Str" }
    else if ct == CT_LIST { "List" }
    else if ct == CT_ITERATOR { "Iterator" }
    else if ct == CT_HANDLE { "Handle" }
    else if ct == CT_CHANNEL { "Channel" }
    else if ct == CT_MAP { "Map" }
    else if ct == CT_SET { "Set" }
    else if ct == CT_BYTES { "Bytes" }
    else if ct == CT_STRINGBUILDER { "StringBuilder" }
    else if ct == CT_PTR { "Ptr" }
    else if ct == CT_CLOSURE { "Fn" }
    else { "Void" }
}

pub fn mangle_generic_name(base: Str, args: Str) -> Str {
    let mut result = base
    let mut i = 0
    let mut _seg_start = 0
    while i <= args.len() {
        if i == args.len() || args.char_at(i) == 44 {
            let seg = args.substr(_seg_start, i - _seg_start)
            result = result.concat("_").concat(seg)
            _seg_start = i + 1
        }
        i = i + 1
    }
    result
}

pub fn register_mono_instance(base: Str, args: Str) -> Str ! Codegen.Register {
    let existing = lookup_mono_instance(base, args)
    if existing != "" {
        return existing
    }
    let c_name = mangle_generic_name(base, args)
    mono_instances.push(MonoInstance { base: base, args: args, c_name: c_name })
    c_name
}

pub type MonoLookup {
    base: Str
    args: Str
}

pub fn lookup_mono_base(c_name: Str) -> MonoLookup {
    let mut i = 0
    while i < mono_instances.len() {
        let m = mono_instances.get(i).unwrap()
        if m.c_name == c_name {
            return MonoLookup { base: m.base, args: m.args }
        }
        i = i + 1
    }
    MonoLookup { base: "", args: "" }
}

pub fn resolve_tp(param_name: Str, tparams_sl: Int, concrete_args: Str) -> Str {
    let mut pi = 0
    let mut _arg_idx = 0
    while pi < sublist_length(tparams_sl) {
        if np_name.get(sublist_get(tparams_sl, pi)).unwrap() == param_name {
            let mut start = 0
            let mut ci = 0
            let mut idx = 0
            while ci <= concrete_args.len() {
                if ci == concrete_args.len() || concrete_args.char_at(ci) == 44 {
                    if idx == _arg_idx {
                        return concrete_args.substring(start, ci - start)
                    }
                    idx = idx + 1
                    start = ci + 1
                }
                ci = ci + 1
            }
            return param_name
        }
        _arg_idx = _arg_idx + 1
        pi = pi + 1
    }
    param_name
}

pub fn find_type_def_node(name: Str) -> Int {
    let types_sl = np_fields.get(cg_program_node).unwrap()
    if types_sl == -1 {
        return -1
    }
    let mut i = 0
    while i < sublist_length(types_sl) {
        let td = sublist_get(types_sl, i)
        if np_name.get(td).unwrap() == name {
            return td
        }
        i = i + 1
    }
    -1
}

pub fn lookup_mono_instance(base: Str, args: Str) -> Str {
    let mut i = 0
    while i < mono_instances.len() {
        let m = mono_instances.get(i).unwrap()
        if m.base == base && m.args == args {
            return m.c_name
        }
        i = i + 1
    }
    ""
}

pub fn is_trait_type(name: Str) -> Int {
    let mut i = 0
    while i < trait_entries.len() {
        if trait_entries.get(i).unwrap().name == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn lookup_impl_method(type_name: Str, method: Str) -> Int {
    let mut i = 0
    while i < impl_entries.len() {
        let ie = impl_entries.get(i).unwrap()
        if ie.type_name == type_name {
            let mut j = 0
            while j < sublist_length(ie.methods_sl) {
                let m = sublist_get(ie.methods_sl, j)
                if np_name.get(m).unwrap() == method {
                    return 1
                }
                j = j + 1
            }
        }
        i = i + 1
    }
    0
}

fn lookup_impl_type_for_trait(trait_name: Str, type_name: Str) -> Int {
    let mut i = 0
    while i < impl_entries.len() {
        let ie = impl_entries.get(i).unwrap()
        if ie.trait_name == trait_name && ie.type_name == type_name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn lookup_builtin_trait_impl(trait_name: Str, ct_type: Int) -> Int {
    let mut i = 0
    while i < builtin_trait_impls.len() {
        let bt = builtin_trait_impls.get(i).unwrap()
        if bt.trait_name == trait_name && bt.ct_type == ct_type {
            return 1
        }
        i = i + 1
    }
    0
}

fn find_impl_method_node(type_name: Str, method: Str) -> Int {
    let mut i = 0
    while i < impl_entries.len() {
        let ie = impl_entries.get(i).unwrap()
        if ie.type_name == type_name {
            let mut j = 0
            while j < sublist_length(ie.methods_sl) {
                let m = sublist_get(ie.methods_sl, j)
                if np_name.get(m).unwrap() == method {
                    return m
                }
                j = j + 1
            }
        }
        i = i + 1
    }
    -1
}

pub fn get_impl_method_ret(type_name: Str, method: Str) -> Int {
    let m = find_impl_method_node(type_name, method)
    if m == -1 { return CT_VOID }
    let ret_str = np_return_type.get(m).unwrap()
    let ret_ct = type_from_name(ret_str)
    let ta = np_type_ann.get(m).unwrap()
    if ta != -1 {
        if ret_str == "Result" {
            let elems_sl = np_elements.get(ta).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
                let ok_ann = sublist_get(elems_sl, 0)
                let err_ann = sublist_get(elems_sl, 1)
                let ok_name = np_name.get(ok_ann).unwrap()
                let err_name = np_name.get(err_ann).unwrap()
                expr_result_ok_type = type_from_name(ok_name)
                expr_result_err_type = type_from_name(err_name)
                if is_struct_type(ok_name) != 0 || is_enum_type(ok_name) != 0 {
                    expr_result_ok_struct = ok_name
                }
                if is_struct_type(err_name) != 0 || is_enum_type(err_name) != 0 {
                    expr_result_err_struct = err_name
                }
            }
        } else if ret_str == "Option" {
            let elems_sl = np_elements.get(ta).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
                let inner_ann = sublist_get(elems_sl, 0)
                let inner_name = np_name.get(inner_ann).unwrap()
                let inner_t = type_from_name(inner_name)
                expr_option_inner = inner_t
                if is_struct_type(inner_name) != 0 || is_enum_type(inner_name) != 0 {
                    expr_option_inner_struct = inner_name
                } else if is_compound_ct(inner_t) != 0 {
                    expr_option_inner_struct = compound_name_from_ann(inner_ann)
                }
            }
        }
    }
    ret_ct
}

pub fn find_from_impl(source: Str, target: Str) -> Int {
    let mut i = 0
    while i < from_entries.len() {
        let fe = from_entries.get(i).unwrap()
        if fe.source == source && fe.target == target {
            return fe.method_sl
        }
        i = i + 1
    }
    -1
}

pub fn find_tryfrom_impl(source: Str, target: Str) -> Int {
    let mut i = 0
    while i < tryfrom_entries.len() {
        let te = tryfrom_entries.get(i).unwrap()
        if te.source == source && te.target == target {
            return te.method_sl
        }
        i = i + 1
    }
    -1
}

pub fn impl_method_has_self(fn_node: Int) -> Int {
    let params_sl = np_params.get(fn_node).unwrap()
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            if np_name.get(p).unwrap() == "self" {
                return 1
            }
            i = i + 1
        }
    }
    0
}

pub fn resolve_self_type(ret_str: Str, impl_type: Str) -> Str {
    if ret_str == "Self" {
        return impl_type
    }
    ret_str
}

pub fn is_emitted_let(name: Str) -> Int {
    emitted_let_set.has(name)
}

pub fn is_emitted_fn(name: Str) -> Int {
    emitted_fn_set.has(name)
}

// ── Helpers ─────────────────────────────────────────────────────────

pub fn c_type_str(ct: Int) -> Str {
    if ct == CT_INT { "int64_t" }
    else if ct == CT_FLOAT { "double" }
    else if ct == CT_BOOL { "int" }
    else if ct == CT_STRING { "const char*" }
    else if ct == CT_LIST { "pact_list*" }
    else if ct == CT_CLOSURE { "pact_closure*" }
    else if ct == CT_ITERATOR { "void*" }
    else if ct == CT_HANDLE { "pact_handle*" }
    else if ct == CT_CHANNEL { "pact_channel*" }
    else if ct == CT_MAP { "pact_map*" }
    else if ct == CT_SET { "pact_set*" }
    else if ct == CT_BYTES { "pact_bytes*" }
    else if ct == CT_INSTANT { "pact_Instant" }
    else if ct == CT_DURATION { "pact_Duration" }
    else if ct == CT_PTR { "void*" }
    else if ct == CT_FFI_SCOPE { "pact_list*" }
    else if ct == CT_STRINGBUILDER { "pact_sb*" }
    else { "void" }
}

pub fn ptr_inner_c_type(name: Str) -> Str {
    match name {
        "Void" => "void"
        "U8" => "uint8_t"
        "U16" => "uint16_t"
        "U32" => "uint32_t"
        "U64" => "uint64_t"
        "I8" => "int8_t"
        "I16" => "int16_t"
        "I32" => "int32_t"
        "I64" => "int64_t"
        "Int" => "int64_t"
        "Float" => "double"
        _ => "void"
    }
}

pub fn resolve_ptr_inner_c() -> Str {
    if cg_let_target_ann != -1 {
        let ta_elems = np_elements.get(cg_let_target_ann).unwrap()
        if ta_elems != -1 && sublist_length(ta_elems) > 0 {
            return ptr_inner_c_type(np_name.get(sublist_get(ta_elems, 0)).unwrap())
        }
    }
    "void"
}

pub fn type_from_name(name: Str) -> Int {
    let bracket_pos = name.index_of("[")
    let mut base = name
    if bracket_pos >= 0 {
        base = name.substr(0, bracket_pos)
    }
    match base {
        "Int" => CT_INT
        "Str" => CT_STRING
        "Float" => CT_FLOAT
        "Bool" => CT_BOOL
        "List" => CT_LIST
        "Option" => CT_OPTION
        "Result" => CT_RESULT
        "Iterator" => CT_ITERATOR
        "Map" => CT_MAP
        "Bytes" => CT_BYTES
        "Instant" => CT_INSTANT
        "Duration" => CT_DURATION
        "Ptr" => CT_PTR
        "StringBuilder" => CT_STRINGBUILDER
        "Fn" => CT_CLOSURE
        "Channel" => CT_CHANNEL
        "Handle" => CT_HANDLE
        _ => CT_VOID
    }
}

pub fn option_c_type(inner: Int) -> Str {
    "pact_Option_{c_type_tag(inner)}"
}

pub fn struct_option_c_type(struct_name: Str) -> Str {
    "pact_Option_{struct_name}"
}

pub fn result_c_type(ok_t: Int, err_t: Int) -> Str {
    "pact_Result_{c_type_tag(ok_t)}_{c_type_tag(err_t)}"
}

pub fn struct_result_c_type(ok_name: Str, err_name: Str) -> Str {
    "pact_Result_{ok_name}_{err_name}"
}

pub fn result_c_type_mixed(ok_t: Int, err_t: Int, ok_struct: Str, err_struct: Str) -> Str {
    let ok_tag = if ok_struct != "" { ok_struct } else { c_type_tag(ok_t) }
    let err_tag = if err_struct != "" { err_struct } else { c_type_tag(err_t) }
    "pact_Result_{ok_tag}_{err_tag}"
}

pub fn option_c_type_mixed(inner: Int, inner_struct: Str) -> Str {
    if inner_struct != "" {
        "pact_Option_{inner_struct}"
    } else {
        "pact_Option_{c_type_tag(inner)}"
    }
}

pub fn tuple_c_type_name(elem_tags: Str, arity: Int) -> Str {
    "Tuple{arity}_{elem_tags}"
}

pub fn ensure_tuple_type(c_name: Str, arity: Int, elem_types: Str, elem_structs: Str) {
    if emitted_tuple_set.has(c_name) != 0 {
        return
    }
    emitted_tuple_set.set(c_name, 1)
    emitted_tuple_entries.push(TupleEntry { c_name: c_name, arity: arity, elem_types: elem_types, elem_structs: elem_structs })
    struct_reg_names.push(c_name)
    struct_reg_set.set(c_name, 1)
    let mut i = 0
    while i < arity {
        let et = get_tuple_entry_elem_type(elem_types, i)
        let es = get_tuple_entry_elem_struct(elem_structs, i)
        let fname = "_{i}"
        if es != "" {
            sf_entries.push(StructFieldEntry { struct_name: c_name, field_name: fname, field_type: CT_VOID, stype: es, tp_id: sv_tp(CT_VOID, -1, -1, es) })
        } else {
            sf_entries.push(StructFieldEntry { struct_name: c_name, field_name: fname, field_type: et, stype: "", tp_id: sv_tp(et, -1, -1, "") })
        }
        i = i + 1
    }
}

fn emit_tuple_typedef(entry: TupleEntry) ! Codegen.Emit {
    emit_line("typedef struct \{")
    cg_indent = cg_indent + 1
    let mut i = 0
    while i < entry.arity {
        let et = get_tuple_entry_elem_type(entry.elem_types, i)
        let es = get_tuple_entry_elem_struct(entry.elem_structs, i)
        let fname = "_{i}"
        if es != "" {
            emit_line("{c_type_c_name(es)} {fname};")
        } else {
            emit_line("{c_type_str(et)} {fname};")
        }
        i = i + 1
    }
    cg_indent = cg_indent - 1
    emit_line("} {c_type_c_name(entry.c_name)};")
    emit_line("")
}

pub fn emit_all_tuple_types() ! Codegen.Emit {
    let mut i = 0
    while i < emitted_tuple_entries.len() {
        emit_tuple_typedef(emitted_tuple_entries.get(i).unwrap())
        i = i + 1
    }
}

pub fn emit_tuple_types_from(start: Int) ! Codegen.Emit {
    let mut i = start
    while i < emitted_tuple_entries.len() {
        emit_tuple_typedef(emitted_tuple_entries.get(i).unwrap())
        i = i + 1
    }
}

fn get_tuple_entry_elem_type(encoded: Str, idx: Int) -> Int {
    let mut sep_count = 0
    let mut start = 0
    let mut i = 0
    while i < encoded.len() {
        if encoded.char_at(i) == 44 {
            if sep_count == idx {
                let part = encoded.substring(start, i - start)
                return part.to_int()
            }
            sep_count = sep_count + 1
            start = i + 1
        }
        i = i + 1
    }
    if sep_count == idx {
        let part = encoded.substring(start, encoded.len() - start)
        return part.to_int()
    }
    CT_VOID
}

fn get_tuple_entry_elem_struct(encoded: Str, idx: Int) -> Str {
    let mut sep_count = 0
    let mut start = 0
    let mut i = 0
    while i < encoded.len() {
        if encoded.char_at(i) == 44 {
            if sep_count == idx {
                let part = encoded.substring(start, i - start)
                if part == "-" { return "" }
                return part
            }
            sep_count = sep_count + 1
            start = i + 1
        }
        i = i + 1
    }
    if sep_count == idx {
        let part = encoded.substring(start, encoded.len() - start)
        if part == "-" { return "" }
        return part
    }
    ""
}

pub fn c_type_tag(ct: Int) -> Str {
    if ct == CT_INT { "int" }
    else if ct == CT_FLOAT { "double" }
    else if ct == CT_BOOL { "bool" }
    else if ct == CT_STRING { "str" }
    else if ct == CT_LIST { "list" }
    else if ct == CT_ITERATOR { "iter" }
    else if ct == CT_HANDLE { "handle" }
    else if ct == CT_CHANNEL { "channel" }
    else if ct == CT_MAP { "map" }
    else if ct == CT_BYTES { "bytes" }
    else if ct == CT_STRINGBUILDER { "stringbuilder" }
    else if ct == CT_PTR { "ptr" }
    else if ct == CT_OPTION { "option" }
    else if ct == CT_RESULT { "result" }
    else { "void" }
}

pub fn is_compound_ct(ct: Int) -> Int {
    if ct == CT_OPTION || ct == CT_RESULT || ct == CT_MAP {
        1
    } else {
        0
    }
}

pub fn compound_name_from_ann(ann_node: Int) -> Str {
    let name = np_name.get(ann_node).unwrap()
    let ct = type_from_name(name)
    if ct == CT_RESULT {
        let inner_elems = np_elements.get(ann_node).unwrap()
        if inner_elems != -1 && sublist_length(inner_elems) >= 2 {
            let ok_ann = sublist_get(inner_elems, 0)
            let err_ann = sublist_get(inner_elems, 1)
            let ok_name = np_name.get(ok_ann).unwrap()
            let err_name = np_name.get(err_ann).unwrap()
            let ok_tag = if is_struct_type(ok_name) != 0 || is_enum_type(ok_name) != 0 { ok_name } else { c_type_tag(type_from_name(ok_name)) }
            let err_tag = if is_struct_type(err_name) != 0 || is_enum_type(err_name) != 0 { err_name } else { c_type_tag(type_from_name(err_name)) }
            return "Result_{ok_tag}_{err_tag}"
        }
        "Result_int_str"
    } else if ct == CT_OPTION {
        let inner_elems = np_elements.get(ann_node).unwrap()
        if inner_elems != -1 && sublist_length(inner_elems) >= 1 {
            let inner_ann2 = sublist_get(inner_elems, 0)
            let inner_name2 = np_name.get(inner_ann2).unwrap()
            let inner_tag = if is_struct_type(inner_name2) != 0 || is_enum_type(inner_name2) != 0 { inner_name2 } else { c_type_tag(type_from_name(inner_name2)) }
            return "Option_{inner_tag}"
        }
        "Option_int"
    } else if ct == CT_MAP {
        let inner_elems = np_elements.get(ann_node).unwrap()
        if inner_elems != -1 && sublist_length(inner_elems) >= 2 {
            let key_ann = sublist_get(inner_elems, 0)
            let val_ann = sublist_get(inner_elems, 1)
            let key_tag = c_type_tag(type_from_name(np_name.get(key_ann).unwrap()))
            let val_tag = c_type_tag(type_from_name(np_name.get(val_ann).unwrap()))
            return "Map_{key_tag}_{val_tag}"
        }
        "map"
    } else {
        c_type_tag(ct)
    }
}

pub fn compound_option_inner_name(inner_type: Int, inner_str: Str) -> Str {
    if inner_type == CT_RESULT {
        let ok_t = get_var_result_ok(inner_str)
        let err_t = get_var_result_err(inner_str)
        let ok_s = get_var_result_ok_struct(inner_str)
        let err_s = get_var_result_err_struct(inner_str)
        let ok_tag = if ok_s != "" { ok_s } else { c_type_tag(ok_t) }
        let err_tag = if err_s != "" { err_s } else { c_type_tag(err_t) }
        "Result_{ok_tag}_{err_tag}"
    } else if inner_type == CT_OPTION {
        let opt_inner = get_var_option_inner(inner_str)
        let opt_inner_s = get_var_option_inner_struct(inner_str)
        let inner_tag = if opt_inner_s != "" { opt_inner_s } else { c_type_tag(opt_inner) }
        "Option_{inner_tag}"
    } else if inner_type == CT_MAP {
        "map"
    } else {
        c_type_tag(inner_type)
    }
}

fn ct_from_str(s: Str) -> Int {
    if s == "0" { CT_INT }
    else if s == "1" { CT_FLOAT }
    else if s == "2" { CT_BOOL }
    else if s == "3" { CT_STRING }
    else if s == "4" { CT_LIST }
    else if s == "5" { CT_VOID }
    else if s == "7" { CT_OPTION }
    else if s == "8" { CT_RESULT }
    else if s == "9" { CT_ITERATOR }
    else if s == "10" { CT_HANDLE }
    else if s == "11" { CT_CHANNEL }
    else if s == "13" { CT_MAP }
    else if s == "14" { CT_BYTES }
    else if s == "17" { CT_PTR }
    else if s == "19" { CT_STRINGBUILDER }
    else { CT_INT }
}

pub fn ensure_option_type(inner: Int) {
    let key = "{inner}"
    if emitted_option_set.has(key) != 0 {
        return
    }
    emitted_option_set.set(key, 1)
    emitted_option_types.push(inner)
}

pub fn ensure_struct_option_type(struct_name: Str) {
    let key = "s_{struct_name}"
    if emitted_option_set.has(key) != 0 {
        return
    }
    emitted_option_set.set(key, 1)
    emitted_struct_option_types.push(struct_name)
}

pub fn ensure_result_type(ok_t: Int, err_t: Int) {
    let key = "{ok_t}_{err_t}"
    if emitted_result_set.has(key) != 0 {
        return
    }
    emitted_result_set.set(key, 1)
    emitted_result_types.push(key)
}

pub fn ensure_struct_result_type(ok_name: Str, err_name: Str) {
    let key = "s_{ok_name}_{err_name}"
    if emitted_result_set.has(key) != 0 {
        return
    }
    emitted_result_set.set(key, 1)
    emitted_struct_result_types.push(key)
}

pub fn ensure_mixed_result_type(ok_t: Int, err_t: Int, ok_struct: Str, err_struct: Str) {
    if ok_struct != "" || err_struct != "" {
        let ok_tag = if ok_struct != "" { ok_struct } else { c_type_tag(ok_t) }
        let err_tag = if err_struct != "" { err_struct } else { c_type_tag(err_t) }
        ensure_struct_result_type(ok_tag, err_tag)
    } else {
        ensure_result_type(ok_t, err_t)
    }
}

fn ensure_mixed_option_type(inner: Int, inner_struct: Str) {
    if inner_struct != "" {
        ensure_struct_option_type(inner_struct)
    } else {
        ensure_option_type(inner)
    }
}

pub fn set_var_option(name: Str, inner: Int) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_OPTION {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: inner, inner2: sv.inner2, sname: sv.sname, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, inner, sv.inner2, sv.sname) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_OPTION, is_mut: 0, inner1: inner, inner2: -1, sname: "", sname2: "", extra: "", tp_id: sv_tp(CT_OPTION, inner, -1, "") })
}

pub fn set_var_option_inner2(name: Str, val: Int) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_OPTION {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: val, sname: sv.sname, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, sv.inner1, val, sv.sname) })
            return
        }
        i = i - 1
    }
}

pub fn get_var_option_inner2(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_OPTION {
            return sv.inner2
        }
        i = i - 1
    }
    -1
}

pub fn set_var_option_inner2_struct(name: Str, struct_name: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_OPTION {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: sv.inner2, sname: sv.sname, sname2: sv.sname2, extra: struct_name, tp_id: sv.tp_id })
            return
        }
        i = i - 1
    }
}

pub fn get_var_option_inner2_struct(name: Str) -> Str {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_OPTION && sv.extra != "" {
            return sv.extra
        }
        i = i - 1
    }
    ""
}

pub fn set_var_option_struct(name: Str, inner: Int, struct_name: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_OPTION {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: inner, inner2: sv.inner2, sname: struct_name, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, inner, sv.inner2, struct_name) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_OPTION, is_mut: 0, inner1: inner, inner2: -1, sname: struct_name, sname2: "", extra: "", tp_id: sv_tp(CT_OPTION, inner, -1, struct_name) })
}

pub fn get_var_option_inner(name: Str) -> Int {
    get_sv_inner1(name, CT_OPTION)
}

pub fn get_var_option_inner_struct(name: Str) -> Str {
    get_sv_sname(name, CT_OPTION)
}

pub fn set_var_result(name: Str, ok_t: Int, err_t: Int) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_RESULT {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: ok_t, inner2: err_t, sname: sv.sname, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, ok_t, err_t, sv.sname) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_RESULT, is_mut: 0, inner1: ok_t, inner2: err_t, sname: "", sname2: "", extra: "", tp_id: sv_tp(CT_RESULT, ok_t, err_t, "") })
}

pub fn set_var_result_struct(name: Str, ok_t: Int, err_t: Int, ok_s: Str, err_s: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_RESULT {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: ok_t, inner2: err_t, sname: ok_s, sname2: err_s, extra: sv.extra, tp_id: sv_tp(sv.ctype, ok_t, err_t, ok_s) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_RESULT, is_mut: 0, inner1: ok_t, inner2: err_t, sname: ok_s, sname2: err_s, extra: "", tp_id: sv_tp(CT_RESULT, ok_t, err_t, ok_s) })
}

pub fn get_var_result_ok(name: Str) -> Int {
    get_sv_inner1(name, CT_RESULT)
}

pub fn get_var_result_err(name: Str) -> Int {
    get_sv_inner2(name, CT_RESULT)
}

pub fn get_var_result_ok_struct(name: Str) -> Str {
    get_sv_sname(name, CT_RESULT)
}

pub fn get_var_result_err_struct(name: Str) -> Str {
    get_sv_sname2(name, CT_RESULT)
}

pub fn set_var_iterator(name: Str, inner: Int, next_fn: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_ITERATOR {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: inner, inner2: sv.inner2, sname: sv.sname, sname2: sv.sname2, extra: next_fn, tp_id: sv_tp(sv.ctype, inner, sv.inner2, sv.sname) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_ITERATOR, is_mut: 0, inner1: inner, inner2: -1, sname: "", sname2: "", extra: next_fn, tp_id: sv_tp(CT_ITERATOR, inner, -1, "") })
}

pub fn get_var_iterator_inner(name: Str) -> Int {
    get_sv_inner1(name, CT_ITERATOR)
}

pub fn get_var_iter_next_fn(name: Str) -> Str {
    get_sv_extra(name, CT_ITERATOR)
}

pub fn set_var_alias(name: Str, target: Str) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: sv.inner1, inner2: sv.inner2, sname: sv.sname, sname2: target, extra: sv.extra, tp_id: sv.tp_id })
            return
        }
        i = i - 1
    }
}

pub fn get_var_alias(name: Str) -> Str {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_ITERATOR {
            return sv.sname2
        }
        i = i - 1
    }
    ""
}

pub fn set_var_handle(name: Str, inner: Int) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_HANDLE {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: inner, inner2: sv.inner2, sname: sv.sname, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, inner, sv.inner2, sv.sname) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_HANDLE, is_mut: 0, inner1: inner, inner2: -1, sname: "", sname2: "", extra: "", tp_id: sv_tp(CT_HANDLE, inner, -1, "") })
}

pub fn get_var_handle_inner(name: Str) -> Int {
    get_sv_inner1(name, CT_HANDLE)
}

pub fn set_var_handle_full(name: Str, inner: Int, inner2: Int, extra1: Str, extra2: Str) {
    let encoded_extra = "{extra1}:{extra2}"
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_HANDLE {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: inner, inner2: inner2, sname: "", sname2: "", extra: encoded_extra, tp_id: sv_tp(CT_HANDLE, inner, -1, "") })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_HANDLE, is_mut: 0, inner1: inner, inner2: inner2, sname: "", sname2: "", extra: encoded_extra, tp_id: sv_tp(CT_HANDLE, inner, -1, "") })
}

pub fn get_var_handle_inner2(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_HANDLE {
            return sv.inner2
        }
        i = i - 1
    }
    -1
}

pub fn get_var_handle_sname(name: Str) -> Str {
    let extra = get_sv_extra(name, CT_HANDLE)
    if extra == "" { return "" }
    let idx = extra.index_of(":")
    if idx < 0 { return extra }
    extra.slice(0, idx)
}

pub fn get_var_handle_sname2(name: Str) -> Str {
    let extra = get_sv_extra(name, CT_HANDLE)
    if extra == "" { return "" }
    let idx = extra.index_of(":")
    if idx < 0 { return "" }
    extra.slice(idx + 1, extra.len())
}

pub fn set_var_channel(name: Str, inner: Int) {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i).unwrap()
        if sv.name == name && tp_get_kind(sv.tp_id) == CT_CHANNEL {
            scope_vars.set(i, ScopeVar { name: sv.name, ctype: sv.ctype, is_mut: sv.is_mut, inner1: inner, inner2: sv.inner2, sname: sv.sname, sname2: sv.sname2, extra: sv.extra, tp_id: sv_tp(sv.ctype, inner, sv.inner2, sv.sname) })
            return
        }
        i = i - 1
    }
    scope_vars.push(ScopeVar { name: name, ctype: CT_CHANNEL, is_mut: 0, inner1: inner, inner2: -1, sname: "", sname2: "", extra: "", tp_id: sv_tp(CT_CHANNEL, inner, -1, "") })
}

pub fn get_var_channel_inner(name: Str) -> Int {
    get_sv_inner1(name, CT_CHANNEL)
}

fn emit_option_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let tname = "pact_Option_{tag}"
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ int tag; {c_inner} value; } {tname};")
    emit_line("")
}

fn emit_result_typedef(ok_t: Int, err_t: Int) ! Codegen.Emit {
    let ok_tag = c_type_tag(ok_t)
    let err_tag = c_type_tag(err_t)
    let tname = "pact_Result_{ok_tag}_{err_tag}"
    let c_ok = c_type_str(ok_t)
    let c_err = c_type_str(err_t)
    emit_line("typedef struct \{ int tag; union \{ {c_ok} ok; {c_err} err; }; } {tname};")
    emit_line("")
}

fn emit_struct_option_typedef(struct_name: Str) ! Codegen.Emit {
    let tname = "pact_Option_{struct_name}"
    emit_line("typedef struct \{ int tag; {c_type_c_name(struct_name)} value; } {tname};")
    emit_line("")
}

fn emit_struct_result_typedef(ok_tag: Str, err_tag: Str) ! Codegen.Emit {
    let tname = "pact_Result_{ok_tag}_{err_tag}"
    let c_ok = if is_struct_type(ok_tag) != 0 || is_enum_type(ok_tag) != 0 { c_type_c_name(ok_tag) } else { c_type_str(type_from_name_tag(ok_tag)) }
    let c_err = if is_struct_type(err_tag) != 0 || is_enum_type(err_tag) != 0 { c_type_c_name(err_tag) } else { c_type_str(type_from_name_tag(err_tag)) }
    emit_line("typedef struct \{ int tag; union \{ {c_ok} ok; {c_err} err; }; } {tname};")
    emit_line("")
}

fn type_from_name_tag(tag: Str) -> Int {
    if tag == "int" { CT_INT }
    else if tag == "str" { CT_STRING }
    else if tag == "double" { CT_FLOAT }
    else if tag == "bool" { CT_BOOL }
    else if tag == "list" { CT_LIST }
    else if tag == "iter" { CT_ITERATOR }
    else if tag == "handle" { CT_HANDLE }
    else if tag == "channel" { CT_CHANNEL }
    else if tag == "map" { CT_MAP }
    else if tag == "bytes" { CT_BYTES }
    else if tag == "stringbuilder" { CT_STRINGBUILDER }
    else if tag == "ptr" { CT_PTR }
    else { CT_VOID }
}

pub fn ensure_iter_type(inner: Int) {
    let key = "{inner}"
    if emitted_iter_set.has(key) != 0 {
        return
    }
    emitted_iter_set.set(key, 1)
    emitted_iter_types.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_range_iter() {
    if emitted_range_iter != 0 {
        return
    }
    emitted_range_iter = 1
    ensure_option_type(CT_INT)
}

pub fn ensure_str_iter() {
    if emitted_str_iter != 0 {
        return
    }
    emitted_str_iter = 1
    ensure_option_type(CT_STRING)
}

pub fn emit_range_iter_typedef() ! Codegen.Emit {
    emit_line("typedef struct \{ int64_t current; int64_t end; int is_inclusive; } pact_RangeIterator;")
    emit_line("")
    emit_line("static pact_Option_int pact_RangeIterator_next(pact_RangeIterator* self) \{")
    emit_line("    int in_range = self->is_inclusive ? (self->current <= self->end) : (self->current < self->end);")
    emit_line("    if (in_range) \{")
    emit_line("        int64_t val = self->current;")
    emit_line("        self->current++;")
    emit_line("        return (pact_Option_int)\{ .tag = 1, .value = val };")
    emit_line("    }")
    emit_line("    return (pact_Option_int)\{ .tag = 0 };")
    emit_line("}")
    emit_line("")
}

pub fn emit_str_iter_typedef() ! Codegen.Emit {
    emit_line("typedef struct \{ const char* str; int64_t index; int64_t len; } pact_StrIterator;")
    emit_line("")
    emit_line("static pact_Option_str pact_StrIterator_next(pact_StrIterator* self) \{")
    emit_line("    if (self->index < self->len) \{")
    emit_line("        const char* val = pact_str_from_char_code((int64_t)(unsigned char)self->str[self->index]);")
    emit_line("        self->index++;")
    emit_line("        return (pact_Option_str)\{ .tag = 1, .value = val };")
    emit_line("    }")
    emit_line("    return (pact_Option_str)\{ .tag = 0 };")
    emit_line("}")
    emit_line("")
}

pub fn list_iter_c_type(inner: Int) -> Str {
    "pact_ListIterator_{c_type_tag(inner)}"
}

fn emit_list_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let tname = "pact_ListIterator_{tag}"
    let opt_name = option_c_type(inner)
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ pact_list* items; int64_t index; } {tname};")
    emit_line("")
    emit_line("static {opt_name} {tname}_next({tname}* self) \{")
    emit_line("    if (self->index < pact_list_len(self->items)) \{")
    if inner == CT_INT {
        emit_line("        int64_t val = (int64_t)(intptr_t)pact_list_get(self->items, self->index);")
    } else if inner == CT_STRING {
        emit_line("        const char* val = (const char*)pact_list_get(self->items, self->index);")
    } else if inner == CT_FLOAT {
        emit_line("        double val = *(double*)pact_list_get(self->items, self->index);")
    } else {
        emit_line("        {c_inner} val = ({c_inner})(intptr_t)pact_list_get(self->items, self->index);")
    }
    emit_line("        self->index++;")
    emit_line("        return ({opt_name})\{ .tag = 1, .value = val };")
    emit_line("    }")
    emit_line("    return ({opt_name})\{ .tag = 0 };")
    emit_line("}")
    emit_line("")
    emit_line("static {tname} pact_list_into_iter_{tag}(pact_list* self) \{")
    emit_line("    return ({tname})\{ .items = self, .index = 0 };")
    emit_line("}")
    emit_line("")
}

pub fn emit_all_iter_types() ! Codegen.Emit {
    if emitted_range_iter != 0 {
        emit_range_iter_typedef()
    }
    if emitted_str_iter != 0 {
        emit_str_iter_typedef()
    }
    let mut i = 0
    while i < emitted_iter_types.len() {
        emit_list_iter_typedef(emitted_iter_types.get(i).unwrap())
        i = i + 1
    }
    i = 0
    while i < emitted_map_iters.len() {
        emit_map_iter_typedef(emitted_map_iters.get(i).unwrap())
        i = i + 1
    }
    i = 0
    while i < emitted_filter_iters.len() {
        emit_filter_iter_typedef(emitted_filter_iters.get(i).unwrap())
        i = i + 1
    }
    i = 0
    while i < emitted_take_iters.len() {
        emit_take_iter_typedef(emitted_take_iters.get(i).unwrap())
        i = i + 1
    }
    i = 0
    while i < emitted_skip_iters.len() {
        emit_skip_iter_typedef(emitted_skip_iters.get(i).unwrap())
        i = i + 1
    }
    i = 0
    while i < emitted_chain_iters.len() {
        emit_chain_iter_typedef(emitted_chain_iters.get(i).unwrap())
        i = i + 1
    }
    i = 0
    while i < emitted_flat_map_iters.len() {
        emit_flat_map_iter_typedef(emitted_flat_map_iters.get(i).unwrap())
        i = i + 1
    }
}

pub fn emit_iter_types_from(list_start: Int, map_start: Int, filter_start: Int, take_start: Int, skip_start: Int, chain_start: Int, flat_map_start: Int) ! Codegen.Emit {
    let mut i = list_start
    while i < emitted_iter_types.len() {
        emit_list_iter_typedef(emitted_iter_types.get(i).unwrap())
        i = i + 1
    }
    i = map_start
    while i < emitted_map_iters.len() {
        emit_map_iter_typedef(emitted_map_iters.get(i).unwrap())
        i = i + 1
    }
    i = filter_start
    while i < emitted_filter_iters.len() {
        emit_filter_iter_typedef(emitted_filter_iters.get(i).unwrap())
        i = i + 1
    }
    i = take_start
    while i < emitted_take_iters.len() {
        emit_take_iter_typedef(emitted_take_iters.get(i).unwrap())
        i = i + 1
    }
    i = skip_start
    while i < emitted_skip_iters.len() {
        emit_skip_iter_typedef(emitted_skip_iters.get(i).unwrap())
        i = i + 1
    }
    i = chain_start
    while i < emitted_chain_iters.len() {
        emit_chain_iter_typedef(emitted_chain_iters.get(i).unwrap())
        i = i + 1
    }
    i = flat_map_start
    while i < emitted_flat_map_iters.len() {
        emit_flat_map_iter_typedef(emitted_flat_map_iters.get(i).unwrap())
        i = i + 1
    }
}

fn has_int_in_list(lst: List[Int], val: Int) -> Bool {
    let mut i = 0
    while i < lst.len() {
        if lst.get(i).unwrap() == val {
            return true
        }
        i = i + 1
    }
    false
}

pub fn ensure_map_iter(inner: Int) {
    if has_int_in_list(emitted_map_iters, inner) { return }
    emitted_map_iters.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_filter_iter(inner: Int) {
    if has_int_in_list(emitted_filter_iters, inner) { return }
    emitted_filter_iters.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_take_iter(inner: Int) {
    if has_int_in_list(emitted_take_iters, inner) { return }
    emitted_take_iters.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_skip_iter(inner: Int) {
    if has_int_in_list(emitted_skip_iters, inner) { return }
    emitted_skip_iters.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_chain_iter(inner: Int) {
    if has_int_in_list(emitted_chain_iters, inner) { return }
    emitted_chain_iters.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_flat_map_iter(inner: Int) {
    if has_int_in_list(emitted_flat_map_iters, inner) { return }
    emitted_flat_map_iters.push(inner)
    ensure_option_type(inner)
}

fn emit_map_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ void* source; {opt} (*source_next)(void*); pact_closure* fn; } pact_MapIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_MapIterator_{tag}_next(void* __self) \{")
    emit_line("    pact_MapIterator_{tag}* self = (pact_MapIterator_{tag}*)__self;")
    emit_line("    {opt} __src = self->source_next(self->source);")
    emit_line("    if (__src.tag == 0) return ({opt})\{ .tag = 0 };")
    emit_line("    {c_inner} __val = (({c_inner} (*)(const pact_closure*, {c_inner}))self->fn->fn_ptr)(self->fn, __src.value);")
    emit_line("    return ({opt})\{ .tag = 1, .value = __val };")
    emit_line("}")
    emit_line("")
}

fn emit_filter_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ void* source; {opt} (*source_next)(void*); pact_closure* fn; } pact_FilterIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_FilterIterator_{tag}_next(void* __self) \{")
    emit_line("    pact_FilterIterator_{tag}* self = (pact_FilterIterator_{tag}*)__self;")
    emit_line("    while (1) \{")
    emit_line("        {opt} __src = self->source_next(self->source);")
    emit_line("        if (__src.tag == 0) return ({opt})\{ .tag = 0 };")
    emit_line("        if (((int (*)(const pact_closure*, {c_inner}))self->fn->fn_ptr)(self->fn, __src.value)) \{")
    emit_line("            return __src;")
    emit_line("        }")
    emit_line("    }")
    emit_line("}")
    emit_line("")
}

fn emit_take_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    emit_line("typedef struct \{ void* source; {opt} (*source_next)(void*); int64_t limit; int64_t count; } pact_TakeIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_TakeIterator_{tag}_next(void* __self) \{")
    emit_line("    pact_TakeIterator_{tag}* self = (pact_TakeIterator_{tag}*)__self;")
    emit_line("    if (self->count >= self->limit) return ({opt})\{ .tag = 0 };")
    emit_line("    {opt} __src = self->source_next(self->source);")
    emit_line("    if (__src.tag == 0) return __src;")
    emit_line("    self->count++;")
    emit_line("    return __src;")
    emit_line("}")
    emit_line("")
}

fn emit_skip_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    emit_line("typedef struct \{ void* source; {opt} (*source_next)(void*); int64_t skip_n; int64_t skipped; } pact_SkipIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_SkipIterator_{tag}_next(void* __self) \{")
    emit_line("    pact_SkipIterator_{tag}* self = (pact_SkipIterator_{tag}*)__self;")
    emit_line("    while (self->skipped < self->skip_n) \{")
    emit_line("        {opt} __src = self->source_next(self->source);")
    emit_line("        if (__src.tag == 0) return __src;")
    emit_line("        self->skipped++;")
    emit_line("    }")
    emit_line("    return self->source_next(self->source);")
    emit_line("}")
    emit_line("")
}

fn emit_chain_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    emit_line("typedef struct \{ void* source_a; {opt} (*next_a)(void*); void* source_b; {opt} (*next_b)(void*); int phase; } pact_ChainIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_ChainIterator_{tag}_next(void* __self) \{")
    emit_line("    pact_ChainIterator_{tag}* self = (pact_ChainIterator_{tag}*)__self;")
    emit_line("    if (self->phase == 0) \{")
    emit_line("        {opt} __src = self->next_a(self->source_a);")
    emit_line("        if (__src.tag != 0) return __src;")
    emit_line("        self->phase = 1;")
    emit_line("    }")
    emit_line("    return self->next_b(self->source_b);")
    emit_line("}")
    emit_line("")
}

fn emit_flat_map_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ void* source; {opt} (*source_next)(void*); pact_closure* fn; pact_list* buffer; int64_t buf_idx; } pact_FlatMapIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_FlatMapIterator_{tag}_next(void* __self) \{")
    emit_line("    pact_FlatMapIterator_{tag}* self = (pact_FlatMapIterator_{tag}*)__self;")
    emit_line("    while (1) \{")
    emit_line("        if (self->buffer && self->buf_idx < pact_list_len(self->buffer)) \{")
    if inner == CT_INT {
        emit_line("            {c_inner} val = (int64_t)(intptr_t)pact_list_get(self->buffer, self->buf_idx);")
    } else if inner == CT_STRING {
        emit_line("            {c_inner} val = (const char*)pact_list_get(self->buffer, self->buf_idx);")
    } else if inner == CT_FLOAT {
        emit_line("            double val = *(double*)pact_list_get(self->buffer, self->buf_idx);")
    } else {
        emit_line("            {c_inner} val = ({c_inner})(intptr_t)pact_list_get(self->buffer, self->buf_idx);")
    }
    emit_line("            self->buf_idx++;")
    emit_line("            return ({opt})\{ .tag = 1, .value = val };")
    emit_line("        }")
    emit_line("        {opt} __src = self->source_next(self->source);")
    emit_line("        if (__src.tag == 0) return ({opt})\{ .tag = 0 };")
    emit_line("        self->buffer = ((pact_list* (*)(const pact_closure*, {c_inner}))self->fn->fn_ptr)(self->fn, __src.value);")
    emit_line("        self->buf_idx = 0;")
    emit_line("    }")
    emit_line("}")
    emit_line("")
}

pub fn emit_all_option_result_types() ! Codegen.Emit {
    let mut i = 0
    while i < emitted_option_types.len() {
        emit_option_typedef(emitted_option_types.get(i).unwrap())
        i = i + 1
    }
    i = 0
    while i < emitted_result_types.len() {
        let key = emitted_result_types.get(i).unwrap()
        let mut sep = 0
        let mut j = 0
        while j < key.len() {
            if key.char_at(j) == 95 {
                sep = j
            }
            j = j + 1
        }
        let ok_str = key.substring(0, sep)
        let err_str = key.substring(sep + 1, key.len() - sep - 1)
        let ok_t = ct_from_str(ok_str)
        let err_t = ct_from_str(err_str)
        emit_result_typedef(ok_t, err_t)
        i = i + 1
    }
    i = 0
    while i < emitted_struct_option_types.len() {
        emit_struct_option_typedef(emitted_struct_option_types.get(i).unwrap())
        i = i + 1
    }
    i = 0
    while i < emitted_struct_result_types.len() {
        let key = emitted_struct_result_types.get(i).unwrap()
        let prefix_len = 2
        let stripped = key.substring(prefix_len, key.len() - prefix_len)
        let mut sep = 0
        let mut j = 0
        while j < stripped.len() {
            if stripped.char_at(j) == 95 {
                sep = j
            }
            j = j + 1
        }
        let ok_tag = stripped.substring(0, sep)
        let err_tag = stripped.substring(sep + 1, stripped.len() - sep - 1)
        emit_struct_result_typedef(ok_tag, err_tag)
        i = i + 1
    }
}

pub fn emit_option_result_types_from(opt_start: Int, res_start: Int, s_opt_start: Int, s_res_start: Int) ! Codegen.Emit {
    let mut i = opt_start
    while i < emitted_option_types.len() {
        emit_option_typedef(emitted_option_types.get(i).unwrap())
        i = i + 1
    }
    i = res_start
    while i < emitted_result_types.len() {
        let key = emitted_result_types.get(i).unwrap()
        let mut sep = 0
        let mut j = 0
        while j < key.len() {
            if key.char_at(j) == 95 {
                sep = j
            }
            j = j + 1
        }
        let ok_str = key.substring(0, sep)
        let err_str = key.substring(sep + 1, key.len() - sep - 1)
        let ok_t = ct_from_str(ok_str)
        let err_t = ct_from_str(err_str)
        emit_result_typedef(ok_t, err_t)
        i = i + 1
    }
    i = s_opt_start
    while i < emitted_struct_option_types.len() {
        emit_struct_option_typedef(emitted_struct_option_types.get(i).unwrap())
        i = i + 1
    }
    i = s_res_start
    while i < emitted_struct_result_types.len() {
        let key = emitted_struct_result_types.get(i).unwrap()
        let prefix_len = 2
        let stripped = key.substring(prefix_len, key.len() - prefix_len)
        let mut sep = 0
        let mut j = 0
        while j < stripped.len() {
            if stripped.char_at(j) == 95 {
                sep = j
            }
            j = j + 1
        }
        let ok_tag = stripped.substring(0, sep)
        let err_tag = stripped.substring(sep + 1, stripped.len() - sep - 1)
        emit_struct_result_typedef(ok_tag, err_tag)
        i = i + 1
    }
}

pub fn fresh_temp(prefix: Str) -> Str {
    let n = cg_temp_counter
    cg_temp_counter = cg_temp_counter + 1
    "{prefix}{n}"
}

pub fn emit_line(line: Str) ! Codegen.Emit {
    if line == "" {
        cg_lines.push("")
    } else {
        let mut pad = ""
        let mut i = 0
        while i < cg_indent {
            pad = pad.concat("    ")
            i = i + 1
        }
        cg_lines.push(pad.concat(line))
    }
}

pub fn join_lines() -> Str ! Codegen.Emit {
    cg_lines.join("\n")
}

pub fn c_type_for_alias(base_name: Str) -> Str {
    if base_name == "Int" { return "int64_t" }
    if base_name == "Float" { return "double" }
    if base_name == "Bool" { return "int64_t" }
    if base_name == "Str" { return "const char*" }
    return "pact_{base_name}"
}
