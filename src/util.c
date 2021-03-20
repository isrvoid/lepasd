/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

#define _POSIX_C_SOURCE 1
#define _DEFAULT_SOURCE 1
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <termios.h>

int napm_getpassword(void* dest, size_t n) {
    if (n > INT_MAX) {
        errno = EINVAL;
        return -1;
    }
    struct termios save, raw;
    const int fd = fileno(stdin);
    if (tcgetattr(fd, &save))
        return -1;

    cfmakeraw(&raw);
    if (tcsetattr(fd, TCSAFLUSH, &raw))
        return -1;

    bool err = false;
    const char* destEnd = (char*)dest + n;
    char* p = (char*)dest;
    while (p < destEnd) {
        const char c = (char)getc(stdin);
        switch (c) {
            case 0x03: // Ctrl-C
                errno = EINTR;
                err = true;
                goto exit;
            case '\r': // enter
                goto exit;
            case 0x08: // Ctrl-H
            case 0x7f: // backspace
                if (p > dest)
                    --p;
                continue;
            case 0x15: // Ctrl-U
                p = (char*)dest;
                continue;
        }
        *p++ = c;
    }
exit:
    (void)tcsetattr(fd, TCSAFLUSH, &save);
    return err ? -1 : (int)(p - (char*)dest);
}
