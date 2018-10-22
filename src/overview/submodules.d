/*******************************************************************************

    Utilities to fetch/parse git submodule information via GitHub API

    Copyright:
        Copyright (c) 2009-2016 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module overview.submodules;

import provider.api.Repos;

/**
    Represents information about a single submodule
 **/
struct Submodule
{
    // submodule name, same as --name argument in git CLI
    string name;
    // relative path to the submodule from the repository root
    string path;
    // submodule URL
    string url;
}

/**
    Queries .gitmodules for a specified repository and parses them into
    `Submodule` metadata array

    Params:
        repo = GitHub repository

    Returns:
        sumbodule information for that repository
 **/
Submodule[] listSubmodules ( Repository repo )
{
    import std.utf;

    auto gitmodules = cast(string) repo.download(".gitmodules").expectFile.content;
    validate(gitmodules);

    return parseGitModules(gitmodules);
}

/**
    Params:
        input = content of .gitmodules file

    Returns:
        .gitmodules information parsed and split into array of metadata structs
 **/
private Submodule[] parseGitModules ( string input )
{
    import std.regex;
    import std.algorithm.iteration;
    import std.range : take;
    import std.typecons : Yes;
    import std.string : strip;

    static rgxSection = regex(`^\[submodule "(.+)"\]$`);
    static rgxEntry = regex(`^(\S+)\s*=\s*(.+)$`);

    auto lines = input
        .splitter("\n")
        .map!(line => strip(line))
        .filter!(line => line.length > 0);

    Submodule[] result;
    Submodule last;

    while (!lines.empty)
    {
        auto line = lines.front;
        scope(exit)
            lines.popFront();

        auto match = line.matchFirst(rgxSection);
        if (!match.empty)
        {
            if (last.url.length && last.name.length)
            {
                result ~= last;
                last = Submodule.init;
            }

            last.name = match[1];
            continue;
        }

        match = line.matchFirst(rgxEntry);
        if (!match.empty)
        {
            if (match[1] == "path")
                last.path = match[2];
            if (match[1] == "url")
                last.url = match[2];
        }
    }

    if (last.url.length && last.name.length)
        result ~= last;

    return result;
}

unittest
{
    auto text = `
[submodule "first"]
    path = submodules/first
    url = https://github.com/organization/first.git
[submodule "second"]
    path = submodules/second
    url = https://github.com/organization/second.git
[submodule "third"]
    path = submodules/third
    url = https://github.com/organization/third.git`;

    assert (parseGitModules(text) == [
        Submodule("first", "submodules/first",
            "https://github.com/organization/first.git"),
        Submodule("second", "submodules/second",
            "https://github.com/organization/second.git"),
        Submodule("third", "submodules/third",
            "https://github.com/organization/third.git")
    ]);
}
