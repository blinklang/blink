// web_api.pact — HTTP handler + system boundaries
//
// Demonstrates: Request -> Response pattern, @requires as HTTP 400,
//               refinement types, struct field defaults,
//               struct construction shorthand, effect composition,
//               mock handlers for Net and DB in tests

type Port = Int @where(self > 0 && self <= 65535)

type User {
    id: Int
    name: Str
    email: Str
}

type ApiError {
    NotFound(msg: Str)
    BadRequest(msg: Str)
    Internal(msg: Str)
}

type ServerConfig {
    host: Str = "0.0.0.0"
    port: Port = 8080
    debug: Bool = false
}

impl From[DBError] for ApiError {
    fn from(e: DBError) -> ApiError {
        ApiError.Internal(e.message())
    }
}

/// Look up a user by ID. The @requires becomes a 400 at the system boundary.
/// db.query_one accepts Query[DB] — {id} auto-parameterizes.
/// The Err string is Str context — {id} concatenates normally.
@requires(id > 0)
pub fn get_user(id: Int) -> Result[User, ApiError] ! DB.Read {
    db.query_one("SELECT * FROM users WHERE id = {id}")
        ?? Err(ApiError.NotFound("User {id} not found"))
}

/// Create a new user. Inputs are validated by contracts.
/// {name} and {email} in db.execute become bound parameters (Query[DB] context).
/// {id} and {name} in io.log are concatenated (Str context).
@requires(name.len() > 0)
@requires(email.len() > 0)
pub fn create_user(name: Str, email: Str) -> Result[User, ApiError] ! DB.Write, IO.Log {
    let id = db.execute("INSERT INTO users (name, email) VALUES ({name}, {email})")
    io.log("Created user {id}: {name}")
    Ok(User { id: id, name: name, email: email })
}

/// HTTP handler: GET /users/:id
/// At this system boundary, @requires on get_user auto-generates a 400 response.
pub fn handle_get_user(req: Request) -> Response ! IO, DB.Read {
    let id = req.param("id").parse_int() ?? return Response.bad_request("Invalid user ID")
    match get_user(id) {
        Ok(user) => Response.json(user)
        Err(ApiError.NotFound(msg)) => Response.not_found(msg)
        Err(e) => Response.internal_error("{e}")
    }
}

/// HTTP handler: POST /users
pub fn handle_create_user(req: Request) -> Response ! IO, DB.Write {
    let name = req.body().unsafe_get("name")?.as_str() ?? return Response.bad_request("Missing name")
    let email = req.body().unsafe_get("email")?.as_str() ?? return Response.bad_request("Missing email")
    match create_user(name, email) {
        Ok(user) => Response.json(user).with_status(201)
        Err(e) => Response.internal_error("{e}")
    }
}

/// Start the server with the given config.
fn start_server(config: ServerConfig) ! Net.Listen, IO {
    if config.debug {
        io.println("Debug mode enabled")
    }
    io.println("Starting server on port {config.port}")
    let server = net.listen(config.host, config.port)
    server.route("GET", "/users/:id", handle_get_user)
    server.route("POST", "/users", handle_create_user)
    server.serve()
}

fn main() {
    let port = env.var("PORT").parse_int() ?? 8080
    // Struct construction shorthand — compiler infers ServerConfig
    start_server({ port: port, debug: env.var("DEBUG").is_some() })
}

// -- Tests with mock handlers --

fn mock_db_with_users(users: List[User]) -> Handler[DB] {
    handler DB {
        fn query_one(query: Query[DB]) -> Result[User?, DBError] {
            let id = extract_id_from_query(query)
            Ok(users.find(fn(u) { u.id == id }))
        }
        fn execute(query: Query[DB]) -> Result[Int, DBError] {
            Ok(users.len() + 1)
        }
    }
}

test "get_user returns user" {
    let users = [User { id: 1, name: "Alice", email: "alice@example.com" }]

    with mock_db_with_users(users) {
        let result = get_user(1)
        assert(result.is_ok())
        assert_eq(result.unwrap().name, "Alice")
    }
}

test "get_user not found" {
    with mock_db_with_users([]) {
        let result = get_user(99)
        assert(result.is_err())
    }
}

test "create_user succeeds" {
    with mock_db_with_users([]), capture_log([]) {
        let result = create_user("Bob", "bob@example.com")
        assert(result.is_ok())
        assert_eq(result.unwrap().name, "Bob")
    }
}
