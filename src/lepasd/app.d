/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module lepasd.app;

import core.thread : Thread;
import core.time : dur, Duration;
import std.array : array, join;
import std.conv : to;
import std.exception : enforce;
import std.file : exists, readText;
import std.format : format;
import std.path : buildPath;
import std.stdio : File, writeln;
import std.string : strip, toStringz;
import std.typecons : Nullable;

import lepasd.encoding;
import lepasd.hashgen;
import lepasd.swkeyboard;
import lepasd.tags;

extern (C) @nogc
{
    int daemon(int, int);
    int mkfifo(const char*, uint);
    enum SIGTERM = 15;
    int kill(int, int);
}

void main(string[] args)
{
    import std.getopt;
    import std.path : baseName;
    processName = args[0].baseName;
    bool isAddTag, isTagLine, isKill, isTest;
    const isEmptyArgs = args.length == 1;
    auto opt = getopt(args,
            config.passThrough,
            "add|a", "Add new tag to '" ~ BaseName.tags ~ "'.", &isAddTag,
            "tag|t", "Use tag ignoring '" ~ BaseName.tags ~ "'; for one-off use.", &isTagLine,
            "kill|k", "Kill the daemon.", &isKill,
            "test", "Make the daemon type a test line, compare with expected.", &isTest
            );

    if (opt.helpWanted)
    {
        defaultGetoptPrinter(helpText(), opt.options);
        return;
    }

    args = args[1 .. $];
    const isStartDaemon = isEmptyArgs;
    const shouldParseTag = isAddTag || isTagLine;
    const maybeExistingTagUse = !shouldParseTag && args.length > 0;
    const shouldSendTag = isTagLine || maybeExistingTagUse;
    const isDaemonRequired = isStartDaemon || shouldSendTag || isTest;

    void maybeCreateDirs()
    {
        import std.file : mkdirRecurse;
        if (!exists(configDir))
            mkdirRecurse(configDir);
        if (isDaemonRequired && !exists(runDir))
            mkdirRecurse(runDir);
    }
    maybeCreateDirs();

    Tag tag;
    if (shouldParseTag)
    {
        tag = parseTag(args);
        args = null;
    }

    if (isAddTag)
    {
        checkLength(tag);
        writeNewTag(tag);
    }

    if (!(isDaemonRequired || isKill))
        return;

    const pid = getPid();
    bool isRunning = isDaemonRunning(pid);
    if (isRunning && isKill)
    {
        enforce(!kill(pid.get, SIGTERM), "Failed to kill the daemon");
        isRunning = false;
    }

    if (!isDaemonRequired)
        return;

    enforce(SwKeyboard.canCreate, "Can't emulate keyboard. Missing udev uinput rule? (check --help)");

    if (isStartDaemon && isRunning)
    {
        writeln("daemon already running");
        return;
    }

    if (!isRunning)
    {
        if (!isStartDaemon)
            writeln("daemon not running");

        startDaemon();
        return;
    }

    if (isTest)
        test();

    if (!shouldSendTag)
        return;

    if (args.length > 1)
        throw new Exception("Single tag name argument allowed");

    if (args.length)
        tag = loadTag(args[0]);

    checkLength(tag);
    sendTag(tag);
    writeln("armed");
}

enum tagsHelpPath = buildPath("~", relConfigDir, BaseName.tags);
auto helpText()
{
    enum confDir = buildPath("~", relConfigDir);
    enum crc = buildPath("~", relConfigDir, BaseName.crc);
    enum trigger = buildPath("~", relRunDir, BaseName.trigger);
    enum rawHelpFile = import("apphelp.txt");
    enum initOpt = format!"v%d %d %c"(Tag.init.ver, Tag.init.length, TagTypeConv.toChar(Tag.init.type));
    return format!rawHelpFile(confDir, trigger, crc, tagsHelpPath, initOpt);
}

Nullable!int getPid()
{
    try
    {
        const pid = path.pid.readText.strip.to!int;
        enforce(pid > 0);
        return Nullable!int(pid);
    }
    catch (Exception)
        return Nullable!int();
}

static string processName;

bool isDaemonRunning(Nullable!int pid)
in (processName)
{
    if (pid.isNull)
        return false;

    try
    {
        const pidProcessName = buildPath("/proc", pid.get.to!string, "comm").readText.strip;
        return pidProcessName == processName;
    }
    catch (Exception)
        return false;
}

Tag parseTag(string[] args) @safe
{
    enforce(args.length, "Missing tag argument");
    return Tag(args[0], args[1 .. $].join(" ").parseOpt.expand);
}

void checkLength(in Tag tag) pure @safe
{
    enum minLength = 4;
    uint maxLength;
    final switch (tag.type)
    {
        case Tag.Type.numeric:
            maxLength = MaxLength.base10;
            break;
        case Tag.Type.alphanumeric:
            maxLength = MaxLength.base62;
            break;
        case Tag.Type.requiresMix:
        case Tag.Type.density:
            maxLength = MaxLength.base1023;
            break;
    }
    const isValidLength = tag.length >= minLength && tag.length <= maxLength;
    enforce(isValidLength, format!"Length '%d' is out of range [%d, %d] valid for '%c' encoding"(
            tag.length, minLength, maxLength, TagTypeConv.toChar(tag.type)));
}

void test()
{
    import std.stdio : readln;
    import std.string : stripRight;
    sendTag(Tag("dummy"));
    Thread.sleep(dur!"msecs"(10));
    File(path.trigger, "w").write("test");
    if (readln().stripRight == testString)
        writeln("OK");
    else
    {
        writeln(testString, " (expected)");
        throw new Exception("Mismatch. Keyboard layout not switched to English (US)?");
    }
}

enum relConfigDir = buildPath(".config", "lepasd");
enum relRunDir = buildPath(relConfigDir, BaseName.run);
enum BaseName : string
{
    tags = "tags",
    crc = "crc",
    pid = "pid",
    tagInput = "tag",
    trigger = "trigger",
    run = "run",
    error = "error"
}

struct Path
{
    string tags, crc, pid, tagInput, trigger, error;
}
const Path path;
const string configDir, runDir;

static this()
{
    import std.process : environment;
    const home = environment.get("HOME");
    enforce(home, "HOME not set");
    configDir = buildPath(home, relConfigDir);
    runDir = buildPath(home, relRunDir);

    path.tags = buildPath(configDir, BaseName.tags);
    path.crc = buildPath(configDir, BaseName.crc);
    path.pid = buildPath(runDir, BaseName.pid);
    path.tagInput = buildPath(runDir, BaseName.tagInput);
    path.trigger = buildPath(runDir, BaseName.trigger);
    path.error = buildPath(runDir, BaseName.error);
}

auto loadTag(string name)
{
    auto file = File(path.tags, "r");
    auto search = (() => file.byLine.findTag(name))();
    enforce(!search.isNull, format!"Tag '%s' not found in '%s'"(name, tagsHelpPath));
    return search.get;
}

void writeNewTag(Tag tag)
{
    auto file = File(path.tags, "a+");
    const isFileEmpty = !file.size;
    auto isNewTag = () => isFileEmpty || file.byLine.findTag(tag.name).isNull;
    enforce(isNewTag(), format!"Tag '%s' already exists in '%s'"(tag.name, tagsHelpPath));
    if (!isFileEmpty)
        file.writeln();
    file.writeln(tag.toLine);
    writeln("tag added");
}

void sendTag(Tag tag) @safe
{
    auto f = File(path.tagInput, "wb");
    f.rawWrite([cast(uint) tag.name.length]);
    f.rawWrite(tag.name);
    tag.name = null;
    f.rawWrite([tag]);
}

Tag recvTag() @trusted
{
    import core.stdc.stdio : fread;
    auto f = File(path.tagInput, "rb");
    auto fp = f.getFP();
    uint nl;
    enforce(1 == fread(&nl, nl.sizeof, 1, fp));
    auto name = new char[](nl);
    enforce(nl == fread(&name[0], 1, nl, fp));
    Tag result;
    enforce(1 == fread(&result, result.sizeof, 1, fp));
    result.name = name.idup;
    return result;
}

extern (C)
{
    int lepasd_getPassword(void*, size_t) @nogc;
    int lepasd_clearPipe(const char*) @nogc;
    ptrdiff_t lepasd_readPipe(const char*, void*, size_t, size_t) @nogc;
}

void startDaemon()
{
    import std.exception : ErrnoException;
    import std.stdio : write;
    import std.digest.crc : crc32Of, crcHexString;

    char[257] buf;
    scope(exit) buf[] = 0;
retry:
    write("Password: ");
    const length = lepasd_getPassword(&buf[0], buf.length);
    writeln();
    if (length == -1)
    {
        import core.stdc.errno;
        if (errno != EINTR)
            throw new ErrnoException("error:");

        return;
    }
    enforce(length > 0, "Empty password");
    enforce(length < buf.length, format!"Max password length: %d"(buf.length - 1));

    auto gen = HashGen(buf[0 .. length]);
    const crc = gen.hash("CRC-32").crc32Of.crcHexString;
    const refCrc = loadCrc();
    if (refCrc.isNull)
        storeCrc(crc);
    else if (crc != refCrc.get)
    {
        writeln(format!"CRC mismatch: reference %s != %s"(refCrc.get, crc));
        goto retry;
    }

    const err = daemon(0, 0);
    if (err)
        return;

    try
    {
        createRunFiles();
        enforce(!lepasd_clearPipe(path.tagInput.toStringz));
        auto sk = SwKeyboard(0);
        daemonLoop(gen, sk);
    }
    catch (Throwable e)
    {
        File(path.error, "w").writeln(e);
        assert(0);
    }
}

void createRunFiles()
{
    import std.conv : octal;
    import std.process : thisProcessID;
    void makeFifo(string path)
    {
        if (!exists(path))
            mkfifo(path.toStringz, octal!600);
    }

    File(path.pid, "w").writeln(thisProcessID().to!string);
    makeFifo(path.tagInput);
    makeFifo(path.trigger);
}

void daemonLoop(in ref HashGen gen, in ref SwKeyboard keyboard)
{
    enum Trigger
    {
        timeout,
        fire,
        test,
        invalid
    }

    auto recvTrigger(Duration timeout)
    {
        import std.algorithm : startsWith;
        const triggerPath = path.trigger.toStringz;
        enforce(!lepasd_clearPipe(triggerPath));
        char[32] buf;
        const length = lepasd_readPipe(triggerPath, &buf[0], buf.sizeof, timeout.total!"msecs");
        enforce(length != -1);
        if (!length)
            return Trigger.timeout;

        if (buf[0] == 1 || buf[0] == '1')
            return Trigger.fire;

        if (buf[].startsWith("test"))
            return Trigger.test;

        return Trigger.invalid;
    }

    void encodeAndType(Tag tag)
    {
        auto hash = gen.hash(versionedTag(tag.name, tag.ver));
        scope(exit) hash[] = 0;
        final switch (tag.type)
        {
            case Tag.Type.alphanumeric:
                auto s = encodeBase62(hash);
                scope(exit) s[] = 0;
                keyboard.write(s[0 .. tag.length]);
                break;
            case Tag.Type.numeric:
                auto s = encodeBase10(hash);
                scope(exit) s[] = 0;
                keyboard.write(s[0 .. tag.length]);
                break;
            case Tag.Type.requiresMix:
                auto s = encodeBase1023!(Lut.mixed)(hash);
                scope(exit) s[] = 0;
                keyboard.write(s[0 .. tag.length]);
                break;
            case Tag.Type.density:
                auto s = encodeBase1023!(Lut.dense)(hash);
                scope(exit) s[] = 0;
                keyboard.write(s[0 .. tag.length]);
                break;
        }
    }

    while (true)
    {
        auto tag = recvTag();
        enum armedDuration = dur!"seconds"(12);
        const trigger = recvTrigger(armedDuration);

        if (trigger == Trigger.fire)
        {
            Thread.sleep(dur!"msecs"(500)); // allow time to release any physical keys
            encodeAndType(tag);
        }
        else if (trigger == Trigger.test)
        {
            Thread.sleep(dur!"msecs"(250)); // allow time to release 'Enter'
            keyboard.write(testString ~ '\n');
        }
    }
}

alias testString = Lut.dense;

Nullable!string loadCrc() nothrow
{
    import std.algorithm : map;
    import std.ascii : toUpper;
    try
        return Nullable!string(readText(path.crc).strip.map!(a => cast(char) a.toUpper).array);
    catch (Exception)
        return Nullable!string();
}

void storeCrc(string s)
{
    {
        auto file = File(path.crc, "w");
        file.rawWrite(s);
        file.writeln();
    }
    writeln("CRC created: ", s);
}
