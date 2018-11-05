/*******************************************************************************

    Github interaction helpers

    Copyright:
        Copyright (c) 2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.github;

import internal.github.GithubConfig;
import octod.api.repos;
import octod.core;

enum State
{
    open,
    closed,
    all,
}


/// Milestone information
struct Milestone
{
    /// Unique id of the milestone
    int id;

    /// Number of the milestone
    int number;

    /// Title of the milestone
    string title;
    /// URL of the milestone
    string url;
    /// State of the milestone
    State state;

    /// Amount of open issues
    int open_issues;
    /// Amount of closed isues
    int closed_issues;
}

/*******************************************************************************

    Lists the existing milestones

    Params:
        connection = prepared github connection object
        repo = initilized repo object
        state = requested state

    Returns:
        array of all milestones for this repository

*******************************************************************************/

Milestone[] listMilestones ( ref HTTPConnection connection, ref Repository repo,
                             State state = State.all )
{
    import std.format;
    import std.conv;
    import vibe.data.json;

    auto owner = repo.json["owner"]["login"].get!string();
    auto name = repo.name();
    auto url = format("/repos/%s/%s/milestones?state=%s", owner, name, state);


    auto json = connection.get(url);

    Milestone[] mstones;

    foreach (milestone; json)
    {
        mstones ~= Milestone(milestone["id"].to!int,
                             milestone["number"].to!int,
                             milestone["title"].to!string,
                             milestone["html_url"].to!string,
                             milestone["state"].to!string.to!(State),
                             milestone["open_issues"].to!int,
                             milestone["closed_issues"].to!int);
    }

    return mstones;
}


/*******************************************************************************

    Updates a milestones state

    Params:
        connection = connection to use
        repo       = repo of the milestone
        number     = number of the milestone
        state      = desired state

*******************************************************************************/

void updateMilestoneState ( ref HTTPConnection connection, ref Repository repo,
                            int number, State state )
{
    import std.format;
    import std.conv;
    import vibe.data.json;

    auto owner = repo.json["owner"]["login"].get!string();
    auto name = repo.name();

    auto url = format("/repos/%s/%s/milestones/%s", owner, name, number);

    Json json_in = Json.emptyObject;

    json_in["state"] = state.to!string;

    connection.patch(url, json_in);
}
