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

        runDaemon();
        return;
    }

    if (args.length > 1)
        throw new Exception("Single tag name argument allowed");

    if (args.length)
        tag = loadTag(args[0]);

    sendTag(tag);
}

auto helpText()
{
    import lepasd.encoding : SpecialChar;
    enum
    {
        confDir = buildPath("~", relConfigDir),
        crc = buildPath("~", relConfigDir, BaseName.crc),
        tags = buildPath("~", relConfigDir, BaseName.tags),
        rawHelpFile = import("apphelp.txt")
    }
    return format!rawHelpFile(confDir, triggerPath, crc, tags, SpecialChar.restrictedSet);
}

bool isDaemonRunning()
{
    try
    {
        const sPid = buildPath(tempDir(), appName, BaseName.pid).readText.strip;
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
    crc = "crc",
    pid = "pid",
    tags = "tags",
    trigger = "trigger"
}
const string configDir;
const string tagsPath, crcPath, triggerPath;
static this()
{
    import std.process : environment;
    const home = environment.get("HOME");
    enforce(home, "HOME not set");
    configDir = buildPath(home, relConfigDir);
    tagsPath = buildPath(configDir, BaseName.tags);
    crcPath = buildPath(configDir, BaseName.crc);
    triggerPath = buildPath(tempDir(), appName, BaseName.trigger);
}

auto loadTag(string name)
{
    auto file = File(tagsPath, "r");
    auto search = (() => file.byLine.findTag(name))();
    enforce(!search.isNull, format!"Tag '%s' not found in '%s'"(name, tagsPath));
    return search.get;
}

void writeNewTag(Tag tag)
{
    if (!exists(configDir))
        mkdirRecurse(configDir);

    auto file = File(tagsPath, "a+");
    const isFileEmpty = !file.size;
    auto isNewTag = () => isFileEmpty || file.byLine.findTag(tag.name).isNull;
    enforce(isNewTag(), format!"Tag '%s' already exists in '%s'"(tag.name, tagsPath));
    if (!isFileEmpty)
        file.writeln();
    file.writeln(tag.toLine);
    writeln("tag added");
}

void sendTag(Tag tag)
{
    // FIXME
    writeln("armed");
}

extern (C) int lepasd_getpassword(void*, size_t) @nogc;

void runDaemon()
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
    class GenWrapper
    {
        import lepasd.hashgen;
        HashGen m;
        alias m this;
        this(char[] pw)
        {
            m = HashGen(pw);
        }
    }
    auto gen = new GenWrapper(buf[0 .. length]);
    scope(exit) gen.m.destroy!false();

    const crc = gen.hash("CRC-32").crc32Of.crcHexString;
    const refCrc = loadCrc();
    if (refCrc.isNull)
        storeCrc(crc);
    else if (crc != refCrc.get)
    {
        writeln(format!"CRC mismatch: reference %s != %s"(refCrc.get, crc));
        goto retry;
    }

    writeln("starting daemon");
    // FIXME
}

Nullable!string loadCrc() nothrow
{
    import std.algorithm : map;
    import std.ascii : toUpper;
    try
        return Nullable!string(readText(crcPath).strip.map!(a => cast(char) a.toUpper).array);
    catch (Exception)
        return Nullable!string();
}

void storeCrc(string s)
{
    if (!exists(configDir))
        mkdirRecurse(configDir);

    {
        auto file = File(crcPath, "w");
        file.rawWrite(s);
        file.writeln();
    }
    writeln("CRC created: ", s);
}
