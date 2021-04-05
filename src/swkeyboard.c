/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

#define _DEFAULT_SOURCE 1
#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <fcntl.h>
#include <linux/uinput.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define ALPHA_KEYS \
    KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, \
    KEY_K, KEY_L, KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, \
    KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z

#define NUMERIC_KEYS KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9

#define TYPE(_key) if (typeKey(fd, _key)) return -1
#define SHIFT_TYPE(_key) if (shiftTypeKey(fd, _key)) return -1

static const uint16_t alphaLut[] = {
    ALPHA_KEYS
};

static const uint16_t numericLut[] = {
    NUMERIC_KEYS
};

static const uint16_t availableKeys[] = {
    KEY_LEFTSHIFT,
    ALPHA_KEYS, NUMERIC_KEYS,
    KEY_APOSTROPHE, KEY_EQUAL, KEY_COMMA, KEY_MINUS, KEY_SEMICOLON, KEY_SLASH,
    KEY_LEFTBRACE, KEY_RIGHTBRACE, KEY_GRAVE
};

static int syncEvent(int fd) {
    struct input_event e = { .type = EV_SYN, .code = SYN_REPORT };
    return -(write(fd, &e, sizeof e) == -1);
}

static int keyAction(int fd, uint16_t key, bool isPressed) {
    struct input_event e = { .type = EV_KEY, .code = key, .value = isPressed };
    return -(write(fd, &e, sizeof e) == -1);
}

static int typeKey(int fd, uint16_t key) {
    if (keyAction(fd, key, true))
        return -1;
    if (keyAction(fd, key, false))
        return -1;
    if (syncEvent(fd))
        return -1;
    return 0;
}

static int shiftTypeKey(int fd, uint16_t key) {
    if (keyAction(fd, KEY_LEFTSHIFT, true))
        return -1;
    if (keyAction(fd, key, true))
        return -1;
    if (keyAction(fd, key, false))
        return -1;
    if (keyAction(fd, KEY_LEFTSHIFT, false))
        return -1;
    if (syncEvent(fd))
        return -1;
    return 0;
}

int lepasd_swKeyboardInit(void) {
    const int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd == -1)
        return -1;

    if (ioctl(fd, UI_SET_EVBIT, EV_KEY) == -1)
        return -1;

    const size_t keyCount = sizeof availableKeys / sizeof *availableKeys;
    for (size_t i = 0; i < keyCount; ++i)
        if (ioctl(fd, UI_SET_KEYBIT, availableKeys[i]) == -1)
            return -1;

    struct uinput_setup usetup = { .id = { .bustype = BUS_USB, .vendor = 0x7fff, .product = 0x100 } };
    strcpy(usetup.name, "lepasd software keyboard");
    if (ioctl(fd, UI_DEV_SETUP, &usetup) == -1)
        return -1;

    if (ioctl(fd, UI_DEV_CREATE) == -1)
        return -1;

    return fd;
}

static int typeAlpha(int fd, char c, bool isUpperCase) {
    const uint16_t key = alphaLut[c - 'a'];
    if (isUpperCase) {
        SHIFT_TYPE(key);
    } else {
        TYPE(key);
    }
    return 0;
}

static int typeNumeric(int fd, char c) {
    const uint16_t key = numericLut[c - '0'];
    TYPE(key);
    return 0;
}

static int typeSpecial(int fd, char c) {
    switch (c) {
        case '!':
            SHIFT_TYPE(KEY_1);
            break;
        case '#':
            SHIFT_TYPE(KEY_3);
            break;
        case '$':
            SHIFT_TYPE(KEY_4);
            break;
        case '%':
            SHIFT_TYPE(KEY_5);
            break;
        case '\'':
            TYPE(KEY_APOSTROPHE);
            break;
        case '(':
            SHIFT_TYPE(KEY_9);
            break;
        case ')':
            SHIFT_TYPE(KEY_0);
            break;
        case '+':
            SHIFT_TYPE(KEY_EQUAL);
            break;
        case ',':
            TYPE(KEY_COMMA);
            break;
        case '-':
            TYPE(KEY_MINUS);
            break;
        case ':':
            SHIFT_TYPE(KEY_SEMICOLON);
            break;
        case '?':
            SHIFT_TYPE(KEY_SLASH);
            break;
        case '@':
            SHIFT_TYPE(KEY_2);
            break;
        case '[':
            TYPE(KEY_LEFTBRACE);
            break;
        case ']':
            TYPE(KEY_RIGHTBRACE);
            break;
        case '^':
            SHIFT_TYPE(KEY_6);
            break;
        case '_':
            SHIFT_TYPE(KEY_MINUS);
            break;
        case '`':
            TYPE(KEY_GRAVE);
            break;
        case '{':
            SHIFT_TYPE(KEY_LEFTBRACE);
            break;
        case '}':
            SHIFT_TYPE(KEY_RIGHTBRACE);
            break;
        case '~':
            SHIFT_TYPE(KEY_GRAVE);
            break;
        default:
            errno = EINVAL;
            return -1;
    }
    return 0;
}

static int typeChar(int fd, char c) {
    const struct timespec dur = { .tv_nsec = 2000000 };
    nanosleep(&dur, NULL);
    const bool isUpperCase = c >= 'A' && c <= 'Z';
    if (isUpperCase)
        c += 'a' - 'A';

    const bool isAlpha = c >= 'a' && c <= 'z';
    if (isAlpha)
        return typeAlpha(fd, c, isUpperCase);

    const bool isNumeric = c >= '0' && c <= '9';
    if (isNumeric)
        return typeNumeric(fd, c);

    return typeSpecial(fd, c);
}

int lepasd_swKeyboardWrite(int fd, const char* s, size_t length) {
    for (size_t i = 0; i < length; ++i)
        if (typeChar(fd, s[i]))
            return -1;

    return 0;
}
