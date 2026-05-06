#ifndef BLINK_RUNTIME_TERM_H
#define BLINK_RUNTIME_TERM_H

#include <unistd.h>
#include <sys/ioctl.h>
#include <limits.h>

BLINK_RT_FN int64_t blink_term_isatty(int64_t fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_term_isatty(int64_t fd) {
    if (fd < 0 || fd > INT_MAX) return 0;
    return isatty((int)fd) ? 1 : 0;
}
#endif

BLINK_RT_FN int64_t blink_term_width(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_term_width(void) {
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
        return (int64_t)ws.ws_col;
    }
    return 80;
}
#endif

BLINK_RT_FN int64_t blink_term_height(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_term_height(void) {
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 0) {
        return (int64_t)ws.ws_row;
    }
    return 24;
}
#endif

#endif /* BLINK_RUNTIME_TERM_H */
