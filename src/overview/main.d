/*******************************************************************************

    Project overview generator tool.

    Uses GitHub API to fetch various information about repositories in one
    GitHub organization and relation between them. That information can be
    used to generate reports and notifications.

    Copyright:
        Copyright (c) 2009-2016 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module overview.main;

import octod.core;
import octod.api.repos;
import overview.repository;
import overview.config;

/// ditto
version(UnitTest) {} else
void main ( )
{
    import overview.htmlreport;
    import semver.Version;
    import vibe.core.log : logInfo;
    import std.algorithm.iteration : map, filter, each;
    import std.range : tee;
    import std.array;

    auto conf = readConfigFile("overview.yml");
    auto client = HTTPConnection.connect(conf.octod);

    logInfo("Fetching repository list");
    auto repos = client.fetchAllProjects(conf.organization, conf.excludedRepos,
        conf.includedRepos);

    logInfo("Aggregating initial repository metadata");
    auto projects = repos
        .map!(name => client.fetchRepositoryMetadata(name))
        .array();

    logInfo("Building SHA to version identifier mapping");
    Version[string] sha_mapping;
    projects
        .filter!(proj => proj.library)
        .tee!(proj => logInfo(".. %s", proj.name))
        .map!(proj => proj.tags)
        .each!(aa => aa.mergeInto(sha_mapping));

    logInfo("Resolving dependency versions for all projects");
    foreach (ref project; projects)
        project.updateRepositoryDependencies(client, sha_mapping);

    logInfo("Generating HTML report");
    generateHTMLReport(projects, "./report.html");
}

/**
    Uses GitHub API to get all specified organization D projects excluding some
    pre-defined list

    Params:
        client = octod API connection
        org = organization name to query for primary repo list
        excluded = list of repo names that need to be ignored during listing
        included = list of additional repos to include
 **/
string[] fetchAllProjects ( HTTPConnection client,
    string org, string[] excluded, string[] included )
{

    import std.algorithm.searching : canFind;
    import std.algorithm.iteration : filter, map;
    import std.array : array;
    import std.exception : ifThrown;

    auto repos = client
        .listOrganizationRepos(org)
        .filter!(repo => repo.language().ifThrown("") == "D")
        .filter!(repo => !excluded.canFind(repo.name()))
        .map!(repo => org ~ "/" ~ repo.name())
        .array();

    repos ~= included;

    return repos;
}

/**
    Merges content of one associative array into another one of the same type.

    Params:
        from = array to merge entries from
        to = array to accumulate the data
 **/
void mergeInto (T, U) ( T[U] from, ref T[U] to )
{
    foreach (k, v; from)
        to[k] = v;
}
