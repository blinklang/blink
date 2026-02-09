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

fn main() {
    let io_err = IOError { message: "file not found" }
    let cfg_err = ConfigError.from(io_err)
    io.println(cfg_err.message)
    io.println(cfg_err.code)
    io.println("PASSED")
}
