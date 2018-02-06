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
    import autopr.helper : path;
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
        }
      }
    }
  }`;

    /// Our github login name
    string our_login;

    /// Key: upstream owner/name, value: downstream name
    string[string] forks;

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
            auto downstream = edge["node"]["name"].get!string;
            auto upstream   = edge["node"]["parent"]["nameWithOwner"].get!string;

            this.forks[upstream] = downstream;
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
