# Sourced by scripts that link the compiler binaries, and read by the Taskfile
# (`LINK_OPT`). The C the compiler emits does not depend on these flags; they
# only set how fast the linked compiler runs.
# Installed and bootstrap binaries: -O2, since users run them.
BLINK_LINK_OPT="${BLINK_LINK_OPT--O2}"
# gen1 is rebuilt on every gate run, and its blink emits the C for every corpus
# file. At -O0 the runtime's static inline list accessors stay calls, and the
# emit is about a quarter of corpus work; -O1 nearly halves the emit for a few
# seconds more link. -O2 adds about 8s more link for little more emit speed.
BLINK_GEN1_LINK_OPT="${BLINK_GEN1_LINK_OPT--O1}"
