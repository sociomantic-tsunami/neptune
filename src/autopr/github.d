/*******************************************************************************

    Varios functions to interact with github

    Copyright:
        Copyright (c) 2018 sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module autopr.github;

import octod.api.repos;
import octod.core;

import vibe.data.json;

/// Enum of possible file types when creating a Tree object
enum Type
{
    Blob = "100644",
    Executable = "100755",
    Folder = "040000",
    Submodule = "160000",
    Symlink = "120000",
}


/// Query to fetch PRs & releases
enum RepositoryQueryString = `
{
  name
  owner { login }
  releases(%s) {
    pageInfo {
      hasPreviousPage
      startCursor
    }
    edges {
      node {
        publishedAt
        tag {
          name
          target {
           ... on Tag {
               target {
                   oid
               }
            }
          }
        }
      }
    }
  }
  pullRequests(last:100, states:[OPEN]) {
      edges {
          node {
              number
              headRefName
              title
          }
      }
  }
}
`;

/// Collects requests to fetch more info and eventually fetches them in batches
struct FetchMore
{
    import vibe.data.json;

    /// Type of fetch to do (only Release supported currently)
    enum Type
    {
        Release,
        Repository,
        PullRequest,
    }

    /// Format-ready string to build query
    enum FetchQueryString = `
{
  %(%s
  %)
}`;

    /// One single request to fetch more releases
    struct ReleaseRequest
    {
        /// Repository for which to fetch more releases
        string repo;
        /// Starting Cursor from which to fetch more releases of
        string cursor;
        /// Owner/orga of the repository
        string orga;

        /// Flag to remember if this repo has already been fetched
        bool fetched;

        /// Formats the release request into a query
        string toString ( ) const
        {
            import std.format;

            return format(`repo_%s: repository(name: "%s", owner:"%s") %s`,
                this.repo, this.repo, this.orga,
                RepositoryQueryString
                    .format(`last:100, before:"%s"`.format(this.cursor)));
        }
    }

    /// List of release fetch requests
    ReleaseRequest[] release_requests;

    /// Returns true if we have not-yet-fetched release requests
    bool hasRequests ( ) const
    {
        import std.algorithm : canFind;
        return this.release_requests.canFind!(a=>!a.fetched);
    }

    /***************************************************************************

        Adds a new release fetch request

        Params:
            repository = repository to add this request for
            cursor = current cursor position
            orga = owner/orga of this repository

    ***************************************************************************/

    void addReleaseRequest ( string repository, string cursor, string orga )
    {
        import std.algorithm : canFind;
        import std.exception: enforce;

        enforce(!this.release_requests.canFind!(a=>a.repo == repository));
        this.release_requests ~= ReleaseRequest(repository, cursor, orga);
    }

    /***************************************************************************

        Fetches the accumulated requests

        Params:
            con = connection to use
            json = json object to amend/merge the new data into
            orgas = list of organisations to fetch data for

        Returns:
            false if no requests are pending, else true

    ***************************************************************************/

    bool fetch ( ref HTTPConnection con, ref Json json, string[] orgas )
    {
        import std.format;
        import std.stdio;
        import std.algorithm;
        import std.range;
        import vibe.data.json;

        if (!this.hasRequests())
            return false;

        auto query =
            FetchQueryString.format(this.release_requests.filter!(a=>!a.fetched));

        writefln("Query: %s", query);

        auto result = graphQL(con, query);

        writefln("RESULT: %s", result);

        auto edges = json["data"]["organization"]["repositories"]["edges"];

        // Merge results into existing json
        foreach (keyval; result["data"].byKeyValue)
        {
            if (keyval.value.type != Json.Type.object)
                continue;

            writefln("Iterating over: %s -> %s", keyval.key,
                     keyval.value["name"]);

            // Finding current repo in original json obj
            auto rep = edges.get!(Json[])
                .find!(a=>"name" in a["node"] &&
                    a["node"]["name"] == keyval.value["name"]);

            if (rep.empty)
            {
                writefln("Couldn't find %s, in %s adding new",
                    keyval.value["name"],
                    edges.get!(Json[]).map!(a=>a["node"].byKeyValue.map!(b=>b.key)));

                auto node = Json.emptyObject;
                node["node"] = keyval.value;
                edges ~= node;
            }
            else
            {
                writefln("found %s, merging", keyval.value["name"]);
                mergeJson(keyval.value, rep.front["node"]);
            }
        }

        foreach (ref rr; this.release_requests)
            rr.fetched = true;

        return true;
    }
}


/*******************************************************************************

    Merge two identically structured json objects

    Params:
        from = json object to merge
        to   = json object to merge into
        overwrite_existing = if true, prefers the new value when there are
                             conflicts

*******************************************************************************/

void mergeJson ( Json from, ref Json to, bool overwrite_existing = true )
{
    import std.range;
    import std.algorithm;
    import std.typecons;

    foreach (from_el; from.byKeyValue())
    {
        if (from_el.key !in to)
            // Insert
            to[from_el.key] = from_el.value.clone;
        else
        {
            // Append
            if (to[from_el.key].type == Json.Type.array)
                to[from_el.key] ~= from_el.value.clone;
            // Recursive merge
            else if (to[from_el.key].type == Json.Type.object)
                mergeJson(from_el.value, to[from_el.key], overwrite_existing);
            // Overwrite
            else if (overwrite_existing)
                to[from_el.key] = from_el.value.clone;
        }
    }
}

unittest
{
    auto a = Json.emptyObject;
    auto b = Json.emptyObject;

    a["num1"] = 1;
    a["array"] = Json.emptyArray;
    a["array"] ~= Json(1);
    a["object"] = Json.emptyObject;
    a["object"]["num2"] = 2;
    a["object"]["num1"] = 2; // Will overwrite
    a["object"]["array"] = Json.emptyArray;
    a["object"]["array"] ~= Json(10);

    b["num2"] = 2;
    b["num3"] = 3;
    b["array"] = Json.emptyArray;
    b["array"] ~= Json(2);
    b["object"] = Json.emptyObject;
    b["object"]["num1"] = 1; // will be overwriten
    b["object"]["array"] = Json.emptyArray;
    b["object"]["array"] ~= Json(2);

    mergeJson(a, b);

    assert(b["array"].length == 2);
    assert(b["array"][0] == 2);
    assert(b["array"][1] == 1);
    assert("num1" in b);
    assert(b["num2"].get!int == 2);
    assert("num2" in b, "Num 2 is missing");
    assert("num3" in b);
    assert(b["object"]["num1"] == 2);
    assert(b["object"]["num2"] == 2);
    assert(b["object"]["array"].length == 2);
    assert(b["object"]["array"][0] == 2);
    assert(b["object"]["array"][1] == 10);
}


/*******************************************************************************

    Perform a graph QL query

    Params:
        connection = connection to use
        query      = query

    Returns:
        query result

*******************************************************************************/

auto graphQL ( ref HTTPConnection con, string query )
{
    import vibe.data.json;
    import octod.media;

    Json data = Json.emptyObject;

    data["query"] = query;

    return con.post("/graphql", data, MediaType.Default);
}


/*******************************************************************************

    Creates a tree object in the given repository with a given path updated.

    Params:
        con = connection to github
        owner = owner of the repository
        repo = name of the repository
        base = sha of the base tree (e.g. found in a previous commit)
        path = path to the file to update
        sha_or_content = sha or content of the file. If file type is submodule
            or Folder this will be interpreted as SHA, otherwise as content
        file_type = type of the file to create/update.

    Returns:
        resulting tree object

*******************************************************************************/

auto createTree ( ref HTTPConnection con, string owner, string repo,
    string base, string path, string sha_or_content, Type file_type )
{
    import std.format;
    import octod.core;
    import octod.media;

    Json request = Json.emptyObject;

    string type;
    string sha_or_content_key;

    with (Type) final switch (file_type)
    {
        case Blob: goto case;
        case Executable: goto case;
        case Symlink:
            type = "blob";
            sha_or_content_key = "content";
            break;

        case Folder:
            type = "tree";
            sha_or_content_key = "sha";
            break;

        case Submodule:
            type = "commit";
            sha_or_content_key = "sha";
            break;
    }

    request["base_tree"] = base;
    request["tree"] = Json.emptyArray;

    Json tree_obj = Json.emptyObject;

    tree_obj["type"] = type;
    tree_obj["mode"] = file_type;
    tree_obj["path"] = path;
    tree_obj[sha_or_content_key] = sha_or_content;

    request["tree"] ~= tree_obj;

    return con.post(format("/repos/%s/%s/git/trees", owner, repo),
        request, MediaType.Default);
}


/*******************************************************************************

    Creates a new commit

    Params:
        con = connection to use
        owner = repository owner
        repo = repository name
        parent = commit parent SHA
        tree = file tree SHA
        msg = commit message

    Returns:
        github server response json

*******************************************************************************/

auto createCommit ( ref HTTPConnection con, string owner, string repo,
    string parent, string tree, string msg )
{
    import std.format;
    import octod.core;
    import octod.media;

    Json request = Json.emptyObject;

    request["parents"] = Json.emptyArray;
    request["parents"] ~= parent;
    request["tree"] = tree;
    request["message"] = msg;

    return con.post(format("/repos/%s/%s/git/commits", owner, repo),
        request, MediaType.Default);
}


/*******************************************************************************

    Creates a new reference (tag/branch)

    Params:
        con = connection to use
        owner = repository owner
        repo = repository name
        ref_name = name of the reference
        sha = sha of the commit the reference should point at

    Returns:
        github server response json

*******************************************************************************/

auto createReference ( ref HTTPConnection con, string owner, string repo,
    string ref_name, string sha )
{
    import std.format;
    import octod.core;
    import octod.media;

    Json request = Json.emptyObject;

    request["ref"] = ref_name;
    request["sha"] = sha;

    return con.post(format("/repos/%s/%s/git/refs", owner, repo),
        request, MediaType.Default);
}


/*******************************************************************************

    Updates an existing reference

    Params:
        con = connection to use
        owner = repository owner
        repo = repository name
        ref_name = name of the reference to update
        sha = new SHA commit to point to
        force = force update, even if not a fast-forward update

    Returns:
        github server json response

*******************************************************************************/

auto updateReference ( ref HTTPConnection con, string owner, string repo,
    string ref_name, string sha, bool force = true )
{
    import std.format;
    import octod.core;
    import octod.media;

    Json request = Json.emptyObject;

    request["force"] = force;
    request["sha"] = sha;

    return con.patch(format("/repos/%s/%s/git/%s", owner, repo, ref_name),
        request, MediaType.Default);
}


/*******************************************************************************

    Creates a new pull request

    Params:
        con = connection object to use
        owner = owner of the target repository
        repo = name of the target repository
        title = title of the PR
        content = content/msg of the PR
        fork = name of the repository to create the PR from
        branch = name of the branch to create the PR to
        fork_branch = name of the branch to create the PR from

    Returns:
        github server response json

*******************************************************************************/

auto createPullrequest ( ref HTTPConnection con, string owner, string repo,
    string title, string content, string fork, string branch, string fork_branch )
{
    import std.format;
    import octod.core;
    import octod.media;

    Json request = Json.emptyObject;

    request["title"] = title;
    request["head"] = format("%s:%s", fork, fork_branch);
    request["base"] = branch;
    request["body"] = content;
    request["maintainer_can_modify"] = true;

    return con.post(format("/repos/%s/%s/pulls", owner, repo), request,
                    MediaType.Default);
}


/*******************************************************************************

    Update an existing PR

    Params:
        con = connection object
        owner = owner of the repository
        repo = name of the repository
        number = number of the PR (not the internal ID)
        title = new title of the PR
        content = new content of the PR

    Returns:
        github server json response

*******************************************************************************/

auto updatePullrequest ( ref HTTPConnection con, string owner, string repo,
    int number, string title, string content )
{
    import std.format;
    import octod.core;
    import octod.media;

    Json request = Json.emptyObject;

    request["title"] = title;
    request["body"] = content;

    return con.patch(format("/repos/%s/%s/pulls/%s", owner, repo, number),
                     request, MediaType.Default);
}


/*******************************************************************************

    Fork a repository

    Params:
        con = connection to use
        owner = owner of the repository
        repo = name of the repository

    Returns:
        github json response

*******************************************************************************/

auto forkRepository ( ref HTTPConnection con, string owner, string repo )
{
    import std.format;
    import octod.media;

    return con.post(format("/repos/%s/%s/forks", owner, repo), Json.emptyObject,
        MediaType.Default);
}


/*******************************************************************************

    Fetches the commits of a repository, can also be used to check if a fork is
    complete

    Params:
        con = connection object to use
        owner = owner of the repository
        repo = name of the repository

    Returns:
        github json response

*******************************************************************************/

auto getRepoCommits ( ref HTTPConnection con, string owner, string repo )
{
    import std.format;
    import octod.media;

    return con.get(format("/repos/%s/%s/commits", owner, repo), MediaType.Default);
}


/*******************************************************************************

    Adds a comment to a PR or issue

    Params:
        con = connection object ot use
        id = id (internal id!) of the PR or issue
        content = content of the comment

    Response:
        github json response

*******************************************************************************/

void addComment ( ref HTTPConnection con, string id, string content )
{
    import std.format;

    auto query = format(`mutation {
        addComment(input:{subjectId:"%s", body:"%s"}) {
            clientMutationId
            }
    }`, id, content);

    con.graphQL(query);
}
