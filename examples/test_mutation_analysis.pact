// test_mutation_analysis.pact — Exercise compile-time mutation analysis patterns
//
// Mutation analysis is a compile-time pass that infers which functions write
// to module-level mutable globals (directly or transitively). If the pass has
// bugs, this file won't compile. The tests verify runtime behavior is correct.

// ── Module-level mutable globals ─────────────────────────────────────
let mut counter: Int = 0
let mut items: List[Int] = []
let mut name: Str = ""

// ── Direct writers ───────────────────────────────────────────────────

fn increment() {
    counter = counter + 1
}

fn set_name(s: Str) {
    name = s
}

// ── Mutating method call on global ───────────────────────────────────

fn add_item(x: Int) {
    items.push(x)
}

// ── Read-only (no writes) ────────────────────────────────────────────

fn get_counter() -> Int {
    counter
}

fn get_item_count() -> Int {
    items.len()
}

fn get_name() -> Str {
    name
}

// ── Transitive writers (call a fn that writes) ───────────────────────

fn double_increment() {
    increment()
    increment()
}

fn setup_defaults() {
    set_name("default")
    add_item(0)
}

// ── Writes multiple globals in one function ──────────────────────────

fn reset_all() {
    counter = 0
    items = []
    name = ""
}

fn bump_everything() {
    counter = counter + 10
    items.push(99)
    name = "bumped"
}

// ── Save/restore patterns (W0550/W0551 diagnostics) ─────────────

// Complete save/restore — should NOT trigger W0550
fn speculative_bump_safe() {
    let saved_counter = counter
    let saved_items = items
    let saved_name = name
    bump_everything()
    counter = saved_counter
    items = saved_items
    name = saved_name
}

// Incomplete save/restore — saves counter+name but NOT items
// Should trigger W0550 for bump_everything() call
fn speculative_bump_incomplete() {
    let saved_counter = counter
    let saved_name = name
    bump_everything()
    counter = saved_counter
    name = saved_name
}

// No save/restore pattern in this function at all
// Should NOT trigger W0551 (only fires when function has existing save/restore)
fn speculative_bump_none() {
    bump_everything()
}

// ── Tests ────────────────────────────────────────────────────────────

test "direct assignment to global" {
    reset_all()
    assert_eq(get_counter(), 0)
    increment()
    assert_eq(get_counter(), 1)
    increment()
    assert_eq(get_counter(), 2)
}

test "mutating method call on global list" {
    reset_all()
    add_item(10)
    add_item(20)
    assert_eq(get_item_count(), 2)
    assert_eq(items.get(0).unwrap(), 10)
    assert_eq(items.get(1).unwrap(), 20)
}

test "string global assignment" {
    reset_all()
    assert_eq(get_name(), "")
    set_name("pact")
    assert_eq(get_name(), "pact")
}

test "transitive writes through call chain" {
    reset_all()
    double_increment()
    assert_eq(get_counter(), 2)
}

test "transitive writes to multiple globals" {
    reset_all()
    setup_defaults()
    assert_eq(get_name(), "default")
    assert_eq(get_item_count(), 1)
}

test "single function writes multiple globals" {
    reset_all()
    bump_everything()
    assert_eq(get_counter(), 10)
    assert_eq(get_name(), "bumped")
    assert_eq(get_item_count(), 1)
    assert_eq(items.get(0).unwrap(), 99)
}

test "read-only functions reflect mutations" {
    reset_all()
    assert_eq(get_counter(), 0)
    assert_eq(get_item_count(), 0)
    assert_eq(get_name(), "")
    increment()
    add_item(5)
    set_name("test")
    assert_eq(get_counter(), 1)
    assert_eq(get_item_count(), 1)
    assert_eq(get_name(), "test")
}

test "reset clears all globals" {
    increment()
    add_item(1)
    set_name("dirty")
    reset_all()
    assert_eq(get_counter(), 0)
    assert_eq(get_item_count(), 0)
    assert_eq(get_name(), "")
}

test "complete save/restore preserves state" {
    reset_all()
    counter = 5
    name = "before"
    items.push(42)
    speculative_bump_safe()
    assert_eq(get_counter(), 5)
    assert_eq(get_name(), "before")
    // list save/restore is by reference, so bump_everything's push(99) mutates the shared list
    assert_eq(get_item_count(), 2)
    assert_eq(items.get(0).unwrap(), 42)
    assert_eq(items.get(1).unwrap(), 99)
}

test "incomplete save/restore preserves only saved globals" {
    reset_all()
    counter = 5
    name = "before"
    speculative_bump_incomplete()
    assert_eq(get_counter(), 5)
    assert_eq(get_name(), "before")
    assert_eq(get_item_count(), 1)
    assert_eq(items.get(0).unwrap(), 99)
}
