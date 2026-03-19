// xtest — Result codegen with data enums needs fixes (pact_Result_int_TodoError vs pact_Result_str_TodoError)
// todo.pact — Structs, enums, traits, error handling
//
// Demonstrates: type (struct/enum), trait, impl, Result,
//               List[T], pattern matching

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
        let s = self.status
        "{s.display()} {self.title}"
    }
}

/// Add a new todo to the list.
fn add(todos: List[Todo], title: Str) {
    let todo = Todo { title: title, status: Status.Open }
    todos.push(todo)
}

/// Mark a todo as done by index. Returns the updated title or error.
fn complete(todos: List[Todo], index: Int) -> Result[Str, TodoError] {
    let opt = todos.get(index)
    if opt.is_none() {
        return Err(TodoError.NotFound(index))
    }
    let todo = opt.unwrap()
    let updated = Todo { title: todo.title, status: Status.Done }
    todos.set(index, updated)
    Ok(todo.title)
}

/// Print all todos.
fn print_todos(todos: List[Todo]) {
    for todo in todos {
        io.println(todo.display())
    }
}

fn main() {
    let todos: List[Todo] = []
    add(todos, "Write Pact spec")
    add(todos, "Build compiler")
    add(todos, "Ship v1")

    complete(todos, 0).unwrap()

    print_todos(todos)
}

test "add creates open todo" {
    let todos: List[Todo] = []
    add(todos, "Test task")
    assert_eq(todos.len(), 1)
    assert_eq(todos.get(0).unwrap().title, "Test task")
    assert_eq(todos.get(0).unwrap().status, Status.Open)
}

test "complete marks done" {
    let todos: List[Todo] = []
    add(todos, "Task")
    let result = complete(todos, 0)
    assert(result.is_ok())
    assert_eq(todos.get(0).unwrap().status, Status.Done)
}

test "complete out of bounds" {
    let todos: List[Todo] = []
    let result = complete(todos, 5)
    assert(result.is_err())
}
