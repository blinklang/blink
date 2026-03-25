trait From[T] {
    fn from(value: T) -> Self
}

type IOError {
    message: Str
}

type ConfigError {
    message: Str
    code: Int
}

impl From[IOError] for ConfigError {
    fn from(value: IOError) -> Self {
        ConfigError { message: value.message, code: 500 }
    }
}

test "From trait converts IOError to ConfigError" {
    let io_err = IOError { message: "file not found" }
    let cfg_err = ConfigError.from(io_err)
    assert_eq(cfg_err.message, "file not found")
    assert_eq(cfg_err.code, 500)
}
