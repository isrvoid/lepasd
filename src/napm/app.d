/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module napm.app;

void main(string[] args)
{
    import std.getopt;

    bool shouldAddTag, isTagLine;
    auto opt = getopt(args,
            config.passThrough,
            "add|a", "Add tag to napm_tags.", &shouldAddTag,
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
}
