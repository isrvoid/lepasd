/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module napm.app;
import std.path : buildPath;
import std.file;
import std.exception : enforce;
import std.format : format;

import napm.tags;

void main(string[] args)
{
    import std.getopt;
    bool isNewTag, isTagLine;
    auto opt = getopt(args,
            config.passThrough,
            "add|a", "Add new tag to napm_tags.", &isNewTag,
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

    if (isNewTag)
    {
        const tag = parseTag(args[1 .. $]);
        writeNewTag(tag);

        if (!isTagLine)
            return;
    }
}

@safe:

Tag parseTag(string[] args)
{
    import std.array : join;
    enforce(args.length, "Missing tag argument");
    return Tag(args[0], args[1 .. $].join(" ").parseOpt.expand);
}

const string configDir;
static this()
{
    import std.process : environment;
    const home = environment.get("HOME");
    enforce(home, "HOME not set");
    configDir = buildPath(home, ".config", "napm");
}

void writeNewTag(Tag tag)
{
    import std.array : join;
    import std.stdio : File;
    if (!exists(configDir))
        mkdirRecurse(configDir);

    enum fileName = "napm_tags";
    auto file = File(buildPath(configDir, fileName), "a+");
    const isFileEmpty = !file.size;
    auto isNewTag = () @trusted => isFileEmpty || file.byLine.findTag(tag.name).isNull;
    enforce(isNewTag(), format!"Tag '%s' already exists in %s"(tag.name, fileName));
    if (!isFileEmpty)
        file.writeln();
    file.writeln(tag.toLine);
}
