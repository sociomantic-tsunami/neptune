/*******************************************************************************

    Main file for AutoPR

    Copyright:
        Copyright (c) 2018 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module data_flow_mapper.main;

import data_flow_mapper.options;

import internal.json;
import internal.github.MetaInfo;
import internal.github.graphql;

import semver.Version;

import provider.core;

import vibe.data.json;

import std.datetime;
import std.format;

/// Query string part to fetch repo info for one orga
enum OrgaString = `
    %s: organization(login: "%s") {
    login
    repositories(first: %s%s) {
      pageInfo {
          hasNextPage
          endCursor
      }
      edges {
        node { ...repoData }
      }
    }
  }`;

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
        return format(OrgaString, this.aliased(), orga, options.num_entries, cursor);
    }

    /// Returns graphql-alias friendly version of the orga name
    string aliased ( ) const
    {
        import std.string : translate;

        return translate(this.orga, ['-':'_']);
    }
}


class DFMMetaInfo : MetaInfo
{
    string[string] readme_ids;

    override public void processEntry ( Json json )
    {
        super.processEntry(json);

        if (json["defaultBranchRef"].type == Json.Type.null_)
            return;

        auto root = json.path!"defaultBranchRef.target.tree.entries";

        auto key = format("%s/%s",
            json["owner"]["login"].get!string,
            json["name"].get!string);

        foreach (entry; root)
        {
            if (entry["name"] == "README.rst")
            {
                this.readme_ids[key] = entry["object"]["id"].get!string;
                return;
            }
        }
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

    parseOpts(args);

    if (options.quit)
        return;

    import provider.core;

    // Prepare github credentials/connection
    Configuration cfg;
    cfg.dryRun = false;
    cfg.oauthToken = options.key;

    auto con = HTTPConnection.connect(cfg);

    auto orgas = options.orgas;

    // Fetch Meta info
    auto meta_info = new DFMMetaInfo();

    fetchMetaInfo(con, orgas, meta_info);
    import std.range : array, chain, chunks;

    auto nodes = chain(
        meta_info.meta_info
            .byValue.map!(a=>a.neptune_id).filter!(a=>a.length > 0),
        meta_info.readme_ids.byValue);


    Json result = Json.emptyObject;

    foreach (chunk; chunks(nodes, options.num_entries))
    {
        string query = "{ %s }".format(MetaInfo.NodeQuery.format(
            chunk));
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

        mergeJson(qresult, result);
    }

    // Extract & process the neptune file content
    meta_info.extractNeptuneYaml(result["data"]["nodes"]);

    import data_flow_mapper.DotNodes;

    Channel[] channels;
    Connection[] connections;
    App[] apps;

    foreach (repo, mi; meta_info.meta_info)
    {
        if (!mi.neptune_yaml.isNull)
        {
            writefln("Parsing %s yml", repo);
            parseFromYML(mi.neptune_yaml.get, channels, connections, apps);
        }
        //writefln("%s: \n%s\n----", repo, mi.neptune_yaml.get);
    }

    enum FileName = "dataflow.gv";
    writefln("Writing graph file: %s", FileName);

    auto file = File(FileName, "w");

    render(file, channels, connections, apps);

    /*foreach (repo, file_id; meta_info.readme_ids)
        foreach (file; result["data"]["nodes"])
            if (file_id == file["id"].get!string)
            {
                writefln("%s README:\n%s\n----------\n", repo,
                         file["text"].get!string.find("Data Flow"));
            }*/

}


/*******************************************************************************

    Fetches, processes and saves information about generic metadata (default
    branch, latest commit sha, latest commits tree sha, github-id of neptune
    file)

    Params:
        con = github connection to use
        orgas = organisations to process
        meta_info = meta info object to be populated with data

*******************************************************************************/

void fetchMetaInfo ( ref HTTPConnection con, string[] orgas,
    MetaInfo meta_info )
{
    import std.algorithm : map;
    import std.range : array;
    import std.stdio;

    /// Query string used to fetch orga & fork info
    enum QueryStringMeta = `
    {
      %(%s
      %)
    }

    fragment repoData on Repository %s
    `;

    auto orgastr = orgas.map!(a=>OrgaFormat(a)).array;

    Json result;

    while(true)
    {
        auto query = QueryStringMeta.format(
            orgastr, MetaInfo.Query);

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

        if (!processMetaInfo(qresult, orgastr, meta_info))
            break;
    }
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

bool processMetaInfo ( Json result, OrgaFormat[] orgas, MetaInfo meta_info )
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
