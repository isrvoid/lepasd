/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module lepasd.app;

import std.array : array, join;
import std.path : buildPath;
import std.exception : enforce;
import std.file;
import std.stdio : File, writeln;
import std.format : format;
import std.typecons : Nullable;
import std.string : strip;

import lepasd.tags;
import lepasd.hashgen;

extern (C) int daemon(int, int);
extern (C) int mkfifo(const char*, uint);

void main(string[] args)
{
    import std.getopt;
    bool isAddTag, isTagLine;
    auto opt = getopt(args,
            config.passThrough,
            "add|a", "Add new tag to '" ~ BaseName.tags ~ "'.", &isAddTag,
            "tag|t", "Use tag ignoring '" ~ BaseName.tags ~ "'; for one-off use.", &isTagLine
            );

    if (opt.helpWanted)
    {
        defaultGetoptPrinter(helpText(), opt.options);
        return;
    }

    args = args[1 .. $];
    const isStartDaemon = !(isAddTag || isTagLine || args.length);
    Tag tag;
    if (isAddTag || isTagLine)
    {
        tag = parseTag(args);
        args.length = 0;
    }

    if (isAddTag)
    {
        writeNewTag(tag);
        if (!isTagLine)
            return;
    }

    const isRunning = isDaemonRunning();
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

    if (args.length > 1)
        throw new Exception("Single tag name argument allowed");

    if (args.length)
        tag = loadTag(args[0]);

    sendTag(tag);
    writeln("armed");
}

enum tagsHelpPath = buildPath("~", relConfigDir, BaseName.tags);
auto helpText()
{
    import lepasd.encoding : SpecialChar;
    enum confDir = buildPath("~", relConfigDir);
    enum crc = buildPath("~", relConfigDir, BaseName.crc);
    enum rawHelpFile = import("apphelp.txt");
    return format!rawHelpFile(confDir, path.trigger, crc, tagsHelpPath, SpecialChar.restrictedSet);
}

bool isDaemonRunning()
{
    try
    {
        const sPid = path.pid.readText.strip;
        const processName = buildPath("/proc", sPid, "comm").readText.strip;
        return processName == appName;
    }
    catch (Exception)
        return false;
}

Tag parseTag(string[] args) @safe
{
    enforce(args.length, "Missing tag argument");
    return Tag(args[0], args[1 .. $].join(" ").parseOpt.expand);
}

enum appName = "lepasd";
enum relConfigDir = buildPath(".config", appName);
enum BaseName : string
{
    tags = "tags",
    crc = "crc",
    pid = "pid",
    tagInput = "tag",
    trigger = "trigger"
}

const string configDir, tempFileDir;
struct Path
{
    string tags, crc, pid, tagInput, trigger;
}
const Path path;

static this()
{
    import std.process : environment;
    const home = environment.get("HOME");
    enforce(home, "HOME not set");
    configDir = buildPath(home, relConfigDir);
    tempFileDir = buildPath(tempDir(), appName);
    path.tags = buildPath(configDir, BaseName.tags);
    path.crc = buildPath(configDir, BaseName.crc);
    path.pid = buildPath(tempFileDir, BaseName.pid);
    path.tagInput = buildPath(tempFileDir, BaseName.tagInput);
    path.trigger = buildPath(tempFileDir, BaseName.trigger);
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
    if (!exists(configDir))
        mkdirRecurse(configDir);

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

extern (C) int lepasd_getpassword(void*, size_t) @nogc;

void startDaemon()
{
    import std.exception : ErrnoException;
    import std.stdio : write;
    import std.digest.crc : crc32Of, crcHexString;

    char[257] buf;
    scope(exit) buf[] = 0;
retry:
    write("Password: ");
    const length = lepasd_getpassword(&buf[0], buf.length);
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

    createTempFiles();
    daemonLoop(gen);
}

void createTempFiles()
{
    import std.process : thisProcessID;
    import std.conv : octal, to;
    import std.string : toStringz;
    try
        mkdir(tempFileDir);
    catch(Exception) { }
    std.file.write(path.pid, thisProcessID().to!string ~ '\n');
    mkfifo(path.tagInput.toStringz, octal!622);
    mkfifo(path.trigger.toStringz, octal!622);
}

void daemonLoop(ref HashGen gen)
{
    while (true)
    {
        auto tag = recvTag();
    }
}

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
    if (!exists(configDir))
        mkdirRecurse(configDir);

    {
        auto file = File(path.crc, "w");
        file.rawWrite(s);
        file.writeln();
    }
    writeln("CRC created: ", s);
}
