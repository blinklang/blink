# blink test build workers and BLINK_MANIFEST_REPORTED

`blink test` reports the blink.toml issues (E0843, W1001) once, then builds each
test file in a `blink build` worker. Each worker loads blink.toml again. To keep
the worker from reporting the same rows a second time, the command starts it as
`/usr/bin/env BLINK_MANIFEST_REPORTED=1 <blink> build ...`.

`BLINK_MANIFEST_REPORTED` is internal. `blink test` sets it only for its build
workers, never in its own environment, so the test binaries it runs do not see
it. When the variable is `1`, a build reports no blink.toml rows. The `[lints]`
levels still apply. A user who sets it only hides the blink.toml rows from their
own builds. An invalid lint level still fails `blink test`, since the command
reports it before it starts a worker.

The `env` wrapper exists because std.process cannot yet set an environment
variable for one spawned child. When it can, cmd_test sets the variable on the
spawn and the wrapper goes.
