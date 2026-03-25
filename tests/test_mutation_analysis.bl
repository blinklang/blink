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

// ── W0551 context-awareness test ────────────────────────────────────
//
// W0551 (UnrestoredMutation) only fires when the *containing function*
// already has a save/restore pattern (sr_fn_has_save_restore != 0).
//
// speculative_bump_none() above has NO save/restore → W0551 should NOT fire.
//
// The function below DOES have a save/restore pattern (saves counter)
// but calls bump_everything() which also mutates items and name without
// saving them. Because saved_count==0 for that second call AND
// sr_fn_has_save_restore==1, W0551 WOULD fire for a bare unprotected call.
// However, here the first call (increment) is fully protected and the
// second call (bump_everything) has partial saves, so W0550 fires instead.
// We add a dedicated function that triggers W0551 specifically.

// This function has a save/restore for counter (via increment), which sets
// sr_fn_has_save_restore=1. Then it calls set_name() with NO save at all
// for the name global. Since saved_count==0 for set_name and
// sr_fn_has_save_restore!=0, this triggers W0551.
// W0551 is a warning, not an error, so compilation still succeeds.
fn speculative_mixed_pattern() {
    let saved_counter = counter
    increment()
    counter = saved_counter
    set_name("speculative")
}

// ── @allow suppression tests ────────────────────────────────────────
//
// @allow(IncompleteStateRestore) suppresses W0550
// @allow(UnrestoredMutation) suppresses W0551
//
// NOTE: [lints] config in pact.toml is project-level and cannot be tested
// in a standalone test file. It should be verified separately/manually.

// Would trigger W0550 (incomplete save/restore: saves counter+name but not items)
// @allow suppresses the warning
@allow(IncompleteStateRestore)
fn speculative_bump_incomplete_allowed() {
    let saved_counter = counter
    let saved_name = name
    bump_everything()
    counter = saved_counter
    name = saved_name
}

// Would trigger W0551 (has save/restore pattern but set_name call has none)
// @allow suppresses the warning
@allow(UnrestoredMutation)
fn speculative_mixed_allowed() {
    let saved_counter = counter
    increment()
    counter = saved_counter
    set_name("allowed")
}

// Both warnings suppressed in one annotation
@allow(IncompleteStateRestore, UnrestoredMutation)
fn speculative_both_allowed() {
    let saved_counter = counter
    bump_everything()
    counter = saved_counter
    set_name("both")
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

test "W0551 context: mixed save/restore pattern" {
    reset_all()
    counter = 5
    speculative_mixed_pattern()
    assert_eq(get_counter(), 5)
    assert_eq(get_name(), "speculative")
}

test "W0551 context: no save/restore means no warning" {
    reset_all()
    counter = 5
    name = "before"
    speculative_bump_none()
    assert_eq(get_counter(), 15)
    assert_eq(get_name(), "bumped")
    assert_eq(get_item_count(), 1)
}

test "@allow(IncompleteStateRestore) suppresses W0550" {
    reset_all()
    counter = 5
    name = "before"
    speculative_bump_incomplete_allowed()
    assert_eq(get_counter(), 5)
    assert_eq(get_name(), "before")
    assert_eq(get_item_count(), 1)
    assert_eq(items.get(0).unwrap(), 99)
}

test "@allow(UnrestoredMutation) suppresses W0551" {
    reset_all()
    counter = 5
    speculative_mixed_allowed()
    assert_eq(get_counter(), 5)
    assert_eq(get_name(), "allowed")
}

test "@allow with multiple warning names" {
    reset_all()
    counter = 5
    speculative_both_allowed()
    assert_eq(get_counter(), 5)
    assert_eq(get_name(), "both")
    assert_eq(get_item_count(), 1)
}
