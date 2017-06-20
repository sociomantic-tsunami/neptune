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
            writefln("This seems to be a %s release which is not yet supported, exiting...",
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
        import std.string : strip, startsWith;

        writefln("%s ...\n\t%s",
                 action.description,
                 action.command);
        try writefln("\t%s", strip(cmd(action.command)));
        catch (ExitCodeException exc)
        {
            if (!action.command.startsWith("git merge"))
                throw exc;

            letUserResolveConflicts(exc.raw_msg);
        }
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


/*******************************************************************************

    Drops the user to a shell where they can resolve any merge conflict that
    might have happened

    Params:
        msg = message to show the user before dropping the shell

*******************************************************************************/

void letUserResolveConflicts ( string msg )
{
    import std.process;
    import std.exception;
    import std.stdio;

    writefln(msg);
    writefln("Exit the shell when you are done.(CTRL+D or 'exit')");

    auto shell_cmd = environment["SHELL"].ifThrown("bash");

    if (shell_cmd.length == 0)
        shell_cmd = "bash";

    auto shell = spawnShell(shell_cmd);
    shell.wait;
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

    do
    {
        // Make sure we are on the branch we're operating on
        if (SemVerBranch(getCurrentBranch()) != current_branch)
            list.local_actions ~= LocalAction(
                                     format("git checkout %s", current_branch),
                                     format("Checkout next branch %s",
                                            current_branch));
        // Make the release
        list ~= makeRelease(current_release, current_branch.toString);

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
                list.local_actions ~= LocalAction(
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

        list.local_actions ~= LocalAction("git rm relnotes/*.md",
                                          "Removing release notes");
        list.local_actions ~= LocalAction(`git commit -m "Clear release notes after release"`,
                                          "Commiting removal of release notes");
    }
    while (follow);

    scope(exit)
    {
        current_branch = SemVerBranch(getCurrentBranch());
        list.local_actions ~= LocalAction(format("git checkout %s", current_branch),
                                          format("Checkout original branch %s",
                                             current_branch));
    }

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
