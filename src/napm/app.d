/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module napm.app;

import std.path : buildPath;
import std.exception : enforce;
import std.file;
import std.stdio : File, writeln;
import std.format : format;

import napm.tags;

void main(string[] args)
{
    import std.getopt;
    bool isAddTag, isTagLine;
    auto opt = getopt(args,
            config.passThrough,
            "add|a", "Add new tag to napm_tags.", &isAddTag,
            "tag|t", "Use tag ignoring napm_tags. Intended for one-off use.", &isTagLine
            );

    if (opt.helpWanted)
    {
        defaultGetoptPrinter("Type out passwords based on a single password, storage free.\nUsage:\n" ~
                "  Start the daemon with 'input' group privilege:\n  $ sudo napm -g input\n" ~
                "  Assuming napm_tags has '@sometag', arm typing:\n  $ napm sometag\n" ~
                "  Within 10 s select the password field and press 'Ctrl' twice to type out the password.",
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

@safe:

bool isDaemonRunning()
{
    import std.string : strip;
    try
    {
        const sPid = buildPath(tempDir(), "napm", "pid").readText.strip;
        const processName = buildPath("/proc", sPid, "comm").readText.strip;
        return processName == "napm";
    }
    catch (Exception)
    {
        return false;
    }
}

Tag parseTag(string[] args)
{
    import std.array : join;
    enforce(args.length, "Missing tag argument");
    return Tag(args[0], args[1 .. $].join(" ").parseOpt.expand);
}

const string configDir;
const string tagsPath;
static this()
{
    import std.process : environment;
    const home = environment.get("HOME");
    enforce(home, "HOME not set");
    configDir = buildPath(home, ".config", "napm");
    tagsPath = buildPath(configDir, "napm_tags");
}

auto loadTag(string name)
{
    auto file = File(tagsPath, "r");
    auto search = (() @trusted => file.byLine.findTag(name))();
    enforce(!search.isNull, format!"Tag '%s' not found in '%s'"(name, tagsPath));
    return search.get;
}

void writeNewTag(Tag tag)
{
    import std.array : join;
    if (!exists(configDir))
        mkdirRecurse(configDir);

    auto file = File(tagsPath, "a+");
    const isFileEmpty = !file.size;
    auto isNewTag = () @trusted => isFileEmpty || file.byLine.findTag(tag.name).isNull;
    enforce(isNewTag(), format!"Tag '%s' already exists in '%s'"(tag.name, tagsPath));
    if (!isFileEmpty)
        file.writeln();
    file.writeln(tag.toLine);
    writeln("tag added");
}

void runDaemon()
{
    // FIXME
    writeln("starting daemon");
    // input readable?
    // crc?
}

void sendTag(Tag tag)
{
    // FIXME
    writeln("armed");
}
