/*******************************************************************************

    Github interaction helpers

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.github;

import release.api;
import octod.api.repos;

/// Structure defining a name-tag association
struct Head
{
    string name;
    string sha;
}

/*******************************************************************************

    Params:
        repo = repository object

    Returns:
        all branches for this repository

*******************************************************************************/

public Head[] getBranches ( ref Repository repo )
{
    import std.format;
    import std.algorithm;
    import std.range;

    import vibe.data.json;

    auto owner = repo.json["owner"]["login"].get!string();
    auto name = repo.name();

    auto url = format("/repos/%s/%s/branches", owner, name);
    auto json_branches = api.get(url).get!(Json[]);

    Head toHead ( Json branch )
    {
       return Head(branch["name"].get!string,
                   branch["commit"]["sha"].to!string);
    }

    return json_branches.map!toHead.array;
}
