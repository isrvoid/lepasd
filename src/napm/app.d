/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module napm.app;
import std.path : buildPath;
import std.file;
import std.exception : enforce;
import std.format : format;

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
        writeNewTag(args[1 .. $]);

        if (!isTagLine)
            return;
    }
}

@safe:

const string configDir;
static this()
{
    import std.process : environment;
    const home = environment.get("HOME");
    enforce(home, "HOME not set");
    configDir = buildPath(home, ".config", "napm");
}

void writeNewTag(string[] args)
{
    import std.array : join;
    import std.stdio : File;
    import napm.tags;
    enforce(args.length, "Missing tag argument");
    const tag = Tag(args[0], args[1 .. $].join(" ").parseOpt.expand);

    if (!exists(configDir))
        mkdirRecurse(configDir);

    enum fileName = "napm_tags";
    auto file = File(buildPath(configDir, fileName), "a+");
    bool tagExists() @trusted
    {
        if (!file.size)
            return false;

        return file.byLine.findTag(tag.name).isNull == false;
    }
    enforce(!tagExists, format!"Tag '%s' already exists in %s"(tag.name, fileName));
    file.writeln(tag.toLine);
}
