// gitdeps.pact — git dependency fetcher for pact package manager
//
// Clones, caches, and checks out git dependencies.
// Cache layout: ~/.pact/cache/git/{sanitized_url}/repo.git (bare clone)
//               ~/.pact/cache/git/{sanitized_url}/{commit}/ (checkout)

import std.path
import pkg.manifest

// ── Last fetch results ──────────────────────────────────────────
pub let mut last_commit: Str = ""
pub let mut last_checkout_path: Str = ""
pub let mut last_content_hash: Str = ""

// ── Clear state ─────────────────────────────────────────────────

pub fn git_clear() {
    last_commit = ""
    last_checkout_path = ""
    last_content_hash = ""
}

// ── Helpers ─────────────────────────────────────────────────────

fn trim_str(s: Str) -> Str {
    let mut end = s.len()
    while end > 0 {
        let ch = s.char_at(end - 1)
        if ch == 10 || ch == 13 || ch == 32 {
            end = end - 1
        } else {
            return s.substring(0, end)
        }
    }
    ""
}

fn get_home_dir() -> Str {
    shell_exec("printf '%s' $HOME > /tmp/_pact_home")
    let home = read_file("/tmp/_pact_home")
    trim_str(home)
}

pub fn sanitize_url(url: Str) -> Str {
    let mut result = ""
    let mut i = 0
    while i < url.len() {
        let ch = url.char_at(i)
        let mut keep = 0
        if ch >= 48 && ch <= 57 {
            keep = 1
        }
        if ch >= 65 && ch <= 90 {
            keep = 1
        }
        if ch >= 97 && ch <= 122 {
            keep = 1
        }
        if keep == 1 {
            result = result.concat(url.substring(i, 1))
        } else {
            result = result.concat("_")
        }
        i = i + 1
    }
    result
}

// ── Git operations ──────────────────────────────────────────────

fn ensure_bare_clone(url: Str, cache_dir: Str) -> Int {
    let repo_dir = path_join(cache_dir, "repo.git")
    if is_dir(repo_dir) == 1 {
        shell_exec("git -C {repo_dir} fetch --tags --quiet 2>/dev/null")
    } else {
        shell_exec("git clone --bare --quiet {url} {repo_dir} 2>/dev/null")
    }
    0
}

fn resolve_commit(cache_dir: Str, ref: Str) -> Int {
    let repo_dir = path_join(cache_dir, "repo.git")
    let cmd = "git -C {repo_dir} rev-list -1 {ref} 2>/dev/null | head -c 40 > /tmp/_pact_commit"
    shell_exec(cmd)
    let raw = read_file("/tmp/_pact_commit")
    last_commit = trim_str(raw)
    if last_commit.len() == 0 {
        return 1
    }
    0
}

fn ensure_checkout(cache_dir: Str, commit: Str) -> Int {
    let checkout_dir = path_join(cache_dir, commit)
    if is_dir(checkout_dir) == 1 {
        last_checkout_path = checkout_dir
        return 0
    }
    let repo_dir = path_join(cache_dir, "repo.git")
    shell_exec("git clone --shared --quiet {repo_dir} {checkout_dir} 2>/dev/null")
    shell_exec("git -C {checkout_dir} checkout --quiet {commit} 2>/dev/null")
    last_checkout_path = checkout_dir
    0
}

fn compute_content_hash(dir: Str) -> Int {
    shell_exec("find {dir} -name '*.pact' -type f | sort | xargs cat | sha256sum | cut -c1-64 > /tmp/_pact_hash")
    let raw = read_file("/tmp/_pact_hash")
    last_content_hash = trim_str(raw)
    0
}

// ── Main fetch function ─────────────────────────────────────────

pub fn git_fetch(url: Str, tag: Str) -> Int {
    git_clear()

    let home = get_home_dir()
    let sanitized = sanitize_url(url)
    let cache_dir = path_join(path_join(path_join(home, ".pact"), "cache"), "git")
    let dep_dir = path_join(cache_dir, sanitized)

    shell_exec("mkdir -p {dep_dir}")

    let clone_rc = ensure_bare_clone(url, dep_dir)
    if clone_rc != 0 {
        return 1
    }

    let resolve_rc = resolve_commit(dep_dir, tag)
    if resolve_rc != 0 {
        return 1
    }

    let checkout_rc = ensure_checkout(dep_dir, last_commit)
    if checkout_rc != 0 {
        return 1
    }

    let hash_rc = compute_content_hash(last_checkout_path)
    if hash_rc != 0 {
        return 1
    }

    0
}

// ── Query functions ─────────────────────────────────────────────

pub fn git_get_commit() -> Str {
    last_commit
}

pub fn git_get_checkout_path() -> Str {
    last_checkout_path
}

pub fn git_get_content_hash() -> Str {
    last_content_hash
}
