/*******************************************************************************

    Utilities to fetch various GitHub repository metadata used in report
    generation.

    Copyright:
        Copyright (c) 2009-2016 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module overview.repository;

import octod.core;
import octod.api.repos;

import overview.submodules;
import semver.Version;

/**
    Describes single repository metadata
 **/
struct Repository
{
    /// project name
    string          name;
    /// versions tagged in the project (key is git SHA)
    Version[string] tags;
    /// current versions of dependencies (key is dependency name)
    Version[string] dependencies;
    /// is a library project?
    bool            library;
}

/**
    Fetches repository metadata using GitHub API

    Ignores dependency field

    Params:
        client = GitHub API connection from octod
        full_name = owner/name of the GitHub repository
 **/
Repository fetchRepositoryMetadata ( HTTPConnection client, string full_name )
{
    import std.algorithm.iteration : map, filter;
    import std.array : assocArray;
    import std.typecons : tuple;
    import std.exception : ifThrown;
    import dyaml.node;
    import vibe.core.log : logInfo;

    logInfo(".. %s", full_name);

    auto repo = client.repository(full_name);

    Repository result;

    result.name = full_name;
    result.tags = repo
        .releasedTags()
        .map!(tag => tuple(tag.sha, Version.parse(tag.name).ifThrown(Version.init)))
        .filter!(pair => pair[1] != Version.init)
        .assocArray();

    Node yml = repo
        .download(".neptune.yml")
        .expectFile
        .content
        .parseYAML()
        .ifThrown(Node.init);

    result.library = {
        if (yml["library"].get!bool)
            return true;
        return false;
    } ().ifThrown(false);

    // will be set later in `updateRepositoryDependencies`
    result.dependencies = null;

    return result;
}

/**
    Fetches repository metadata using GitHub API

    Ignores dependency field

    Params:
        project = repository metadata to update
        client = GitHub API connection from octod
        mapping = pre-created map of submodule git hashes to respective
            version instances
 **/
void updateRepositoryDependencies ( ref Repository project, HTTPConnection client,
    Version[string] mapping )
{
    import std.algorithm.iteration : map, filter;
    import std.array : assocArray, array;
    import std.typecons : tuple, Tuple;
    import vibe.core.log : logInfo;

    logInfo(".. %s", project.name);

    auto repo = client.repository(project.name);

    // resolves submodule in currently processed repository to figure out
    // under what version string it is tagged in original repository, returning
    // tuple of name and version

    Tuple!(string, Version) resolveSubmoduleVersion ( Submodule info )
    {
        import std.format;
        import std.regex;
        import std.exception : enforce;

        try
        {
            auto sha = repo.download(info.path).expectSubmodule().sha;
            auto p_version = sha in mapping;

            enforce(
                p_version !is null,
                format("SHA '%s' for '%s' not found in mapping", sha, info.url)
            );

            // extract organization/name
            static rgxSubmoduleURL = regex(
                r"(https:\/\/)|(git@)github\.com\/|:([^\/]+)\/([^.]+)\.git");

            auto match = info.url.matchFirst(rgxSubmoduleURL);
            enforce(
                !match.empty,
                format("Unexpected submodule URL (%s) format", info.url)
            );

            return tuple(match[3] ~ "/" ~ match[4], *p_version);
        }
        catch (Exception e)
        {
            logInfo(".. %s", e.msg);
            return tuple("", Version.init);
        }
    }

    try
    {
        // eagerly allocate plain array first to workaround double calls to
        // map.front (which is assumed to be pure)
        auto arr = repo
            .listSubmodules
            .map!resolveSubmoduleVersion
            .array();

        project.dependencies = arr
            .filter!(pair => pair[0].length != 0)
            .assocArray();
    }
    catch (Exception e)
    {
        logInfo(".. FAILED (%s): %s", typeid(e), e.msg);
        return;
    }
}

/**
    YAML parsing helper for usage in pipeline

    Params:
        content = raw data that is expected to contain UTF-8 YAML text
 **/
private auto parseYAML ( const void[] content )
{
    import std.utf;
    import dyaml.loader;

    auto s = cast(char[]) content.dup;
    validate(s);
    return Loader.fromString(s).load();
}
