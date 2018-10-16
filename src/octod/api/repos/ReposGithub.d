/*******************************************************************************

    Library release tool.

    Copyright:
        Copyright (c) 2018 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module octod.api.repos.ReposGithub;

import octod.api.Repos;

/// Github specific implementation of Repository
class GithubRepo : Repository
{
    import octod.core;
    import vibe.data.json;
    import std.typecons;

    const Json json;

    /** C'tor

        Params:
            con = http connection
            json = initial json info

     **/
    public this ( HTTPConnection* con, const Json json )
    {
        this.json = json;

        super(con);
    }

    /**
        Returns:
            repository name
     **/
    public override string name ( )
    {
        return this.json["name"].get!string();
    }

    /**
        Returns:
            repository name
     **/
    public override string login ( )
    {
        return this.json["owner"]["login"].get!string();
    }

    /**
        Returns:
            programming language used for majority of repository files
     **/
    public override string language ( )
    {
        return this.json["language"].get!string();
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

        auto owner = this.json["owner"]["login"].get!string();
        auto name = this.name();

        auto url = format("/repos/%s/%s/branches", owner, name);
        auto json_branches = this.connection.get(url).get!(Json[]);

        GitRef toRef ( Json branch )
        {
           return GitRef(branch["name"].get!string,
                       branch["commit"]["sha"].to!string);
        }

        return json_branches.map!toRef.array;
    }

    /**
        Fetches repository tags filtered to only released ones

        This utility is useful for projects that strictly require all public
        releases to be actual GitHub releases, making possible to ignore any
        other tags that may exist in the project.

        There is a GitHub API to get both releases and tags, but former lacks
        SHA information and latter has no information about releases. This
        method makes request to both and merges information into one entity.

        Returns:
            array of gitref structs for all GitHub releases in this repo
     **/
    public override GitRef[] releasedTags ( )
    {
        import std.format;
        import std.array;
        import std.algorithm.iteration : map, filter;
        import std.algorithm.searching : find;

        auto owner = this.json["owner"]["login"].get!string();
        auto name = this.name();

        auto url = format("/repos/%s/%s/releases", owner, name);
        auto json_releases = this.connection.get(url).get!(Json[]);

        url = format("/repos/%s/%s/tags", owner, name);
        auto json_tags = this.connection.get(url).get!(Json[]);

        GitRef resolveTag ( Json release )
        {
            auto tag_name = release["tag_name"].get!string();
            auto tag = json_tags
                .find!(json => json["name"].get!string() == tag_name);
            if (tag.empty)
                return GitRef.init;
            else
                return GitRef(tag_name, tag.front["commit"]["sha"].to!string());
        }

        return json_releases
            .filter!(a => !a["draft"].get!bool)
            .map!resolveTag
            // refs that failed to resolve will have empty name:
            .filter!(gitref => gitref.name.length)
            .array();
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
    public override RepositoryEntity download ( string path, string gitref = "" )
    {
        import std.format;

        auto url = format(
            "/repos/%s/%s/contents/%s",
            this.json["owner"]["login"].get!string(),
            this.name(),
            path
        );

        if (gitref.length)
            url ~= "?ref=" ~ gitref;

        return RepositoryEntity(this.connection.get(url));
    }

    /***************************************************************************

        Lists the existing milestones

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

        auto owner = this.json["owner"]["login"].get!string();
        auto name = this.name();
        auto url = format("/repos/%s/%s/milestones?state=%s", owner, name, state);


        auto json = connection.get(url);

        Milestone[] mstones;

        foreach (milestone; json)
        {
            mstones ~= Milestone(milestone["id"].to!int,
                                 milestone["number"].to!int,
                                 milestone["title"].to!string,
                                 milestone["html_url"].to!string,
                                 milestone["state"].to!string.to!(Milestone.State),
                                 milestone["open_issues"].to!int,
                                 milestone["closed_issues"].to!int);
        }

        return mstones;
    }

    /***************************************************************************

        Creates a new release on github

        Params:
            connection = connection to use
            tag  = tag used for the release
            title = title for the release
            content = content of the release
            prerelease = true if this is a prerelease, else false

    ***************************************************************************/

    public override void createRelease ( ref HTTPConnection connection,
        string tag, string title, string content,
        Flag!"prerelease" prerelease = No.prerelease )
    {
        import std.format;
        import vibe.data.json;

        auto owner = this.json["owner"]["login"].get!string();
        auto name = this.name();

        Json json = Json.emptyObject;
        json["tag_name"] = tag;
        json["name"] = title;
        json["body"] = content;
        json["target_committish"] = tag;
        json["prerelease"] = prerelease == Yes.prerelease;

        auto url = format("/repos/%s/%s/releases", owner, name);

        connection.post(url, json);
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
        import std.conv;
        import vibe.data.json;

        auto owner = this.json["owner"]["login"].get!string();
        auto name = this.name();

        auto url = format("/repos/%s/%s/milestones/%s",
            owner, name, milestone.number);

        Json json_in = Json.emptyObject;

        json_in["state"] = state.to!string;

        connection.patch(url, json_in);
    }

    /**
        Makes an API request to resolve specified git reference name to
        its SHA hash in this repo.

        Params:
            refname = git ref (like tag or branch) name

        Returns:
            SHA of commit matching the reference
     **/
    protected string resolveGitReference ( string refname )
    {
        import std.format;
        import octod.media;

        auto owner = this.json["owner"]["login"].get!string();
        auto name = this.name();
        auto url = format("/repos/%s/%s/commits/%s", owner, name, refname);
        auto json = this.connection.get(url, MediaType.create("", "sha"));
        return json.get!string();
    }
}
