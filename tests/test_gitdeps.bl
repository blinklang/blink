import std.path
import pkg.gitdeps

fn setup_test_repo() {
    shell_exec("rm -rf /tmp/_pact_test_git")
    shell_exec("mkdir -p /tmp/_pact_test_git/mylib/src")
    write_file("/tmp/_pact_test_git/mylib/src/lib.pact", "pub fn greet() -> Str \{ \"hello\" \}\n")
    write_file("/tmp/_pact_test_git/mylib/pact.toml", "[package]\nname = \"mylib\"\nversion = \"1.0.0\"\n")
    shell_exec("cd /tmp/_pact_test_git/mylib && git init && git add -A && git commit -m 'init' && git tag v1.0")
}

fn cleanup() {
    shell_exec("rm -rf /tmp/_pact_test_git")
    shell_exec("rm -rf ~/.blink/cache/git/*_pact_test_*")
}

test "fetch file url" {
    setup_test_repo()
    git_clear()
    let url = "file:///tmp/_pact_test_git/mylib"
    let rc = git_fetch(url, "v1.0")
    assert_eq(rc, 0)
    let commit = git_get_commit()
    assert_eq(commit.len(), 40)
}

test "checkout path exists" {
    let path = git_get_checkout_path()
    assert(is_dir(path))
    let lib_path = path_join(path, "src/lib.pact")
    assert(file_exists(lib_path))
}

test "content hash" {
    let hash = git_get_content_hash()
    assert(hash.len() > 0)
}

test "cache reuse" {
    let url = "file:///tmp/_pact_test_git/mylib"
    let first_commit = git_get_commit()
    let first_hash = git_get_content_hash()

    git_clear()
    let rc = git_fetch(url, "v1.0")
    assert_eq(rc, 0)
    assert_eq(git_get_commit(), first_commit)
    assert_eq(git_get_content_hash(), first_hash)
}

test "sanitize url" {
    let sanitized = sanitize_url("https://github.com/org/repo.git")
    // Should have no slashes, colons, or dots
    let mut i = 0
    let mut has_bad = 0
    while i < sanitized.len() {
        let ch = sanitized.char_at(i)
        if ch == 47 || ch == 58 || ch == 46 {
            has_bad = 1
        }
        i = i + 1
    }
    assert(has_bad == 0)
    // Should contain recognizable parts
    assert(sanitized.len() > 0)
}

test "clear state" {
    git_clear()
    assert_eq(git_get_commit(), "")
    assert_eq(git_get_checkout_path(), "")
    assert_eq(git_get_content_hash(), "")
    cleanup()
}
