/*******************************************************************************

    Library release tool.

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.main;

import release.api;
import release.actions;
import release.versionHelper;
import release.releaseHelper;
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
    import std.algorithm : map, sort, uniq;
    import std.range : array;

    auto opts = parseOpts(params);

    if (opts.help_triggered)
        return;

    setLogLevel(opts.logging);

    checkOAuthSetup();

    try
    {
        import release.gitHelper;
        getRemote(getUpstream());
    }
    catch (Exception exc)
    {
        writefln("Warning: %s", exc.msg);
    }

    auto con = HTTPConnection.connect(getConf());
    auto repo = con.repository(getUpstream());
    auto tags = repo.releasedTags().map!(a=>Version.parse(a.name)).array;

    sort(tags);

    cmd("git remote update");

    auto myrelease = autodetectVersions(tags);

    ActionList list;

    with (Type) final switch (myrelease.type)
    {
        case Patch:
            list = preparePatchRelease(con, repo, tags, myrelease);
            break;
        case Minor:
            list = prepareMinorRelease(con, repo, tags, myrelease,
                                       opts.release_subsequent);
            break;
        case Major:
            list = prepareMajorRelease(con, repo, tags, myrelease);
            break;
    }

    // No actions? Stop.
    if (list == ActionList())
        return;

    writefln("Actions to be done:");

    foreach (action; list.actions)
        writefln(" * %s (%s)", action.description, action.command);

    if (!readYesNoResponse("\nWould you like to continue?"))
    {
        writefln("Aborting...");
        return;
    }


    writefln("");
    foreach (action; list.actions)
    {
        writefln("%s ...\n\t%s",
                 action.description,
                 action.command);
        writefln("\t%s", action.execute());
    }

    // Make sure we mention each ref only once or git push will complain
    list.affected_refs.sort();
    auto unique_refs = list.affected_refs.uniq();

    writefln("Done! Some references should be pushed: %s", unique_refs);

    if (!readYesNoResponse("Would you like to push the modified references now?"))
    {
        writefln("Aborting...");
        return;
    }

    import release.gitHelper;
    import std.format;

    cmd(format("git push %s %(%s %)", getRemote(getUpstream()), unique_refs));

    writefln("Some tags on github should be released: %s",
             list.releases);

    if (!readYesNoResponse("Would you like to release those tags now?"))
    {
        writefln("Aborting...");
        return;
    }

    foreach (ver; list.releases)
    {
        import release.github;

        writefln("Creating %s ...", ver);
        con.createRelease(repo, ver, ver, getTagMessage(ver));
    }

    writefln("All done.");
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
    import release.versionHelper;

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
        list.actions ~= new LocalAction(format("git checkout %s", current_branch),
                                        format("Checkout original branch %s",
                                               current_branch));

    scope releaser = new PatchMerger(branches, tags);

    list ~= releaser.release(SemVerBranch(current_branch));

    return list;
}


/*******************************************************************************

    Prepares the actions for a minor release

    Params:
        con = connection object
        repo = repo object
        tags = array of tags for this repo
        minor_version = version to release
        follow = is set, will also release merged branches

    Returns:
        prepared ActionList object with all refs/actions required for this
        release

*******************************************************************************/

ActionList prepareMinorRelease ( ref HTTPConnection con, ref Repository repo,
                                 Version[] tags, Version minor_version,
                                 bool follow = true )
{
    import release.gitHelper;

    import std.format;
    import std.algorithm;
    import std.range;
    import std.stdio;

    ActionList list;

    auto current_branch = SemVerBranch(getCurrentBranch());

    // Get version tracking branches
    auto branches = getBranches(con, repo, minor_version, false);
    auto major_branches = branches.filter!(a=>a.type == Type.Major &&
                                              a != current_branch);

    auto current_release = minor_version;
    string last_release;

    do
    {
        // Make sure we are on the branch we're operating on
        if (SemVerBranch(getCurrentBranch()) != current_branch)
            list.actions ~= new LocalAction(
                                     format("git checkout %s", current_branch),
                                     format("Checkout next branch %s",
                                            current_branch));
        // Make the release
        list ~= makeRelease(current_release, current_branch.toString,
                            last_release);

        last_release = current_release.toString;

        // Mark branch as modified (before the actual modification as we're
        // about to overwrite "current_branch" with the next one)
        list.affected_refs ~= current_branch.toString;

        // Merge release in subequent majors
        if (!major_branches.empty)
        {
            // find latest release on that branch
            auto latest_rel = tags.retro.find!(a=>a.major ==
                                                  major_branches.front.major);

            // No release? Stop then, this is an unreleased major branch
            if (latest_rel.empty)
                follow = false;
            else
            {
                // merge
                list ~= checkoutMerge(current_release, major_branches.front);

                // Checkout previous branch so we can remove the rel notes
                list.actions ~= new LocalAction(
                                         format("git checkout %s", current_branch),
                                         format("Checkout previous branch %s",
                                                current_branch));

                // If we don't iterate again, add this branch as modified
                // right here
                if (!follow)
                    list.affected_refs ~= major_branches.front.toString;
            }

            // Should we release on the next major branch too?
            if (follow)
            {
                current_branch = major_branches.front;

                major_branches.popFront;

                current_release = Version(current_branch.major,
                                          latest_rel.front.minor+1, 0);
            }
        }
        else
            follow = false;

        list ~= clearReleaseNotes();
    }
    while (follow);

    scope(exit)
    {
        current_branch = SemVerBranch(getCurrentBranch());
        list.actions ~= new LocalAction(format("git checkout %s", current_branch),
                                        format("Checkout original branch %s",
                                               current_branch));
    }

    return list;
}


/*******************************************************************************

    Prepares the actions to clar the release notes

    Returns:
        actions required to clear the release notes

*******************************************************************************/

ActionList clearReleaseNotes ( )
{
    ActionList list;

    list.actions ~= new LocalAction("git rm relnotes/*.md",
                                      "Removing release notes");
    list.actions ~= new LocalAction(`git commit -m "Clear release notes after release"`,
                                      "Commiting removal of release notes");

    return list;
}


/*******************************************************************************

    Prepares the actions for a major release

    Params:
        con = connection object
        repo = repo object
        tags = array of tags for this repo
        major_version = version to release

    Returns:
        prepared ActionList object with all refs/actions required for this
        release

*******************************************************************************/

ActionList prepareMajorRelease ( ref HTTPConnection con, ref Repository repo,
                                 Version[] tags, Version major_version )
{
    import release.gitHelper;

    import std.algorithm : find;
    import std.range : empty;
    import std.format : format;

    auto current_branch = SemVerBranch(getCurrentBranch());

    // Make sure no merges are between the last major and this
    if (current_branch.major > 1)
    {
        import release.shellHelper;

        auto previous_major_branch = current_branch;
        previous_major_branch.major--;

        auto merges = cmd(format("git log --oneline --merges %s..%s",
                                 previous_major_branch, current_branch));

        if (merges.length > 0)
        {
            import std.stdio;
            writefln("Found merges between this and the last major "~
                     "branch:\n-----\n%s\n-----\nPlease rebase the current branch and "~
                     "retry.\n", merges);
            return ActionList();
        }

        // Make sure the last major is an ancestor of this major
        if (!isAncestor(previous_major_branch.toString, current_branch.toString))
        {
            import std.stdio;
            writefln("%s is not decending from %s! Aborting!",
                     current_branch.toString, previous_major_branch.toString);
            return ActionList();
        }

    }

    auto list = makeRelease(major_version, current_branch.toString, "");

    list.affected_refs ~= current_branch.toString;

    auto next_major = current_branch;
    next_major.major++;

    auto branches = getBranches(con, repo, major_version, false);

    auto next_major_rslt = branches.find(next_major);

    if (next_major_rslt.empty)
    {
        list.actions ~= new LocalAction(format("git branch %s", next_major),
                                        format("Create next major branch %s",
                                               next_major));
    }

    list.actions ~= new LocalAction(format("git checkout %s", next_major),
                                    format("Checkout next major branch %s",
                                           next_major));

    list ~= clearReleaseNotes();

    list.affected_refs ~= next_major.toString;

    list.actions ~= new LocalAction(format("git checkout %s", current_branch),
                                    format("Checkout original branch %s",
                                           current_branch));
    return list;
}


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
               !v.minor.isNull && v.minor == ver.minor;
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

    if (tags.length == 0)
        writefln("Warning: No previous releases found. "~
                 "This should only be the case for your very first release!");

    auto matching_major = tags.retro.find!(a=>a.major == current.major);
    auto matching_minor = tags.retro.find!(a=>!current.minor.isNull &&
                                              a.major == current.major &&
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
