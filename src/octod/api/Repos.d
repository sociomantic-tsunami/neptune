/*******************************************************************************

    Provides wrappers on top of some methods documented in
    https://developer.github.com/v3/repos/

    Copyright: Copyright (c) 2016 dunnhumby Germany GmbH. All rights reserved

    License: Boost Software License Version 1.0 (see LICENSE for details)

*******************************************************************************/

module octod.api.Repos;

import vibe.data.json;
import octod.core;
import octod.media;
import octod.api.common;

/**
    Aggregate for git reference description

    There are quite some places in GitHub JSON responses where references are
    referred either by name or by sha exclusively. This API tries to provide
    both when feasible and wraps it with this struct.
 **/
struct GitRef
{
    string name;
    string sha;
}

/// Alias for old name of the struct
deprecated alias Tag = GitRef;

/**
    Wraps connection and repository metadata for simple shortcut access
    to repository related API methods. Arbitrary fields can be accessed
    via `json` getter.
 **/
class Repository
{
    import std.typecons;

    @disable this();

    protected
    {
        HTTPConnection* connection;

        this ( HTTPConnection* connection )
        {
            this.connection = connection;
        }
    }

    /// Milestone information
    struct Milestone
    {
        /// Milestone state
        enum State
        {
            open,
            closed,
            all,
        }

        /// Unique id of the milestone
        int id;

        /// Repo/Project internal number/id of the milestone
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

    /**
        Returns:
            repository name
     **/
    public abstract string name ( );

    /**
        Returns:
            owner login name
     **/
    public abstract string login ( );

    /**
        Returns:
            programming language used for majority of repository files
     **/
    public abstract string language ( );

    /**
        Fetches all repository branches

        Returns:
            array of gitref structs for all GitHub branches in this repo
     **/
    public abstract GitRef[] branches ( );

    /**
        Fetches repository tags filtered to only released ones

        Returns:
            array of gitref structs for all Git* releases in this repo
     **/
    public abstract GitRef[] releasedTags ( );

    /**
        Provides access to repository content

        Params:
            path = relative path in the repository to request
            gitref = branch/tag to use. If empty, default branch will be used.

        Returns:
            information about found entity (file/directory/submodule/symlink)
            stored in a wrapper struct
     **/
    public abstract RepositoryEntity download ( string path, string gitref = "");

    /***************************************************************************

        Lists the existing milestones

        Params:
            connection = prepared github connection object
            state = requested state

        Returns:
            array of all milestones for this repository

    ***************************************************************************/

    public abstract Milestone[] listMilestones ( ref HTTPConnection connection,
        Milestone.State state = Milestone.State.all );

    /***************************************************************************

        Creates a new release on git*

        Params:
            connection = connection to use
            tag  = tag used for the release
            title = title for the release
            content = content of the release
            prerelease = true if this is a prerelease, else false

    ***************************************************************************/

    public abstract void createRelease ( ref HTTPConnection connection,
        string tag, string title, string content,
        Flag!"prerelease" prerelease = No.prerelease );

    /***************************************************************************

        Updates a milestones state

        Params:
            connection = connection to use
            milestone  = milestone to update
            state      = desired state

    ***************************************************************************/

    public abstract void updateMilestoneState ( ref HTTPConnection connection,
        Milestone milestone, Repository.Milestone.State state );
}

/**
    Struct representing some entity stored in a git repository

    Exact kind of entity can be checked by calling `RepositoryEntity.kind`, and
    more strongly typed wrapper structs can be retrieved by
    `RepositoryEntity.expectXXX` methods.
 **/
struct RepositoryEntity
{
    /**
        Represents a file stored in the repository
     **/
    static struct File
    {
        const Json json;

        private this ( Json json )
        {
            this.json = json;
        }

        /**
            Returns:
                Decoded content of the file (if < 1Mb)
         **/
        immutable(void)[] content ( )
        {
            import std.exception : enforce;
            import std.base64;
            import std.range : join;
            import std.algorithm : splitter;

            enforce!HTTPAPIException(
                this.json["encoding"].get!string()== "base64");

            auto encoded = this.json["content"].get!string();
            // GitHub provides base64 with newlines injected to enable per-line
            // decoding, those have to be removed here
            return Base64.decode(encoded.splitter("\n").join(""));
        }
    }

    /**
        Represents a directory stored in the repository
     **/
    static struct Directory
    {
        const Json json;

        private this ( Json json )
        {
            this.json = json;
        }

        /**
            Returns:
                Array of paths for entities within this directory. Paths are
                relative to repository root.
         **/
        const(string)[] listAll ( )
        {
            import std.algorithm.iteration : map;
            import std.array;

            return this.json
                .get!(Json[])
                .map!(element => element["path"].get!string())
                .array();
        }
    }

    /**
        Represents a submodule linked from the repository
     **/
    static struct Submodule
    {
        const Json json;

        private this ( Json json )
        {
            this.json = json;
        }

        /**
            Returns:
                linked submodule hash
         **/
        string sha ( )
        {
            return this.json["sha"].get!string();
        }

        /**
            Returns:
                linked submodule git URL
         **/
        string url ( )
        {
            return this.json["submodule_git_url"].get!string();
        }
    }

    /**
        Raw entity metadata JSON

        See https://developer.github.com/v3/repos/contents/#get-contents for
        more details
     **/
    const Json json;

    /**
        Returns:
            typeid of whatever kind of entity stored metadata describes
     **/
    TypeInfo kind ( )
    {
        if (this.json.type() == Json.Type.Array)
            return typeid(RepositoryEntity.Directory);

        switch (this.json["type"].get!string())
        {
            case "file":
                return typeid(RepositoryEntity.File);
            case "submodule":
                return typeid(RepositoryEntity.Submodule);
            case "symlink":
            default:
                assert(false);
        }
    }

    /**
        Returns:
            current entity wrapped as RepositoryEntity.File

        Throws:
            HTTPAPIException on expectation violation
     **/
    File expectFile ( )
    {
        import std.exception : enforce;
        enforce!HTTPAPIException(this.kind == typeid(RepositoryEntity.File));
        return File(json);
    }

    /**
        Returns:
            current entity wrapped as RepositoryEntity.Directory

        Throws:
            HTTPAPIException on expectation violation
     **/
    Directory expectDirectory ( )
    {
        import std.exception : enforce;
        enforce!HTTPAPIException(this.kind == typeid(RepositoryEntity.Directory));
        return Directory(json);
    }

    /**
        Returns:
            current entity wrapped as RepositoryEntity.Submodule

        Throws:
            HTTPAPIException on expectation violation
     **/
    Submodule expectSubmodule ( )
    {
        import std.exception : enforce;
        enforce!HTTPAPIException(this.kind == typeid(RepositoryEntity.Submodule));
        return Submodule(json);
    }
}

/**
    Fetch specific repository metadata

    Params:
        connection = setup connection to API server
        repo = repository string of form "owner/repo", for example
            "sociomantic-tsunami/ocean"

    Returns:
        Wrapper struct to work with that repo embedding the json metadata
 **/
Repository repository ( ref HTTPConnection connection, string repo )
{
    import std.format;

    validateRepoString(repo);

    if (connection.isGithub())
        return newRepo(connection,
            connection.get(format("/repos/%s", repo)), repo);
    else
        return newRepo(connection, Json(), repo);
}

/**
    Lists all repos for given organization

    Params:
        connection = setup connection to API server
        name = organization name
        type = project filter to use, as defined by
            https://developer.github.com/v3/repos/#list-organization-repositories

    Returns:
        Array of json objects one per each repo
 **/
Repository[] listOrganizationRepos ( ref HTTPConnection connection, string name,
    string type = "sources" )
{
    import std.format;
    import std.exception : enforce;
    import std.algorithm : map, canFind;
    import std.array;

    enforce!APIException(
        canFind(["all", "public", "private", "forks", "sources", "member"], type),
        "Unknown repository filter type"
    );

    auto url = format("/orgs/%s/repos?type=%s", name, type);
    auto json = connection.get(url);

    return json
        .get!(Json[])
        .map!(elem => newRepo(connection, elem, "dummy/dum" /*TODO*/))
        .array();
}

/**
    Creates a new specialized class instance of Repository

    Params:
        connection = setup connection to API server
        json = json information about the repo
        repo = repo id ("user/repo")

    Returns:
        an instance of the Repository class
 **/
private Repository newRepo ( ref HTTPConnection con, Json json, string repo )
{
    import octod.api.repos.ReposGitlab;
    import octod.api.repos.ReposGithub;

    if (con.isGithub())
        return new GithubRepo(&con, json);
    else
        return new GitlabRepo(&con, repo);

    assert(false);
}

