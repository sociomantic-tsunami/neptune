/*******************************************************************************

    Git-cmd interaction helper

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.gitHelper;

import release.shellHelper;

/***************************************************************************

    Finds out if ref1 is an ancestor of ref2

    Params:
        ref1 = ref to check if it is an ancestor of ref2
        ref2 = ref to check if it is a decendant of ref1

    Returns:
        true if ref1 is an ancestor of ref2

***************************************************************************/

bool isAncestor ( string ref1, string ref2 )
{
    import std.process : executeShell;
    import std.format;

    auto c = executeShell(format("git merge-base --is-ancestor %s %s",
                                 ref1, ref2));

    // Status 0 => is ancestor
    // Status 1 => is not
    if (c.status != 0 && c.status != 1)
        throw new Exception(c.output);

    return c.status == 0;
}


/*******************************************************************************

    Returns:
        the currently checked out branch

*******************************************************************************/

string getCurrentBranch ( )
{
    import release.shellHelper;
    return cmd("git symbolic-ref --short HEAD");
}


/*******************************************************************************

    Params:
        upstream = upstream to use for getting the data

    Returns:
        The upstream remote name

*******************************************************************************/

string getRemote ( string upstream )
{
    import std.algorithm.iteration : splitter, uniq, map, filter;
    import std.algorithm.searching: canFind;
    import std.range;
    import std.conv;

    auto remotes = cmd("git remote -v")
                      .uniq()
                      .splitter!(a=>a == '\n')
                      .filter!(a=>a.canFind("github.com:" ~ upstream))
                      .map!(a=>a.splitter!(a=>a == ' ' || a == '\t').front);

    if (remotes.empty)
        throw new Exception("Can't find your upstream remote for %s",
                            upstream);

    return remotes.front.array.to!string;
}


/*******************************************************************************

    Returns:
        the configured neptune.upstream variable. If not found, asks the user to
        set it up.

*******************************************************************************/

string getUpstream ( )
{
    import std.exception;

    return cmd("git config neptune.upstream")
              .ifThrown(configureUpstream(askUpstreamName()));
}


/*******************************************************************************

    Params:
        path = config path to get

    Returns:
        requested config path valu

*******************************************************************************/

string getConfig ( string path )
{
    import std.format;
    return cmd(format("git config %s", path));
}


/*******************************************************************************

    Configures neptune upstream

    Params:
        upstream = desired upstream

    Returns:
        the new upstream

*******************************************************************************/

string configureUpstream ( string upstream )
{
    cmd("git config neptune.upstream " ~ upstream);

    return upstream;
}
