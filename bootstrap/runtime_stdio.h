#ifndef PACT_RUNTIME_STDIO_H
#define PACT_RUNTIME_STDIO_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* Read one line from stdin (strips \r\n and \n, returns strdup'd string) */
PACT_UNUSED static const char* pact_stdin_read_line(void) {
    char buf[4096];
    int64_t pos = 0;
    while (pos < (int64_t)(sizeof(buf) - 1)) {
        int ch = fgetc(stdin);
        if (ch == EOF || ch == '\n') break;
        buf[pos++] = (char)ch;
    }
    if (pos > 0 && buf[pos - 1] == '\r') pos--;
    buf[pos] = '\0';
    return strdup(buf);
}

/* Read exactly n bytes from stdin into Bytes */
PACT_UNUSED static pact_bytes* pact_stdin_read_bytes(int64_t n) {
    pact_bytes* b = pact_bytes_new();
    if (n <= 0) return b;
    if (n > b->cap) {
        b->cap = n;
        b->data = (uint8_t*)realloc(b->data, (size_t)b->cap);
    }
    int64_t total = 0;
    while (total < n) {
        size_t got = fread(b->data + total, 1, (size_t)(n - total), stdin);
        if (got == 0) break;
        total += (int64_t)got;
    }
    b->len = total;
    return b;
}

/* Write string to stdout with immediate flush */
PACT_UNUSED static void pact_stdout_write(const char* data) {
    size_t len = strlen(data);
    fwrite(data, 1, len, stdout);
    fflush(stdout);
}

/* Write bytes to stdout with immediate flush */
PACT_UNUSED static void pact_stdout_write_bytes(pact_bytes* b) {
    fwrite(b->data, 1, (size_t)b->len, stdout);
    fflush(stdout);
}

#endif /* PACT_RUNTIME_STDIO_H */
