/*******************************************************************************

    Main file for AutoPR

    Copyright:
        Copyright (c) 2018 sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module autopr.main;

import autopr.helper;
import autopr.yaml;
import autopr.SubModsUpdate;

import autopr.github;
import autopr.LibInfo;
import autopr.ForkInfo;
import autopr.MetaInfo;

import semver.Version;

import octod.core;

import vibe.data.json;

import std.datetime;
import std.format;

/// Query string part to fetch repo info for one orga
enum OrgaString = `
    %s: organization(login: "%s") {
    login
    repositories(first: 100%s) {
      pageInfo {
          hasNextPage
          endCursor
      }
      edges {
        node { ...repoData }
      }
    }
  }`;


/// Query string to fetch release, pr and neptune information
enum QueryStringReleasesPRsAndNeptune = `
{
  %(%s
  %)
  nodes(ids:%s) {
    id
    ... on Blob {
      text
    }
  }
}

fragment repoData on Repository %s
`;

/// Query string to fetch release and pr info
enum QueryStringReleasesPRs = `
{
  %(%s
  %)
}

fragment repoData on Repository %s
`;

/// Structure to format orga-query strings
struct OrgaFormat
{
    /// Orga name to format this instance for
    string orga;
    /// Cursor from which on to fetch further repositories
    string cursor;

    /// Returns formatted query string
    string toString ( ) const
    {
        import std.format;

        // We can't use '-' in aliases in graphQL so we replace them with '_'
        return format(OrgaString, this.aliased(), orga, cursor);
    }

    /// Returns graphql-alias friendly version of the orga name
    string aliased ( ) const
    {
        import std.string : translate;

        return translate(this.orga, ['-':'_']);
    }
}

/*******************************************************************************

    Main entry function

    Params:
        args = main program parameters

*******************************************************************************/

version(unittest) {} else
void main ( string[] args )
{
    import std.conv;
    import std.algorithm;
    import std.exception;
    import std.stdio;

    if (args.length < 3)
    {
        writefln("Usage: ./%s token org1 [org2...]\n\n", args[0]);
        throw new Exception("Unexpected amount of parameters");
    }

    import octod.core;

    // Prepare github credentials/connection
    Configuration cfg;
    cfg.dryRun = false;
    cfg.oauthToken = args[1];

    auto con = HTTPConnection.connect(cfg);

    auto orgas = args[2..$];

    // Fetch Meta & Fork info
    MetaInfo meta_info;
    ForkInfo fork_info;

    fetchMetaAndForkInfo(con, orgas, meta_info, fork_info);
    import std.range : array;
    auto orga_structs = orgas.map!(a=>OrgaFormat(a)).array;

    Json result = Json.emptyObject;
    bool more_pages;

    // Fetch releases, pull requests and neptune file contents
    do
    {
        writefln("Querying repos ... ");

        string query;

        // The first page queries the neptune node ids
        // all further querys don't need to do that again
        if (more_pages)
        {
            query = QueryStringReleasesPRs.format(
                orga_structs,
                RepositoryQueryString.format("last:100"));
        }
        else
        {
            query = QueryStringReleasesPRsAndNeptune.format(
                orga_structs,
                meta_info.meta_info
                    .byValue.map!(a=>a.neptune_id).filter!(a=>a.length > 0),
                RepositoryQueryString.format("last:100"));
        }

        more_pages = false;

        auto qresult = con.graphQL(query);

        scope(failure)
        {
            writefln("QUERY WAS: \n\n%s", query);
            writefln("RESP WAS: \n\n%s", qresult);
        }

        if ("errors" in qresult)
        {
            auto err = qresult["errors"];
            throw new Exception(err.get!string);
        }

        foreach (ref orga; orga_structs)
        {
            auto has_next_page =
                qresult["data"][orga.aliased]
                    .path!"repositories.pageInfo.hasNextPage".get!bool;

            // If there is more data to fetch, set the according endCursor
            // to continue where we left off
            if (has_next_page)
            {
                auto end_cursor =
                    qresult["data"][orga.aliased]
                        .path!"repositories.pageInfo.endCursor".get!string;

                orga.cursor = format(`, after: "%s"`, end_cursor);
                more_pages = true;
            }
        }

        // Merge the new data in the existing result
        mergeJson(qresult, result);
    }
    while (more_pages);

    // Extract & process the neptune file content
    meta_info.extractNeptuneYaml(result["data"]["nodes"]);

    // Extract & process any libraries
    LibInfo lib_info;
    lib_info.extractInfo(con, result, orgas, meta_info);

    // Find out which repos require updates
    SubModsUpdate[] updates;
    foreach (orga; orgas)
    {
        auto aliased = OrgaFormat(orga).aliased();
        auto repo_edges = result["data"][aliased]["repositories"]["edges"];

        updates ~= findUpdates(repo_edges, lib_info, meta_info);
    }

    string[string] pending_forks;

    // Create any forks we're missing
    foreach (update; updates)
    {
        auto fork = update.repo.toString() in fork_info.forks;

        if (fork is null && update.repo.toString() !in pending_forks)
        {
            writef("Creating fork for %s ...", update.repo);
            auto res = con.forkRepository(update.repo.owner, update.repo.name);
            pending_forks[update.repo.toString()] = res["name"].get!string;
            writefln(" %s/%s", fork_info.our_login, res["name"].get!string);
        }
    }

    // Make sure all forks are ready for use
    while (pending_forks.length > 0)
        foreach (orig, fork; pending_forks)
        {
            writef("Checking fork %s -> %s/%s ... ", orig, fork_info.our_login, fork);
            try con.getRepoCommits(fork_info.our_login, fork);
            catch (HTTPAPIException exc)
            {
                writefln("N/A");
                continue;
            }

            // Add to our fork map
            fork_info.forks[orig] = fork;
            pending_forks.remove(orig);
            writefln("Success");
        }

    // Create a PR for every update
    foreach (update; updates) try
    {
        if (update.repo.toString() !in fork_info.forks)
        {
            writefln("Skipping %s.%s which is not in our forks", update.repo,
                     update.updates);
            continue;
        }

        update.createOrUpdatePR(con, fork_info.our_login,
            fork_info.forks[update.repo.toString()]);
    }
    catch (Exception exc)
    {
        writefln("Failed to create pull request in %s for %s:\n%s", update.repo,
            update.updates, exc);
    }
}

/*******************************************************************************

    Fetches, processes and saves information about existing forks and generic
    metadata (default branch, latest commit sha, latest commits tree sha,
    github-id of neptune file)

    Params:
        con = github connection to use
        orgas = organisations to process
        meta_info = meta info object to be populated with data
        fork_info = fork info object to be populated with data

*******************************************************************************/

void fetchMetaAndForkInfo ( ref HTTPConnection con, string[] orgas,
    out MetaInfo meta_info, out ForkInfo fork_info )
{
    import std.algorithm : map;
    import std.range : array;
    import std.stdio;

    /// Query string used to fetch orga & fork info
    enum QueryStringMetaAndFork = `
    {
      %(%s
      %)
      %s
    }

    fragment repoData on Repository %s

    `;

    auto orgastr = orgas.map!(a=>OrgaFormat(a)).array;

    Json result;

    while(true)
    {
        auto query = QueryStringMetaAndFork.format(
            orgastr,
            ForkInfo.Query.format(fork_info.cursor),
            MetaInfo.Query);

        Json qresult;

        scope(failure)
        {
            writefln("QUERY WAS: \n\n%s", query);
            writefln("RESP WAS: \n\n%s", qresult);
        }

        writefln("Querying metadata ...");
        qresult = con.graphQL(query);

        if ("errors" in qresult)
        {
            auto err = qresult["errors"];
            throw new Exception(err.get!string);
        }

        if (!fork_info.extractInfo(qresult) &&
            !getMetaInfo(qresult, orgastr, meta_info))
            break;
    }

    writefln("Discovered forks: %s", fork_info.forks);
}

/***************************************************************************

    Extract & process meta data info (see autopr.MetaInfo) and populates the
    given meta_info object

    Params:
        result = json data to process
        orgas  = organisations that are involved
        meta_info = meta info object to populate

    Returns:
        true if there are more pages to fetch

***************************************************************************/

bool getMetaInfo ( Json result, OrgaFormat[] orgas, ref MetaInfo meta_info )
{
    bool more_pages = false;

    foreach (ref orga; orgas)
    {
        auto orga_json = result["data"][orga.aliased()];
        foreach (repo; orga_json.path!"repositories.edges")
        {
            meta_info.processEntry(repo["node"]);
        }

        if (orga_json.path!"repositories.pageInfo.hasNextPage".get!bool)
        {
            more_pages = true;

            orga.cursor = format(`, after: "%s"`,
                orga_json.path!"repositories.pageInfo.endCursor".get!string);
        }
    }

    return more_pages;
}

/*******************************************************************************

    Finds out if any repository requires a submodule update (according to their
    neptune file specifications).

    Params:
        repo_edges = all the repo edges to process
        lib_info   = library information object
        meta_info  = meta info object

    Returns:
        array of updates that will need to be done

*******************************************************************************/

auto findUpdates ( Json repo_edges, LibInfo lib_info, MetaInfo meta_info )
{
    import std.algorithm : find;
    import std.stdio;
    import std.format;

    SubModsUpdate[] updates;

    // Iterate over every repo/edge
    foreach (edge; repo_edges)
    {
        auto pull_requests = edge.path!"node.pullRequests.edges";
        auto repo = edge["node"]["name"].get!string;
        auto owner = edge["node"]["owner"]["login"].get!string;

        RequestLevel global = RequestLevel.Minor;
        RequestLevel[string] mods;

        auto owner_name = format("%s/%s", owner, repo);

        auto meta = owner_name in meta_info.meta_info;

        if (meta is null)
        {
            writefln("No meta info found for %s. Skipping.", owner_name);
            continue;
        }

        // Access neptune data
        if (!meta.neptune_yaml.isNull())
        {
            import autopr.yaml;

            auto res =
                getAutoPRSettings(meta.neptune_yaml);

            global = res.global;
            mods   = res.mods;
        }
        else
        {
            writefln("%s: No neptune data found, using defaults", owner_name);
        }

        processSubmodules(edge, lib_info, global, mods,
                          updates, *meta);
    }

    return updates;
}

/*******************************************************************************

    Analyse submodules and find out if they require an update

    Params:
        edge = json data of the repository to analyse
        lib_info = library information object
        global = the global library update request level
        mods   = the submodule specific update request levels
        updates = in/out param, will be populated with any updates we detect
        meta_info = meta information object

*******************************************************************************/

void processSubmodules ( Json edge, LibInfo lib_info, RequestLevel global,
    RequestLevel[string] mods,
    ref SubModsUpdate[] updates, MetaInfo.MetaInfo meta_info )
{
    import std.stdio : writefln;
    import std.algorithm : find;
    import std.range : empty, front;
    import std.string;
    import std.typecons;

    auto pull_requests = edge.path!"node.pullRequests.edges";
    auto repo = edge["node"]["name"].get!string;


    auto repoid = SubModsUpdate.NameWithOwner(repo, meta_info.owner);

    // Skip if that update exists already
    auto result = updates.find!(a=>a.repo == repoid);

    SubModsUpdate update;

    if (result.empty)
        update = SubModsUpdate(
        // Repo Name/Owner
        repoid,
        // Repos latest commit SHA
        meta_info.latest_commit_sha,
        // Repos latest commits tree SHA
        meta_info.latest_commit_tree_sha,
        // Repos default branch to create PR against
        meta_info.def_branch);
    else
        update = result.front;

    bool matchPrefix ( in Json a )
    {
        return a["node"]["title"]
            .get!string.startsWith(PRTitle);
    }

    // Find out if a PR already exists
    auto pr_exists = pull_requests.get!(Json[]).find!matchPrefix;

    // If it exists already, remember pr number
    if (!pr_exists.empty)
    {
        update.pr_number = pr_exists.front["node"]["number"].get!int;

        auto pr_commits = pr_exists.front["node"]["commits"]["edges"].get!(Json[]);

        foreach (commit; pr_commits) try
        {
            import std.algorithm : countUntil;

            auto msg = commit["node"]["commit"]["messageHeadline"].get!string;

            // Headline looks like "Advance %s from %s to %s"

            if (msg.length < "Advance".length)
                continue;

            // First skip "Advance "
            msg = msg["Advance ".length .. $];

            // Now, find " from "
            auto idx_name_end = msg.countUntil(" from ");

            if (idx_name_end == -1)
                continue;

            // Extract submodule name
            auto subname = msg[0 .. idx_name_end];

            // Find beginning of current version
            auto idx_cur_ver_start = idx_name_end + " from ".length;

            if (idx_cur_ver_start == -1)
                continue;

            // Skip ahead to beginning
            msg = msg[idx_cur_ver_start .. $];

            // Find " to "
            auto idx_cur_ver_end = msg.countUntil(" to ");

            if (idx_cur_ver_end == -1)
                continue;

            // Parse current version
            auto cur_ver = Version.parse(msg[0 .. idx_cur_ver_end]);

            auto idx_target_ver_start = idx_cur_ver_end + " to ".length;

            // Parse target version
            auto target_ver = Version.parse(msg[idx_target_ver_start .. $]);

            /// Add existing version to existing updates
            update.existing_updates ~= SubModsUpdate.SubModUpdate(
                SubModsUpdate.NameWithOwner(subname, ""),
                SubModsUpdate.SubModVer("", cur_ver),
                SubModsUpdate.SubModVer("", target_ver));
        }
        catch (Exception exc)
        {
            writefln("Skipping existing update: %s", exc.msg);
        }
    }
    else
        writefln("%s> No PR found!", repoid);

    // Iterate over all submodules
    foreach (name, sha; meta_info.submodules)
    {
        // Check if is a library
        auto lib = name in lib_info.libs;

        if (lib is null)
        {
            // Ignore submodules we don't know about
            continue;
        }

        // Find what version is currently in the repo
        auto cur_ver = (*lib).find!(a=>a.sha == sha);

        import std.range;

        if (cur_ver.empty)
        {
            writefln("%s> version %s of %s not found", repoid, sha, name);

            continue;
        }

        bool matchRequestLevel ( LibInfo.Release rel )
        {
            RequestLevel level;

            if (!rel.supported)
                return false;

             auto mod = name in mods;

            if (mod is null)
                level = global;
            else
                level = *mod;

            with(cur_ver.front)
            with(RequestLevel)
            final switch (level)
            {
                case None:
                    return false;
                case Patch:
                    return rel.ver.major == ver.major &&
                        rel.ver.minor == ver.minor;
                case Minor:
                    return rel.ver.major == ver.major;
                case Major:
                    return true;
            }
        }

        // Find out what version we want to update to
        auto latest = (*lib).retro.find!matchRequestLevel;

        if (latest.empty || latest.front.ver <= cur_ver.front.ver)
            continue;


        import vibe.data.json;
        import std.typecons : Nullable;

        import std.algorithm : canFind;

        auto submodule = SubModsUpdate.NameWithOwner(name, latest.front.owner);

        if (update.updates.canFind!(a=>a.repo == submodule))
            continue;

        update.updates ~= SubModsUpdate.SubModUpdate(
            // Submod Name/Owner
            submodule,
            // Current Submod sha/version
            SubModsUpdate.SubModVer(sha, cur_ver.front.ver),
            // new submod sha/version
            SubModsUpdate.SubModVer(latest.front.sha, latest.front.ver));
    }

    if (update.updates.length == 0)
        return;

    // Compare the existing updates with the upcoming updates
    if (update.updates.length == update.existing_updates.length)
    {
        int matching = 0;

        foreach (upd; update.updates)
        foreach (xupd; update.existing_updates)
        {
            if (upd.repo.name == xupd.repo.name &&
                upd.cur.ver == xupd.cur.ver &&
                upd.target.ver == xupd.target.ver)
            {
                matching++;
            }
        }

        // If they are the same, we don't need to update this
        if (matching == update.updates.length)
        {
            writefln("%s> Skipping existing PR", repoid);
            return;
        }
    }

    // Add the new or updated update struct
    if (result.empty)
        updates ~= update;
    else
        result.front = update;
}
