/*******************************************************************************

    Varios functions to interact with githubs graphql api

    Copyright:
        Copyright (c) 2018 sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module internal.github.graphql;

import octod.api.repos;
import octod.core;

import vibe.data.json;

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
