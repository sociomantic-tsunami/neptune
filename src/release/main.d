/*******************************************************************************

    Library release tool.

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.main;

import release.api;
import release.versionHelper;
import release.mergeHelper;
import semver.Version;

import octod.api.repos;
import octod.core;

/*******************************************************************************

    Programs entry point

*******************************************************************************/

void main ( string[] params )
{
    import release.shellHelper;
    import release.options;

    import vibe.core.log;

    import std.stdio;
    import std.algorithm : map, sort;
    import std.range : array;

    auto opts = parseOpts(params);

    if (opts.help_triggered)
        return;

    setLogLevel(opts.logging);

    checkOAuthSetup();

    auto con = HTTPConnection.connect(getConf());
    auto repo = con.repository(getUpstream());
    auto tags = repo.releasedTags().map!(a=>Version.parse(a.name)).array;

    sort(tags);

    cmd("git remote update");

    auto myrelease = autodetectVersions(tags);

    ActionList list;

    if (myrelease.type == myrelease.type.Patch)
        list = preparePatchRelease(con, repo, tags, myrelease);
    else
    {
        writefln("This seems to be %s release which is not yet supported, exiting...",
                 myrelease.type);
        return;
    }

    writefln("Actions to be done:");

    foreach (action; list.local_actions)
        writefln(" * %s (%s)", action.description, action.command);

    if (!readYesNoResponse("\nWould you like to continue?"))
    {
        writefln("Aborting...");
        return;
    }


    writefln("");
    foreach (action; list.local_actions)
    {
        import std.string : strip;

        writefln("%s ...\n\t%s",
                 action.description,
                 action.command);
        writefln("\t%s", strip(cmd(action.command)));
    }

    writefln("Done! Some references should be pushed: %s", list.affected_refs);

    if (!readYesNoResponse("Would you like to push the modified references now?"))
    {
        writefln("Aborting...");
        return;
    }

    import release.gitHelper;
    import std.format;

    cmd(format("git push %s %(%s %)", getRemote(getUpstream()), list.affected_refs));
}


/***************************************************************************

    Creates local versions of all given remote branches

    Params:
        remote branches to create local branches from

***************************************************************************/

void createLocalBranches ( R ) ( R branches )
{
    import release.gitHelper;
    import release.shellHelper;
    import std.format;

    auto upstream = getRemote(getUpstream());

    foreach (branch; branches)
        cmd(format("git branch -f %s %s/%s", branch, upstream, branch));
}


/*******************************************************************************

    Prepares the actions for a patch release

    Params:
        con = connection object
        repo = repo object
        tags = array of tags for this repo
        patch_version = version to release

    Returns:
        prepared ActionList object with all refs/actions required for this
        release

*******************************************************************************/

ActionList preparePatchRelease ( ref HTTPConnection con, ref Repository repo,
                                 Version[] tags, Version patch_version )
{
    import release.github;
    import release.gitHelper;
    import release.mergeHelper;

    import std.format;
    import std.algorithm;
    import std.range;
    import std.stdio;

    // Get version tracking branches
    auto branches = getBranches(con, repo, patch_version);

    createLocalBranches(branches);

    auto current_branch = getCurrentBranch();

    ActionList list;

    scope(exit)
        list.local_actions ~= LocalAction(format("git checkout %s", current_branch),
                                          format("Checkout original branch %s",
                                             current_branch));

    scope releaser = new PatchMerger(branches, tags);

    list ~= releaser.release(SemVerBranch(current_branch));

    return list;
}


/*******************************************************************************

    Params:
        release_version = release version to make
        target = target reference for the release

    Returns:
        an actionlist element containing all the actions/refs required to do the
        requested release

*******************************************************************************/

ActionList makeRelease ( Version release_version, string target )
{
    import std.format;
    auto v = release_version.toString();


/*******************************************************************************

    Gathers the branches in this repo, filtered and sorted so that

    - sorted by ascending order
    - the branch matching major/minor with the given version is excluded
    - the branches are newer than the given version
    - except for the matching major branch if "same_major" is set

    Params:
        con = connection to be used
        repo = repo to be operated on
        ver  = version to base filters on
        same_major = if set, include the major branch matching the given version

    Returns:
        array of branches, sorted and filtered as described

*******************************************************************************/

SemVerBranch[] getBranches ( ref HTTPConnection con, ref Repository repo,
                             Version ver, bool same_major = true )
{
    static import release.github;

    import std.algorithm;
    import std.range;

    bool thisVersion ( SemVerBranch v )
    {
        return v.major == ver.major &&
               v.minor == ver.minor;
    }

    bool newerVersion ( SemVerBranch v )
    {
        return v > ver;
    }

    bool ourMajorRelease ( SemVerBranch v )
    {
        return v.major == ver.major &&
               v.minor.isNull;
    }

    auto branches = release.github.getBranches(con, repo)
                      .map!(a=>SemVerBranch(a.name))
                      .filter!(a=>!thisVersion(a) &&
                                  (newerVersion(a) ||
                                  (same_major && ourMajorRelease(a))))
                      .array();

    branches.sort();

    return branches;
}


/*******************************************************************************

    Autodetects what kind of release and which version most likely needs to be
    done

    The type of the release is detected according to this table:

    MA = current branch major version number
    MI = current branch minor version number
    eqMA = equal major version tag existing
    eqMI = equal minor version tag existing

    MA MI eqMA eqMI type    // example
    0  1  1    0    Minor   // tag 2.0.0  branch 2.1.x
    1  0  1    0    Minor   // tag 3.1.2  branch 3.x.x
    0  1  1    1    Patch   // tag 2.1.0  branch 2.1.x
    1  0  0    0    Major   // tag 2.0.0  branch 3.x.x

    Params:
        tags = tags of the repository

    Returns:
        most likely version to be released

*******************************************************************************/

Version autodetectVersions ( Version[] tags )
{
    import release.shellHelper;
    import release.gitHelper;
    import release.versionHelper;

    import octod.api.repos;

    import std.stdio;
    import std.range;
    import std.algorithm;
    import std.exception : enforce;

    auto current = SemVerBranch(getCurrentBranch());

    assert(tags.length > 0, "No tags found?!");

    auto matching_major = tags.retro.find!(a=>a.major == current.major);
    auto matching_minor = tags.retro.find!(a=>a.major == current.major &&
                                              a.minor == current.minor);
    Version rel_ver;

    bool detected =
        needPatchRelease(matching_major, matching_minor, current, rel_ver) ||
        needMinorRelease(matching_major, matching_minor, current, rel_ver) ||
        needMajorRelease(matching_major, matching_minor, current, rel_ver);

    enforce(detected);

    writefln("We are on branch %s", current);
    writefln("Detected release %s", rel_ver);

    return rel_ver;
}


/*******************************************************************************

    Accuires the upstream location

    Returns:
        the upstream

*******************************************************************************/

string getUpstream ( )
{
    import release.shellHelper;
    import release.gitHelper;
    import std.exception;
    import std.stdio;

    /// Asks the user if hub.upstream should be used
    static string tryHubUpstream ( )
    {
        auto hubupstream = getConfig("hub.upstream");

        writefln("However, an hub.upstream configuration was found: %s",
                 hubupstream);

        if (readYesNoResponse("Would you like to use it as neptune.upstream config?"))
           return hubupstream;

        throw new Exception("");
    }

    /// Gets the upstream location through interaction with git and the user
    static string getUpstreamFromUser ( )
    {
        writefln("No neptune upstream config found.");

        return tryHubUpstream().ifThrown(askUpstreamName());
    }

    return getConfig("neptune.upstream")
              .ifThrown(configureUpstream(getUpstreamFromUser()));
}
