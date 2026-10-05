# Sourced by scripts that link the compiler binaries, and read by the Taskfile
# (`LINK_OPT`). The C the compiler emits does not depend on these flags; they
# only set how fast the linked compiler runs.
# Installed and bootstrap binaries: -O2, since users run them.
BLINK_LINK_OPT="${BLINK_LINK_OPT--O2}"
# gen1 is rebuilt on every gate run and the corpus is dominated by cc and the
# test programs, so a -O2 link costs more wall time than it saves.
BLINK_GEN1_LINK_OPT="${BLINK_GEN1_LINK_OPT--O0}"
