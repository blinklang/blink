// embed.pact — Compile-time file inclusion
//
// Demonstrates: #embed intrinsic, const bindings, compile-time
//               string values from external files

/// Print the project's help text, embedded at compile time.
fn print_help() ! IO {
    const HELP_TEXT: Str = #embed("templates/help.txt")
    io.println(HELP_TEXT)
}

/// Serve an HTML template embedded from a file.
fn serve_template(name: Str) -> Str {
    const HOME_PAGE: Str = #embed("templates/home.html")
    const ABOUT_PAGE: Str = #embed("templates/about.html")

    match name {
        "home" => HOME_PAGE
        "about" => ABOUT_PAGE
        _ => "Not found"
    }
}

/// SQL schema embedded at compile time — no escaping needed.
fn init_db() ! DB {
    const SCHEMA: Str = #embed("sql/schema.sql")
    db.exec(SCHEMA)
}

fn main() {
    let page = env.args().unsafe_get(1) ?? "home"
    io.println(serve_template(page))
}
