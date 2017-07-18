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
import octod.core;

/// Structure defining a name-tag association
struct Head
{
    string name;
    string sha;
}

/*******************************************************************************

    Params:
        connection = connection to use
        repo = repository object

    Returns:
        all branches for this repository

*******************************************************************************/

public Head[] getBranches ( ref HTTPConnection connection, ref Repository repo )
{
    import std.format;
    import std.algorithm;
    import std.range;

    import vibe.data.json;

    auto owner = repo.json["owner"]["login"].get!string();
    auto name = repo.name();

    auto url = format("/repos/%s/%s/branches", owner, name);
    auto json_branches = connection.get(url).get!(Json[]);

    Head toHead ( Json branch )
    {
       return Head(branch["name"].get!string,
                   branch["commit"]["sha"].to!string);
    }

    return json_branches.map!toHead.array;
}

/*******************************************************************************

    Creates a new release on github

    Params:
        connection = connection to use
        repo = repository object
        tag  = tag used for the release
        title = title for the release
        content = content of the release

*******************************************************************************/

public void createRelease ( ref HTTPConnection connection, ref Repository repo,
                            string tag, string title, string content )
{
    import std.format;
    import vibe.data.json;

    auto owner = repo.json["owner"]["login"].get!string();
    auto name = repo.name();

    Json json = Json.emptyObject;
    json["tag_name"] = tag;
    json["name"] = title;
    json["body"] = content;
    json["target_committish"] = tag;

    auto url = format("/repos/%s/%s/releases", owner, name);

    connection.post(url, json);
}
