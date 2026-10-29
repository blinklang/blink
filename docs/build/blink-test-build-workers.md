# blink test build workers and BLINK_MANIFEST_REPORTED

`blink test` reports the blink.toml issues (E0843, W1001, W1002) once, then builds each
test file in a build worker. Each worker loads blink.toml again. To keep
the worker from reporting the same rows a second time, the command starts it as
`/usr/bin/env BLINK_MANIFEST_REPORTED=1 <blink> __test-build ...`.

`BLINK_MANIFEST_REPORTED` is internal. `blink test` sets it only for its build
workers, never in its own environment, so the test binaries it runs do not see
it. When the variable is `1`, a build reports no blink.toml rows. The `[lints]`
levels still apply. A user who sets it only hides the blink.toml rows from their
own builds. An invalid lint level still fails `blink test`, since the command
reports it before it starts a worker.

The `env` wrapper exists because std.process cannot yet set an environment
variable for one spawned child. When it can, cmd_test sets the variable on the
spawn and the wrapper goes.

## The test build

Only the build that `blink test` makes keeps the test blocks (spec §2.20). Each
other build, with each option, leaves out the test bodies, the name and tag
tables and the runner. The front end still type-checks each test block.

`CgConfig.test_build` holds this decision. It is 0 by default, so a new caller
of the codegen driver strips the tests. Three callers set it to 1:

- `blink test` on one file sets it in its own process.
- `blink test` on a directory starts each worker as
  `blink __test-build <file> -o <out> --debug`. `__test-build` is hidden, like
  `__emit-per-module`. It takes the arguments of `blink build`, but it makes a
  test build. It does not go through the build daemon.
- `blinkc --test-build` is for the test helpers and the format scripts.
  blinkc is a development tool, and the install does not ship it.

A test build runs the runner and never main, also when the file has no test
block: the runner then runs zero tests. Any other build has no runner, so
`./app --test` gives `--test` to main. The emit reuse record keys on
`test_build`, so a test build and a plain build of one output never share a unit.
