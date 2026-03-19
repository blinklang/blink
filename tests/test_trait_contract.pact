import compile_test_helpers

fn main() {
    // --- Positive: correct impl compiles cleanly ---
    let src_ok = "trait Greet \{\n    fn greet(self) -> Str\n}\ntype Dog \{ name: Str }\nimpl Greet for Dog \{\n    fn greet(self) -> Str \{ self.name }\n}\nfn main() \{\n}\n"
    let out_ok = compile_test_helpers.compile_and_capture(src_ok, "_tc_ok")
    compile_test_helpers.expect_clean(out_ok, "correct impl compiles")

    // --- Positive: From[T] with type param ---
    let src_from = "trait From[T] \{\n    fn from(value: T) -> Self\n}\ntype IOError \{ message: Str }\ntype AppError \{ message: Str, code: Int }\nimpl From[IOError] for AppError \{\n    fn from(value: IOError) -> Self \{\n        AppError \{ message: value.message, code: 500 }\n    }\n}\nfn main() \{\n}\n"
    let out_from = compile_test_helpers.compile_and_capture(src_from, "_tc_from")
    compile_test_helpers.expect_clean(out_from, "From[T] impl compiles")

    // --- Negative: missing method → E0900 ---
    let src_missing = "trait Greet \{\n    fn greet(self) -> Str\n}\ntype Dog \{ name: Str }\nimpl Greet for Dog \{\n}\nfn main() \{\n}\n"
    let out_missing = compile_test_helpers.compile_and_capture(src_missing, "_tc_missing")
    compile_test_helpers.expect_error(out_missing, "E0900", "missing method detected")

    // --- Negative: wrong arity → E0901 ---
    let src_arity = "trait Math \{\n    fn add(self, x: Int, y: Int) -> Int\n}\ntype Calc \{ base: Int }\nimpl Math for Calc \{\n    fn add(self) -> Int \{ self.base }\n}\nfn main() \{\n}\n"
    let out_arity = compile_test_helpers.compile_and_capture(src_arity, "_tc_arity")
    compile_test_helpers.expect_error(out_arity, "E0901", "wrong arity detected")

    // --- Negative: wrong param type → E0902 ---
    let src_param = "trait Math \{\n    fn add(self, x: Int) -> Int\n}\ntype Calc \{ base: Int }\nimpl Math for Calc \{\n    fn add(self, x: Str) -> Int \{ 0 }\n}\nfn main() \{\n}\n"
    let out_param = compile_test_helpers.compile_and_capture(src_param, "_tc_param")
    compile_test_helpers.expect_error(out_param, "E0902", "wrong param type detected")

    // --- Negative: wrong return type → E0903 ---
    let src_ret = "trait Math \{\n    fn compute(self) -> Int\n}\ntype Calc \{ base: Int }\nimpl Math for Calc \{\n    fn compute(self) -> Str \{ \"nope\" }\n}\nfn main() \{\n}\n"
    let out_ret = compile_test_helpers.compile_and_capture(src_ret, "_tc_ret")
    compile_test_helpers.expect_error(out_ret, "E0903", "wrong return type detected")

    // --- Negative: type param substitution mismatch → E0902 ---
    let src_tp = "trait Convert[T] \{\n    fn convert(self, value: T) -> Str\n}\ntype Fmt \{ prefix: Str }\nimpl Convert[Int] for Fmt \{\n    fn convert(self, value: Str) -> Str \{ value }\n}\nfn main() \{\n}\n"
    let out_tp = compile_test_helpers.compile_and_capture(src_tp, "_tc_tparam")
    compile_test_helpers.expect_error(out_tp, "E0902", "type param substitution mismatch detected")

    // --- Negative: impl for undefined trait → E0904 ---
    let src_undef = "type Dog \{ name: Str }\nimpl NonExistent for Dog \{\n}\nfn main() \{\n}\n"
    let out_undef = compile_test_helpers.compile_and_capture(src_undef, "_tc_undef")
    compile_test_helpers.expect_error(out_undef, "E0904", "undefined trait detected")
}
