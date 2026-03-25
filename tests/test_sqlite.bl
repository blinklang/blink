fn main() ! IO, DB {
    let handle = db.open(":memory:")

    db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)")

    db.exec("INSERT INTO users (name, age) VALUES ('Alice', 30)")
    db.exec("INSERT INTO users (name, age) VALUES ('Bob', 25)")

    let rid = db.execute("INSERT INTO users (name, age) VALUES ('Charlie', 35)")
    io.println("last rowid: {rid}")

    let rows = db.query("SELECT name, age FROM users ORDER BY name")
    let mut i = 0
    while i < rows.len() {
        let row = rows.get(i).unwrap()
        let name = row.get(0).unwrap()
        let age = row.get(1).unwrap()
        io.println("{name} is {age}")
        i = i + 1
    }

    let one = db.query_one("SELECT name FROM users WHERE name = 'Bob'")
    if one.is_some() {
        let row = one.unwrap()
        io.println("found: {row.get(0).unwrap()}")
    }

    let none = db.query_one("SELECT name FROM users WHERE name = 'Nobody'")
    if none.is_none() {
        io.println("not found: correct")
    }

    let stmt = db.prepare("SELECT name FROM users WHERE age > ?")
    db.bind_int(stmt, 1, 28)
    let mut rc = db.step(stmt)
    while rc == 100 {
        let name = db.column_text(stmt, 0)
        io.println("older than 28: {name}")
        rc = db.step(stmt)
    }
    db.finalize(stmt)

    db.begin(handle)
    db.exec("INSERT INTO users (name, age) VALUES ('Dave', 40)")
    db.commit(handle)

    db.begin(handle)
    db.exec("INSERT INTO users (name, age) VALUES ('Eve', 50)")
    db.rollback(handle)

    let final_rows = db.query("SELECT name FROM users ORDER BY name")
    io.println("total users: {final_rows.len()}")

    let msg = db.errmsg(handle)
    io.println("errmsg: {msg}")

    db.close(handle)
}
