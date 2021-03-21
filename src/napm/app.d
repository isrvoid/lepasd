/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module napm.app;

import std.array : array, join;
import std.path : buildPath, asRelativePath;
import std.exception : enforce;
import std.file;
import std.stdio : File, writeln;
import std.format : format;
import std.typecons : Nullable;
import std.string : strip;

import napm.tags;

void main(string[] args)
{
    import std.getopt;
    bool isAddTag, isTagLine;
    auto opt = getopt(args,
            config.passThrough,
            "add|a", "Add new tag to '" ~ tagsBaseName ~ "'.", &isAddTag,
            "tag|t", "Use tag ignoring '" ~ tagsBaseName ~ "'; for one-off use.", &isTagLine
            );

    if (opt.helpWanted)
    {
        defaultGetoptPrinter("Type out passwords based on a single password, storage free.\n\nUsage:\n" ~
                "  Start the daemon:\n  $ napm\n" ~
                "  Assuming napm/tags has '@sometag', arm typing:\n  $ napm sometag\n" ~
                "  Within 10 s select the password field and press FIXME to type out the password.\n\n" ~
                "Files (tags, crc) are stored in '" ~ buildPath("~", relConfigDir) ~ "'\n",
                opt.options);
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

bool isDaemonRunning()
{
    try
    {
        const sPid = buildPath(tempDir(), "napm", "pid").readText.strip;
        const processName = buildPath("/proc", sPid, "comm").readText.strip;
        return processName == "napm";
    }
    catch (Exception)
        return false;
}

Tag parseTag(string[] args) @safe
{
    enforce(args.length, "Missing tag argument");
    return Tag(args[0], args[1 .. $].join(" ").parseOpt.expand);
}

enum relConfigDir = buildPath(".config", "napm");
enum tagsBaseName = "tags";
enum crcBaseName = "crc";
const string configDir;
const string tagsPath, crcPath;
static this()
{
    import std.process : environment;
    const home = environment.get("HOME");
    enforce(home, "HOME not set");
    configDir = buildPath(home, relConfigDir);
    tagsPath = buildPath(configDir, tagsBaseName);
    crcPath = buildPath(configDir, crcBaseName);
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

extern (C) int napm_getpassword(void*, size_t) @nogc;

void runDaemon()
{
    import std.exception : ErrnoException;
    import std.stdio : write;
    import std.digest.crc : crc32Of, crcHexString;
    // FIXME this has to work without input group; extract interface; use external tool
    enforce(canReadKeyboard(), "Failed to open keyboard. Not 'input' group member?");

    // TODO refactor
    const refCrc = loadCrc();
    if (refCrc.isNull)
    {
        writeln("A good password is strong and easy to remember: a made up sentence or combination of words.");
        writeln("Recommended length is at least 12 characters.");
        writeln("There is no strength analysis, choose wisely. The length can't be 0.");
        writeln();
    }
    char[257] buf;
    scope(exit) buf[] = 0;
retry:
    write("Password: ");
    const length = napm_getpassword(&buf[0], buf.length);
    writeln();
    if (length == -1)
    {
        import core.stdc.errno;
        if (errno != EINTR)
            throw new ErrnoException("error:");

        return;
    }
    enforce(length > 0, "Password can't have 0 length.");
    enforce(length < buf.length, format!"Max password length: %d"(buf.length - 1));
    class GenWrapper
    {
        import napm.hashgen;
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

// FIXME to be removed
bool canReadKeyboard()
{
    import std.algorithm : endsWith;
    foreach (string name; dirEntries("/dev/input/by-id", SpanMode.breadth))
        if (name.endsWith("kbd"))
        {
            try
            {
                File(name, "rb");
                return true;
            }
            catch (Exception)
                return false;
        }

    throw new Exception("No keyboard found");
}

Nullable!string loadCrc()
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
    writeln("CRC written: ", s);
    writeln("If it seems unfamiliar, consider killing and restaring the daemon to verify the password.");
    enum crcHintPath = buildPath("~", relConfigDir, crcBaseName);
    writeln("If it's wrong, remove '" ~ crcHintPath ~ "' and restart the daemon to retype.");
}
