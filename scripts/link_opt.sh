# Sourced by scripts that link the compiler binaries, and read by the Taskfile
# (`LINK_OPT`, `SRC_CFLAGS`). The C the compiler emits does not depend on these
# flags. The opt levels set how fast the linked compiler runs.
# Installed and bootstrap binaries: -O2, since users run them.
BLINK_LINK_OPT="${BLINK_LINK_OPT--O2}"
# gen1 is rebuilt on every gate run, and its blink emits the C for every corpus
# file. At -O0 the runtime's static inline list accessors stay calls, and the
# emit is about a quarter of corpus work; -O1 nearly halves the emit for a few
# seconds more link. -O2 adds about 8s more link for little more emit speed.
BLINK_GEN1_LINK_OPT="${BLINK_GEN1_LINK_OPT--O1}"
# Flags for a hand cc of the C of src. That C declares each foreign symbol inside
# `#ifndef BLINK_DECLARED_<sym>`, which only the blink driver's header probe defines.
# The runtime headers already declare `link` (unistd.h), so without the define the
# second prototype conflicts.
BLINK_SRC_CFLAGS="-DBLINK_DECLARED_link"
