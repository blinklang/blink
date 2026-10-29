#!/bin/bash
# Runs `blink test` so that it caps each test binary's memory and process
# count itself, on top of the time limit it always applies. In a gate run,
# blink shares the gate's cgroup with its task and shell ancestors, so the
# runtime cannot give a child a cgroup and `blink test --memory` would be a
# usage error. `capped.sh --own-cgroup` moves blink into a cgroup that holds
# only it; there blink can cap each test binary, and a runaway test binary
# ends as aborted with a limit instead of taking the whole gate budget.
# Where no such cgroup exists (BLINK_GATE_CAP=0, no systemd user session,
# macOS), blink test runs with the time limit only, and a line says so.
#
#   scripts/blink_test_capped.sh <blink> test <args> ...
#
# BLINK_TEST_MEMORY (default 2G) and BLINK_TEST_PROCESSES (default 256) set
# the per-binary caps. 256 stays well under the gate's TasksMax, so the
# per-binary cap ends a fork loop before the gate's cap does.
set -u
if [ "${1:-}" != --inner ]; then
    exec "$(dirname "$0")/capped.sh" --own-cgroup "$0" --inner "$@"
fi
shift
if [ "${BLINK_OWN_CGROUP:-}" = 1 ]; then
    exec "$@" --memory "${BLINK_TEST_MEMORY:-2G}" --processes "${BLINK_TEST_PROCESSES:-256}"
fi
echo "blink_test_capped.sh: each test binary gets its time limit only, no memory or process cap" >&2
exec "$@"
