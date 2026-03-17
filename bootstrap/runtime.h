#ifndef PACT_RUNTIME_H
#define PACT_RUNTIME_H

/* Core runtime: alloc, list, map, bytes, strings, file I/O, closures, effects */
#include "runtime_core.h"

/* Feature modules */
#include "runtime_tcp.h"
#include "runtime_unix_socket.h"
#include "runtime_thread.h"
#include "runtime_process.h"
#include "runtime_test.h"
#include "runtime_sqlite.h"
#include "runtime_stdio.h"

#endif /* PACT_RUNTIME_H */
