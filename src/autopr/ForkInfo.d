/*******************************************************************************

    Structure to handle fork information

    Copyright:
        Copyright (c) 2018 sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module autopr.ForkInfo;

/// Extracts and saves information about forks
struct ForkInfo
{
    import autopr.SubModsUpdate;
    import internal.json;
    import octod.core;
    import vibe.data.json;

    /// GraphQL query to fetch the fork information
    enum Query = `
viewer {
    login
    repositories(first:100, isFork: true%s) {
      pageInfo {
          hasNextPage
          endCursor
      }
      edges {
          node {
              name
              parent { nameWithOwner }
              all: ref(qualifiedName:"`~PRRefNames[0]~`") { ...prData }
              rcs: ref(qualifiedName:"`~PRRefNames[1]~`") { ...prData }
              norcs: ref(qualifiedName:"`~PRRefNames[2]~`") { ...prData }
        }
      }
    }
}`;

    enum QueryFragment = `fragment prData on Ref
{
    associatedPullRequests(first: 1, states:[OPEN]) {
        nodes {
            number
            headRefName
            title
            commits(first:100) {
                edges {
                    node {
                        commit {
                            messageHeadline
                        }
                    }
                }
            }
        }
    }
}`;

    /// Holds PR information
    struct PullRequest
    {
        int number;
        string refname;
        string title;
        string[] commits;
    }

    /// Holds fork information
    struct Fork
    {
        /// Full upstream path (owner/repo)
        string upstream;
        /// Only repo name (repo)
        string downstream_name;

        PullRequest[] pull_requests;
    }


    /// Our github login name
    string our_login;

    /// Key: upstream owner/name, value: downstream name
    Fork[string] forks;

    /// If we need to fetch more than 100, contains the cursor from which on to
    /// fetch more
    string cursor;

    /***************************************************************************

        Extracts the fork and login information from a fetched query.
        If more pages exist, the cursor member will be set accordingly.

        Params:
            json = json query result

        Returns:
            true  if more pages exist, else false

    ***************************************************************************/

    bool extractInfo ( Json json )
    {
        import std.format;

        this.our_login = json["data"]["viewer"]["login"].get!string;

        auto edges = json.path!"data.viewer.repositories.edges";

        foreach (edge; edges)
        {
            Fork fork;

            auto node = edge["node"];

            fork.downstream_name = node["name"].get!string;
            fork.upstream        = node["parent"]["nameWithOwner"].get!string;

            void parsePRs ( Json prnode )
            {
                if (prnode.type() == Json.Type.null_)
                    return;

                auto prs = prnode["associatedPullRequests"]["nodes"].get!(Json[]);

                if (prs.length == 0)
                    return;

                auto pr = prs[0];

                PullRequest pull_req;

                pull_req.number  = pr["number"].get!int;
                pull_req.refname = pr["headRefName"].get!string;
                pull_req.title   = pr["title"].get!string;

                foreach (commit; pr["commits"]["edges"])
                    pull_req.commits ~=
                        commit.path!"node.commit.messageHeadline".get!string;

                fork.pull_requests ~= pull_req;
            }

            parsePRs(node["all"]);
            parsePRs(node["rcs"]);
            parsePRs(node["norcs"]);

            this.forks[fork.upstream] = fork;
        }

        if (json.path!"data.viewer.repositories.pageInfo.hasNextPage".get!bool)
        {
            cursor = format(`, after:"%s"`,
                json.path!"data.viewer.repositories.endCursor".get!string);
            return true;
        }


        return false;
    }
}
