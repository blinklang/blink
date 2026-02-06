// todo.pact — Structs, enums, traits, error handling
//
// Demonstrates: type (struct/enum), trait, impl, Result, ?,
//               List[T], pattern matching, ! IO, ! FS

type Status {
    Open
    Done
}

type Todo {
    title: Str
    status: Status
}

type TodoError {
    NotFound(id: Int)
    IO(msg: Str)
}

impl From[IOError] for TodoError {
    fn from(e: IOError) -> TodoError {
        TodoError.IO(e.message())
    }
}

trait Display {
    fn display(self) -> Str
}

impl Display for Status {
    fn display(self) -> Str {
        match self {
            Open => "[ ]"
            Done => "[x]"
        }
    }
}

impl Display for Todo {
    fn display(self) -> Str {
        "{self.status.display()} {self.title}"
    }
}

/// Add a new todo to the list.
fn add(todos: List[Todo], title: Str) -> List[Todo] {
    let todo = Todo { title: title, status: Status.Open }
    todos.append(todo)
}

/// Mark a todo as done by index.
@requires(index >= 0)
fn complete(todos: List[Todo], index: Int) -> Result[List[Todo], TodoError] {
    match todos.get(index) {
        Some(todo) => {
            let updated = Todo { title: todo.title, status: Status.Done }
            Ok(todos.set(index, updated))
        }
        None => Err(TodoError.NotFound(index))
    }
}

/// Print all todos.
fn print_todos(todos: List[Todo]) ! IO {
    for todo in todos {
        io.println(todo.display())
    }
}

/// Save todos to a file.
fn save(todos: List[Todo], path: Str) ! FS.Write {
    let lines = todos.map(fn(t) { t.display() })
    fs.write(path, lines.join("\n"))
}

fn main() {
    let mut todos = []
    todos = add(todos, "Write Pact spec")
    todos = add(todos, "Build compiler")
    todos = add(todos, "Ship v1")

    todos = complete(todos, 0).unwrap()

    print_todos(todos)
    save(todos, "todos.txt")
}

test "add creates open todo" {
    let todos = add([], "Test task")
    assert_eq(todos.len(), 1)
    assert_eq(todos.get(0).unwrap().title, "Test task")
    assert_eq(todos.get(0).unwrap().status, Status.Open)
}

test "complete marks done" {
    let todos = add([], "Task")
    let result = complete(todos, 0)
    assert(result.is_ok())
    assert_eq(result.unwrap().get(0).unwrap().status, Status.Done)
}

test "complete out of bounds" {
    let result = complete([], 5)
    assert(result.is_err())
}
