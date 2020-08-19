/*******************************************************************************

    Library release tool.

    Copyright:
        Copyright (c) 2018 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module provider.api.repos.ReposGitlab;

import provider.api.Repos;

/// Gitlab specific implementation of Repository
class GitlabRepo : Repository
{
    import provider.core;
    import vibe.data.json;
    import std.typecons;

    /// Full repository identifier
    protected string repo;

    /// Repo name & login
    protected string _name, _login;

    /** C'tor

        Params:
            con = http connection
            json = initial json info
            repo = repo name

     **/
    public this ( HTTPConnection* con, string repo )
    {
        import std.string : split;

        auto splitted = repo.split("/");

        this.repo = splitted[0] ~ "%2F" ~ splitted[1];

        this._login = splitted[0];
        this._name = splitted[1];

        super(con);
    }

    /**
        Returns:
            repository name
     **/
    public override string name ( )
    {
        return this._name;
    }

    /**
        Returns:
            login name
     **/
    public override string login ( )
    {
        return this._login;
    }

    /**
        Returns:
            programming language used for majority of repository files
     **/
    public override string language ( )
    {
        throw new Exception("not implemented");
    }

    /**
        Fetches all repository branches

        Returns:
            array of gitref structs for all GitHub branches in this repo
     **/
    public override GitRef[] branches ( )
    {
        import std.format;
        import std.algorithm;
        import std.range;

        import vibe.data.json;

        auto url = format("/projects/%s/repository/branches", this.repo);
        auto json_branches = this.connection.get(url).get!(Json[]);

        GitRef toRef ( Json branch )
        {
           return GitRef(branch["name"].get!string,
                       branch["commit"]["id"].to!string);
        }

        return json_branches.map!toRef.array;
    }

    /**
        Fetches repository tags filtered to only released ones

        This utility is useful for projects that strictly require all public
        releases to be actual GitLab releases, making possible to ignore any
        other tags that may exist in the project.

        Returns:
            array of gitref structs for all GitLab releases in this repo
     **/
    public override GitRef[] releasedTags ( )
    {
        import std.format;
        import std.range;
        import std.algorithm;

        import std.stdio;

        auto url = format("/projects/%s/repository/tags", this.repo);

        writefln(" Requesting: %s", url);
        auto tags = this.connection.get(url).get!(Json[]);


        return tags.filter!(a=>a["release"].type == Json.Type.Object)
            .map!(a=>GitRef(a["name"].get!string,
                                  a["target"].get!string))
            .array;
    }

    /**
        Provides access to repository content

        Params:
            path = relative path in the repository to request
            gitref = branch/tag to use. If empty, default branch will be used.

        Returns:
            information about found entity (file/directory/submodule/symlink)
            stored in a wrapper struct
     **/
    public override RepositoryEntity download ( string path, string gitref = "")
    {
        throw new Exception("not implemented");
    }

    /***************************************************************************

        Lists the existing milestones

        TODO: Fetch open and closed issues per milestone

        Params:
            connection = prepared github connection object
            state = requested state

        Returns:
            array of all milestones for this repository

    ***************************************************************************/

    public override Milestone[] listMilestones ( ref HTTPConnection connection,
        Milestone.State state = Milestone.State.all )
    {
        import std.format;
        import std.conv;
        import vibe.data.json;

        auto url = format("/projects/%s/milestones?state=%s", this.repo,
            this.convertState(state));

        auto json = connection.get(url);

        Milestone[] mstones;

        foreach (milestone; json)
        {
            mstones ~= Milestone(milestone["id"].to!int,
                                 milestone["iid"].to!int,
                                 milestone["title"].to!string,
                                 format("%s/%s/milestones/%s",
                                    connection.baseURL,
                                    this.repo,
                                    milestone["iid"].to!int),
                                 milestone["state"].to!string == "active" ?
                                    Milestone.State.open :
                                    Milestone.State.closed);
                                 //milestone["open_issues"].to!int,
                                 //milestone["closed_issues"].to!int);
        }

        return mstones;
    }

    /***************************************************************************

        Creates a new release on git*

        Params:
            connection = connection to use
            tag  = tag used for the release
            content = content of the release
            prerelease = true if this is a prerelease, else false

    ***************************************************************************/

    public override void createRelease ( ref HTTPConnection connection,
        string tag, string, string content,
        Flag!"prerelease" prerelease = No.prerelease )
    {
        import std.format;
        import std.conv;
        import vibe.data.json;

        auto url = format("/projects/%s/repository/tags/%s/release",
            this.repo, tag);

        auto json = Json.emptyObject;

        json["description"] = content;

        try connection.post(url, json);
        catch ( HTTPAPIException exc )
        {
            connection.put(url, json);
        }
    }

    /************************************************************************

        Updates a milestones state

        Params:
            connection = connection to use
            milestone  = milestone to update
            state      = desired state

    ***************************************************************************/

    public override void updateMilestoneState ( ref HTTPConnection connection,
        Milestone milestone, Repository.Milestone.State state )
    {
        import std.format;
        import vibe.data.json;

        auto url = format("/projects/%s/milestones/%s",
            this.repo, milestone.id);

        auto json = Json.emptyObject;

        auto fixed_state = this.convertState(state);

        if (fixed_state == "closed")
            fixed_state = "close";

        json["state_event"] = fixed_state;

        connection.put(url, json);
    }

    /**
        Fetches all repo issues description/metadata

        Params:
            state = only fetch issues with this state
     **/
    public override Issue[] listIssues ( Issue.State state = Issue.State.open )
    {
        import std.format;
        import std.algorithm.iteration : map;
        import std.array;

        auto url = format("/projects/%s/issues?state=%s", this.repo,
            this.convertState(state));

        return this.connection
            .get(url)
            .get!(Json[])
            .map!(element => Issue(this.connection, element,
                element["iid"].get!long,
                element["web_url"].get!string))
            .array();
    }

    /// Convert milestone state name to gitlab convention
    protected string convertState ( Milestone.State state )
    {
        import std.conv;
        return state == state.open ? "active" : state.to!string;
    }

    /// Convert issue state name to gitlab convention
    protected string convertState ( Issue.State state )
    {
        import std.conv;
        return state == state.open ? "opened" : state.to!string;
    }
}
