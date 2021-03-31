/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

#define _POSIX_C_SOURCE 1
#define _DEFAULT_SOURCE 1
#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>

#include <fcntl.h>
#include <poll.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>

int lepasd_getPassword(void* dest, size_t destLength) {
    if (destLength > INT_MAX) {
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
    const char* destEnd = (char*)dest + destLength;
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

int lepasd_clearPipe(const char* path) {
    const int fd = open(path, O_RDONLY | O_NONBLOCK);
    if (fd == -1)
        return -1;

    struct pollfd fds[1];
    fds[0].fd = fd;
    fds[0].events = POLLIN | POLLPRI;
    int ret = poll(fds, 1, 1);
    if (ret == -1 || ret == 0)
        goto exit;

    char sink[128];
    while (1) {
        ssize_t n = read(fd, sink, sizeof sink);
        if (n < (ssize_t)sizeof sink) {
            ret = n == -1 ? -1 : 0;
            break;
        }
    }
exit:
    if (close(fd))
        return -1;

    return ret;
}

ssize_t lepasd_readPipe(const char* path, void* dest, size_t destLength, size_t msTimeout) {
    assert(msTimeout <= INT_MAX);
    const int fd = open(path, O_RDONLY | O_NONBLOCK);
    if (fd == -1)
        return -1;

    struct pollfd fds[1];
    fds[0].fd = fd;
    fds[0].events = POLLIN | POLLPRI;
    ssize_t ret = poll(fds, 1, (int)msTimeout);
    if (ret == -1 || ret == 0)
        goto exit;

    ret = read(fd, dest, destLength);
exit:
    if (close(fd))
        return -1;

    return ret;
}
