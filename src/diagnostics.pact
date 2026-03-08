import parser

effect Diag {
    effect Report
}

// diagnostics.pact — Structured diagnostic collector and emitter
//
// Collects errors/warnings into parallel arrays, then flushes as
// JSON (one object per line) or human-readable format.

// ── Diagnostic storage (parallel arrays) ─────────────────────────────

pub let mut diag_severity: List[Str] = []
pub let mut diag_name: List[Str] = []
pub let mut diag_code: List[Str] = []
pub let mut diag_message: List[Str] = []
pub let mut diag_file: List[Str] = []
pub let mut diag_line: List[Int] = []
pub let mut diag_col: List[Int] = []
pub let mut diag_help: List[Str] = []
pub let mut diag_end_line: List[Int] = []
pub let mut diag_end_col: List[Int] = []
pub let mut diag_fix_action: List[Str] = []
pub let mut diag_fix_text: List[Str] = []

// ── Configuration ────────────────────────────────────────────────────

pub let mut diag_format: Int = 0       // 0=human, 1=json
pub let mut diag_source_file: Str = ""
pub let mut diag_count: Int = 0        // error count only
pub let mut diag_warn_count: Int = 0   // warning count only
pub let mut diag_module_files: Map[Str, Str] = Map()

// ── Lint severity overrides from [lints] in pact.toml ───────────────
pub let mut lint_overrides: Map[Str, Str] = Map()

// ── Lint override helpers ────────────────────────────────────────────

pub fn lint_set_override(name: Str, level: Str) {
    lint_overrides.set(name, level)
}

fn lint_apply_override(severity: Str, name: Str) -> Str {
    if lint_overrides.has(name) == 0 {
        return severity
    }
    let level = lint_overrides.get(name)
    if level == "off" {
        return "off"
    }
    if level == "error" && severity == "warning" {
        return "error"
    }
    if level == "warn" && severity == "error" {
        return "warning"
    }
    severity
}

// ── Emit helpers ─────────────────────────────────────────────────────

pub fn diag_emit(severity: Str, name: Str, code: Str, message: Str, line: Int, col: Int, help: Str) ! Diag.Report {
    let effective_severity = lint_apply_override(severity, name)
    if effective_severity == "off" {
        return
    }
    diag_severity.push(effective_severity)
    diag_name.push(name)
    diag_code.push(code)
    diag_message.push(message)
    diag_file.push(diag_source_file)
    diag_line.push(line)
    diag_col.push(col)
    diag_help.push(help)
    diag_end_line.push(0)
    diag_end_col.push(0)
    diag_fix_action.push("")
    diag_fix_text.push("")
    if effective_severity == "error" {
        diag_count = diag_count + 1
    }
    if effective_severity == "warning" {
        diag_warn_count = diag_warn_count + 1
    }
}

pub fn diag_set_last_fix(action: Str, text: Str) {
    let idx = diag_fix_action.len() - 1
    if idx >= 0 {
        diag_fix_action.set(idx, action)
        diag_fix_text.set(idx, text)
    }
}

pub fn diag_error(name: Str, code: Str, message: Str, line: Int, col: Int, help: Str) ! Diag.Report {
    diag_emit("error", name, code, message, line, col, help)
}

pub fn diag_error_no_loc(name: Str, code: Str, message: Str, help: Str) ! Diag.Report {
    diag_emit("error", name, code, message, 0, 0, help)
}

pub fn diag_file_for_node(node_id: Int) -> Str {
    let mod_name = np_module.get(node_id).unwrap()
    if mod_name != "" {
        let f = diag_module_files.get(mod_name)
        if f != "" {
            return f
        }
    }
    diag_source_file
}

pub fn diag_error_at(name: Str, code: Str, message: Str, node_id: Int, help: Str) ! Diag.Report {
    let line = np_line.get(node_id).unwrap()
    let col = np_col.get(node_id).unwrap()
    let saved_file = diag_source_file
    diag_source_file = diag_file_for_node(node_id)
    diag_emit("error", name, code, message, line, col, help)
    diag_source_file = saved_file
}

pub fn diag_warn(name: Str, code: Str, message: Str, line: Int, col: Int, help: Str) ! Diag.Report {
    diag_emit("warning", name, code, message, line, col, help)
}

pub fn diag_warn_no_loc(name: Str, code: Str, message: Str, help: Str) ! Diag.Report {
    diag_emit("warning", name, code, message, 0, 0, help)
}

pub fn diag_warn_at(name: Str, code: Str, message: Str, node_id: Int, help: Str) ! Diag.Report {
    let line = np_line.get(node_id).unwrap()
    let col = np_col.get(node_id).unwrap()
    let saved_file = diag_source_file
    diag_source_file = diag_file_for_node(node_id)
    diag_emit("warning", name, code, message, line, col, help)
    diag_source_file = saved_file
}

pub fn diag_emit_range(severity: Str, name: Str, code: Str, message: Str, line: Int, col: Int, end_line: Int, end_col: Int, help: Str) ! Diag.Report {
    let effective_severity = lint_apply_override(severity, name)
    if effective_severity == "off" {
        return
    }
    diag_severity.push(effective_severity)
    diag_name.push(name)
    diag_code.push(code)
    diag_message.push(message)
    diag_file.push(diag_source_file)
    diag_line.push(line)
    diag_col.push(col)
    diag_help.push(help)
    diag_end_line.push(end_line)
    diag_end_col.push(end_col)
    diag_fix_action.push("")
    diag_fix_text.push("")
    if effective_severity == "error" {
        diag_count = diag_count + 1
    }
    if effective_severity == "warning" {
        diag_warn_count = diag_warn_count + 1
    }
}

// ── JSON string escaping ─────────────────────────────────────────────

pub fn json_escape(s: Str) -> Str {
    let mut result = ""
    let mut i = 0
    while i < s.len() {
        let ch = s.char_at(i)
        if ch == 92 {
            result = result.concat("\\\\")
        } else if ch == 34 {
            result = result.concat("\\\"")
        } else if ch == 10 {
            result = result.concat("\\n")
        } else if ch == 13 {
            result = result.concat("\\r")
        } else if ch == 9 {
            result = result.concat("\\t")
        } else {
            result = result.concat(s.substring(i, 1))
        }
        i = i + 1
    }
    result
}

// ── Flush: emit all diagnostics ──────────────────────────────────────

pub fn diag_flush() ! Diag.Report {
    let mut i = 0
    while i < diag_severity.len() {
        if diag_format == 1 {
            diag_print_json(i)
        } else {
            diag_print_human(i)
        }
        i = i + 1
    }
    if diag_format == 1 {
        // no summary in json mode
    } else {
        if diag_count > 0 {
            io.println("{diag_count} error(s) found")
        }
    }
}

pub fn diag_print_json(idx: Int) ! Diag.Report {
    let sev = json_escape(diag_severity.get(idx).unwrap())
    let name = json_escape(diag_name.get(idx).unwrap())
    let code = json_escape(diag_code.get(idx).unwrap())
    let msg = json_escape(diag_message.get(idx).unwrap())
    let file = json_escape(diag_file.get(idx).unwrap())
    let line = diag_line.get(idx).unwrap()
    let col = diag_col.get(idx).unwrap()
    let help = diag_help.get(idx).unwrap()
    let el = diag_end_line.get(idx).unwrap()
    let ec = diag_end_col.get(idx).unwrap()
    let mut span = "\"span\":\{\"file\":\"{file}\",\"line\":{line},\"col\":{col}"
    if el > 0 {
        span = span.concat(",\"end_line\":{el},\"end_col\":{ec}")
    }
    span = span.concat("}")
    let mut json = "\{\"severity\":\"{sev}\",\"name\":\"{name}\",\"code\":\"{code}\",\"message\":\"{msg}\",{span}"
    if help != "" {
        json = json.concat(",\"help\":\"").concat(json_escape(help)).concat("\"")
    }
    let fix_act = diag_fix_action.get(idx).unwrap()
    if fix_act != "" {
        let fix_txt = json_escape(diag_fix_text.get(idx).unwrap())
        json = json.concat(",\"fix\":\{\"action\":\"{fix_act}\",\"text\":\"{fix_txt}\"}")
    }
    json = json.concat("}")
    io.println(json)
}

pub fn diag_print_human(idx: Int) ! Diag.Report {
    let sev = diag_severity.get(idx).unwrap()
    let name = diag_name.get(idx).unwrap()
    let msg = diag_message.get(idx).unwrap()
    let file = diag_file.get(idx).unwrap()
    let line = diag_line.get(idx).unwrap()
    let col = diag_col.get(idx).unwrap()
    let help = diag_help.get(idx).unwrap()
    io.println("{sev}[{name}]: {msg}")
    if line > 0 {
        io.println("  --> {file}:{line}:{col}")
    }
    if help != "" {
        io.println("  help: {help}")
    }
    let fix_act = diag_fix_action.get(idx).unwrap()
    if fix_act != "" {
        let fix_txt = diag_fix_text.get(idx).unwrap()
        io.println("  fix: {fix_act} '{fix_txt}'")
    }
}

// ── Reset ────────────────────────────────────────────────────────────

pub fn diag_reset() {
    diag_severity = []
    diag_name = []
    diag_code = []
    diag_message = []
    diag_file = []
    diag_line = []
    diag_col = []
    diag_help = []
    diag_end_line = []
    diag_end_col = []
    diag_fix_action = []
    diag_fix_text = []
    diag_count = 0
    diag_warn_count = 0
    diag_module_files = Map()
    lint_overrides = Map()
}

// ── Error catalog ─────────────────────────────────────────────────

pub fn diag_explain(code: Str) -> Str {
    if code == "E0300" {
        return "E0300 -- TypeError\n\nA type mismatch was detected during type checking.\n\nCommon causes:\n  - Passing a value of the wrong type to a function\n  - Using '?' in a function that does not return Result\n  - Assigning a value to a variable of incompatible type\n\nFix: check the expected and actual types in the error message and\nadjust your code to match.\n\n  fn add(a: Int, b: Int) -> Int \{ a + b \}\n  add(1, \"two\")  // E0300: expected Int, got Str"
    }
    if code == "E0500" {
        return "E0500 -- UndeclaredEffect\n\nA function calls another function that requires an effect, but the\ncaller does not declare that effect in its signature.\n\nFix: add '! EffectName' to the calling function's signature.\n\n  fn greet() ! IO \{\n      io.println(\"hello\")  // IO effect declared\n  \}\n\n  fn bad() \{\n      io.println(\"hello\")  // E0500: requires IO but bad() has none\n  \}"
    }
    if code == "E0501" {
        return "E0501 -- InsufficientCapability\n\nA function uses an effect that is not listed in the module's\n@capabilities budget.\n\nFix: add the effect to the @capabilities annotation at the top of\nyour module.\n\n  @capabilities(IO, Net)\n  fn fetch() ! IO, Net \{ ... \}  // OK -- both in budget"
    }
    if code == "E0502" {
        return "E0502 -- InvalidOperand for ? or ??\n\nThe '?' or '??' operator was used on a value that is not the\nexpected type. '?' requires Result or Option, '??' requires Option.\n\nCommon causes:\n  - Using '?' on a plain value instead of a Result or Option\n  - Using '??' on a Result instead of an Option\n  - Using '?' on Option (not yet supported -- use '??' instead)\n\n  let val = some_option ?? \"default\"  // OK\n  let res = try_parse()?              // OK -- ? on Result"
    }
    if code == "E0504" {
        return "E0504 -- UndefinedFunction\n\nA function was called that has not been defined or imported.\n\nCommon causes:\n  - Typo in the function name\n  - Forgetting to import the module that defines the function\n  - The function is private (not pub) in another module\n\nFix: check the function name spelling, or add the appropriate import.\n\n  import math\n  let x = math.sqrt(4.0)  // OK -- imported"
    }
    if code == "E0505" {
        return "E0505 -- UnresolvedMethod\n\nA method call could not be resolved for the receiver's type.\n\nCommon causes:\n  - Calling a method that does not exist on that type\n  - The variable's type is not what you expected\n  - Missing trait implementation\n\nFix: check the receiver type and available methods.\n\n  let x: Int = 42\n  x.contains(\"a\")  // E0505: Int has no .contains() method"
    }
    if code == "E0506" {
        return "E0506 -- UndefinedVariable\n\nA variable was referenced that has not been declared in scope.\n\nCommon causes:\n  - Typo in the variable name\n  - Using a variable before it is declared\n  - Variable is out of scope (declared in a different block)\n\n  let name = \"Pact\"\n  io.println(nane)  // E0506: 'nane' -- did you mean 'name'?"
    }
    if code == "E0507" {
        return "E0507 -- UnknownType\n\nA type name was used that the compiler does not recognize.\n\nCommon causes:\n  - Typo in the type name\n  - Forgetting to define or import the type\n  - Using a type from a module that is not imported\n\n  type Point \{ x: Int, y: Int \}\n  let p: Piont = ...  // E0507: unknown type 'Piont'"
    }
    if code == "E0508" {
        return "E0508 -- QuestionMarkResultInNonResult\n\nThe '?' operator was used on a Result value inside a function that\ndoes not return Result.\n\nFix: change the function's return type to Result[T, E].\n\n  fn parse(s: Str) -> Result[Int, Str] \{ ... \}\n\n  fn caller() -> Result[Int, Str] \{\n      let n = parse(\"42\")?  // OK -- caller returns Result\n      Ok(n)\n  \}"
    }
    if code == "E0509" {
        return "E0509 -- QuestionMarkOptionInNonOption\n\nThe '?' operator was used on an Option value inside a function that\ndoes not return Option.\n\nFix: change the function's return type to Option[T].\n\n  fn find(items: List[Str], key: Str) -> Option[Str] \{\n      items.get(0)?  // OK -- function returns Option\n  \}"
    }
    if code == "E1003" {
        return "E1003 -- PrivateItemAccess\n\nAn attempt was made to access a private (non-pub) item from another\nmodule.\n\nFix: either mark the item as 'pub' in its module, or use the\nmodule's public API instead.\n\n  // in math.pact\n  pub fn sqrt(x: Float) -> Float \{ ... \}  // accessible\n  fn helper() \{ ... \}                      // private"
    }
    if code == "E1015" {
        return "E1015 -- InlineModuleNotSupported\n\nInline modules (mod name \{ ... \}) are not supported in Pact.\nPact uses file-based modules: one file = one module.\n\nFix: move the module contents into a separate file and use import.\n\n  // Instead of:\n  mod schema \{\n      fn validate() \{ ... \}\n  \}\n\n  // Create schema.pact with the contents and import it:\n  import schema\n  schema.validate()\n\nSee section 10.1 for details on Pact's module system."
    }
    if code == "E1100" {
        return "E1100 -- UnexpectedToken\n\nThe parser encountered a token it did not expect at this position.\n\nCommon causes:\n  - Missing or extra braces, parentheses, or brackets\n  - Incorrect syntax for the current context\n  - Using an operator in the wrong position\n\nFix: check the line and column indicated and look for syntax errors."
    }
    if code == "E1101" {
        return "E1101 -- UnexpectedToken in String\n\nThe parser encountered an unexpected token inside a string\ninterpolation.\n\nCommon causes:\n  - Malformed interpolation expression\n  - Unmatched braces inside a string\n\nFix: ensure interpolation expressions are valid Pact expressions."
    }
    if code == "E1102" {
        return "E1102 -- UnexpectedToken in Pattern\n\nThe parser encountered an unexpected token inside a match pattern.\n\nCommon causes:\n  - Invalid pattern syntax in a match arm\n  - Using expressions where a pattern is expected\n\nFix: use valid pattern syntax: literals, identifiers, enum variants,\nor wildcard '_'."
    }
    if code == "E1103" {
        return "E1103 -- KeywordAsIdentifier\n\nA language keyword was used where an identifier (variable or\nfunction name) was expected.\n\nKeywords: fn, let, if, else, match, while, return, type, trait,\nimport, pub, handler, effect, enum, for, in, mut, const, test\n\nFix: choose a different name that is not a reserved keyword.\n\n  let result = 42    // OK\n  let match = 42     // E1103: 'match' is a keyword"
    }
    if code == "E1107" {
        return "E1107 -- EmptyBraceExpr\n\nEmpty braces were used in expression position. Pact does not have\nempty-brace map syntax.\n\nFix: use Map() to construct an empty map.\n\n  let m: Map[Str, Int] = Map()  // OK"
    }
    if code == "E1108" {
        return "E1108 -- FileNotFound / UnknownIntrinsic\n\nEither an #embed() referenced a file that does not exist, or an\nunknown compile-time intrinsic was used.\n\nFix: check that the file path is correct relative to the source\nfile, or use a supported intrinsic (#embed is currently the only one).\n\n  const data: Str = #embed(\"data.txt\")  // file must exist"
    }
    if code == "E1200" {
        return "E1200 -- ModuleNotFound\n\nAn import statement referenced a module that could not be found.\n\nCommon causes:\n  - Typo in the module name\n  - Missing file: the module's .pact file does not exist\n  - Incorrect path in the module hierarchy\n\nFix: verify the module name matches a .pact file in your project or\nthe standard library.\n\n  import math       // looks for lib/std/math.pact or src/math.pact\n  import pkg.audit  // looks for lib/pkg/audit.pact"
    }
    if code == "W0501" {
        return "W0501 -- UnknownMethod\n\nA method was called that could not be verified during type checking.\nThe code will still compile, but may produce a C error.\n\nCommon causes:\n  - The variable's type is not fully known at check time\n  - A typo in the method name\n\nFix: verify the method name and receiver type."
    }
    if code == "W0550" {
        return "W0550 -- IncompleteStateRestore\n\nA function call mutates global state but only some of the affected\nglobals are saved and restored around the call.\n\nCommon causes:\n  - Adding a new global to a function's write-set without updating\n    the save/restore pattern in the caller\n\nFix: save and restore all affected globals around the call, or\nverify the mutation is intentional."
    }
    if code == "W0551" {
        return "W0551 -- UnrestoredMutation\n\nA function call mutates globals with no save/restore pattern, but\nthe enclosing function uses save/restore elsewhere. This suggests\nthe call may need save/restore too.\n\nCommon causes:\n  - Calling a function with broad side effects speculatively\n  - Forgetting to wrap the call in a save/restore block\n\nFix: if the call is speculative (may need to be rolled back), save\nand restore the affected globals."
    }
    if code == "W0600" {
        return "W0600 -- UnusedVariable\n\nA variable was declared but never read.\n\nCommon causes:\n  - Leftover variable from refactoring\n  - Variable assigned but result never used\n\nFix: remove the variable, or prefix its name with '_' to suppress\nthis warning.\n\n  let _unused = compute()  // OK -- prefixed with '_'"
    }
    if code == "W0601" {
        return "W0601 -- SetButNotRead\n\nA variable was assigned a value that was never read before being\noverwritten or going out of scope.\n\nCommon causes:\n  - Redundant assignment before reassignment\n  - Leftover intermediate computation\n\nFix: remove the unused assignment, or prefix with '_' to suppress.\n\n  let mut x = compute()  // W0601: value never read\n  x = other()\n  io.println(x)"
    }
    if code == "W0602" {
        return "W0602 -- UnusedImport\n\nA module was imported but no symbols from it are referenced.\n\nCommon causes:\n  - Leftover import from refactoring\n  - Import added for future use\n\nFix: remove the unused import statement.\n\n  import math    // W0602 if math.* never used\n  import strings // OK if strings.contains() is called"
    }
    if code == "W0603" {
        return "W0603 -- ShadowedVariable\n\nA variable in an inner scope shadows a variable with the same name\nin an outer scope.\n\nCommon causes:\n  - Accidentally reusing a variable name from an enclosing scope\n  - Copy-paste without renaming\n\nFix: rename the inner variable, or prefix with '_' to suppress\nthis warning.\n\n  let x = 10\n  if true \{\n      let _x = 20  // OK -- prefixed with '_'\n  \}"
    }
    if code == "W0700" {
        return "W0700 -- UnreachableCode\n\nCode appears after an unconditional return, break, or continue\nstatement and will never execute.\n\nCommon causes:\n  - Leftover code from refactoring\n  - Early return added without removing subsequent code\n\nFix: remove the unreachable code or move it before the control\nflow statement."
    }
    if code == "W0800" {
        return "W0800 -- UnauditedFFI\n\nAn @ffi function is not marked @trusted, meaning it has not been\naudited for safety.\n\nFix: audit the foreign function for memory safety and correctness,\nthen add @trusted to suppress this warning.\n\n  @ffi(\"puts\")\n  @trusted\n  fn c_puts(s: Ptr[U8]) -> Int ! FFI \{ \}"
    }
    if code == "E0801" {
        return "E0801 -- PubFFI\n\nAn @ffi function was declared as pub. FFI functions are unsafe and\nshould not be exposed in a module's public API.\n\nFix: remove 'pub' and wrap the FFI call in a safe public function.\n\n  @ffi(\"strlen\")\n  @trusted\n  fn c_strlen(s: Ptr[U8]) -> Int ! FFI \{ \}\n\n  pub fn string_length(s: Str) -> Int ! FFI \{\n      c_strlen(s.as_ptr())\n  \}"
    }
    if code == "E0802" {
        return "E0802 -- FFINoEffects\n\nAn @ffi function does not declare any effects. FFI calls are\ninherently side-effectful and must declare their effects.\n\nFix: add '! FFI' or appropriate effects to the function signature.\n\n  @ffi(\"puts\")\n  @trusted\n  fn c_puts(s: Ptr[U8]) -> Int ! FFI \{ \}"
    }
    if code == "E0803" {
        return "E0803 -- ContractOnFFI\n\nA @requires or @ensures annotation was used on an @ffi function.\nContracts cannot verify foreign code behavior.\n\nFix: remove the contract annotation from the FFI function. If you\nneed contracts, add them to a safe wrapper function instead.\n\n  @ffi(\"sqrt\")\n  @trusted\n  fn c_sqrt(x: Float) -> Float ! FFI \{ \}\n\n  @requires(x >= 0.0)\n  pub fn safe_sqrt(x: Float) -> Float ! FFI \{\n      c_sqrt(x)\n  \}"
    }
    if code == "E0810" {
        return "E0810 -- InvalidPtrType\n\nPtr[T] was used with an invalid type parameter. Only FFI-compatible\ntypes are allowed inside Ptr.\n\nValid types: Void, U8, U16, U32, U64, I8, I16, I32, I64, Int,\nFloat, Ptr\n\nFix: use one of the valid FFI-compatible types.\n\n  fn good(p: Ptr[U8]) ! FFI \{ \}   // OK\n  fn bad(p: Ptr[Str]) ! FFI \{ \}    // E0810: Str is not valid"
    }
    if code == "E0811" {
        return "E0811 -- PtrOutsideFFI\n\nPtr[T] was used in a function that is not marked @ffi. Pointer\ntypes are only valid in FFI contexts.\n\nFix: add @ffi to the function, or use a safe wrapper.\n\n  @ffi(\"malloc\")\n  @trusted\n  fn c_malloc(size: Int) -> Ptr[Void] ! FFI \{ \}"
    }
    ""
}
