/*******************************************************************************

    Helper classes to tag & merge

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.mergeHelper;

import release.versionHelper;
import release.actions;
import semver.Version;

/// Specialized merge action. Falls back to the user to solve conflicts
class MergeAction : LocalAction
{
    /***************************************************************************

        C'tor

        Params:
            target = branch to merge into
            tag = tag to merge

    ***************************************************************************/

    this ( string target, string tag )
    {
        import std.format;
        import colorize;

        super(["git", "merge", "--no-ff", "-m",
                format("Merge tag %s into %s", tag, target), tag],
                format("%s %s %s %s",
                     "Merge".color(fg.green),
                     tag.color(fg.green, bg.init, mode.bold),
                     "into".color(fg.green),
                     target.color(fg.green, bg.init, mode.bold)));
    }

    /***************************************************************************

        Executes the merge action.

        If an ExitCodeException is thrown it means there were conflicts.
        In that case, a shell is dropped to the user to resolve those conflicts.

        Returns:
            output of merge command

    ***************************************************************************/

    override string execute ( )
    {
        import release.shellHelper;

        try return super.execute();
        catch (ExitCodeException exc)
            letUserResolveConflicts(exc.raw_msg);

        return "";
    }
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
    writefln("Resolve the conflicts and finish the merge process.\n" ~
        "Exit the shell when you are done.(CTRL+D or 'exit')");

    auto shell_cmd = environment["SHELL"].ifThrown("bash");

    if (shell_cmd.length == 0)
        shell_cmd = "bash";


    auto shell = spawnShell(shell_cmd);
    shell.wait;
}


/*******************************************************************************

    Class to build the list of actions required to make a patch release

*******************************************************************************/

class PatchMerger
{
    import Rel = release.releaseHelper;

    /// Wraps a branch that received a merge and requires releasing
    struct Pending
    {
        /// Branch that received a merge
        SemVerBranch branch;

        /// easy access of said branch
        alias branch this;

        /// Merge information about that branch
        Rel.ReleaseAction merged;
    }

    /// List of actions that will result in a release
    ActionList actions;

    /// Branches that received merges and will need to be released
    Pending[] pending_branches;

    /// All branches of this repo
    const(SemVerBranch[]) branches;

    /// All versions/tags of this repo
    const(Version[]) versions;

    /// Metadata to be used for all releases
    const(string[]) metadata;

    /***************************************************************************

        Contsructor

        Params:
            branches = all existing branches of the repository
            versions = all existing versions/tags of the repository
            metadata = metadata to be added to all releases

    ***************************************************************************/

    this ( in SemVerBranch[] branches, in Version[] versions, in string[] metadata )
    {
        this.branches = branches;
        this.versions = versions;
        this.metadata = metadata;
    }

    /***************************************************************************

        Prepares all actions to do a release and all merges and releases based
        on it.

        Release will be done recursively in a vertical manner, as in, the
        corresponding minor releases in the next major version will be done
        first. For example, given:

        [v1.1.x, v1.2.x, v2.1.x, v2.2.x]

        We will first release v1.1.1, merge it into v1.2.x and v2.1.x and then
        release v2.1.x.

        After that, all the subsequent minor releases on the same major version
        will be taken care of in a second iteration. In this case that would be
        releasing of v1.2.x, merging it into v2.2.x and releasing that.

        Params:
            ver_branch = branch to release

        Returns:
            A list of actions to make this release

    ***************************************************************************/

    ActionList release ( SemVerBranch ver_branch )
    {
        this.actions.reset();

        Rel.ReleaseAction rel;
        this.tagAndMerge(ver_branch, rel);

        do
        {
            import std.algorithm;
            import std.array;

            this.pending_branches.sort();

            // Make sure that the array we're actively iterating over is not
            // changed
            auto local_pending_branches = this.pending_branches.uniq().array;

            foreach (pending; local_pending_branches)
            {
                try this.tagAndMerge(pending.branch, pending.merged);
                catch (Exception exc)
                {
                    import std.format;
                    import colorize;
                    exc.msg = format("Failed to handle branch %s: %s".color(fg.red),
                        pending, exc.msg);
                    throw exc;
                }
            }

            this.pending_branches.sort();
            this.pending_branches = this.pending_branches.uniq().array;

            // Process the newly added branches in the next iteration
            this.pending_branches =
                this.pending_branches[local_pending_branches.length .. $];
        }
        while (this.pending_branches.length > 0);

        return this.actions;
    }

    /***************************************************************************

        Given the branches:

        * A — The branch given here as parameter, assumed to be a minor branch
        * B — The corresponding minor branch in the next major version
        * C — The next minor branch on the same major version

        Creates the next patch release for A and merges it into B and C.
        Then this function will call itself again with B as the parameter.

        C will be added to this.pending_branches to mark it as a branch that
        received merges but wasn't released yet.

        Params:
            ver_branch = branch to make a patch release on

    ***************************************************************************/

    void tagAndMerge ( SemVerBranch ver_branch, Rel.ReleaseAction prev )
    {
        import release.versionHelper;
        import release.releaseHelper;

        import std.algorithm;
        import std.range;
        import std.stdio;

        // Find next version to be released
        auto next_ver = this.findNewPatchRelease(ver_branch);
        next_ver.metadata = this.metadata.dup;

        // Release it
        this.actions ~= makeRelease(next_ver, ver_branch.toString, prev);

        // Find next minor branch on current major branch
        auto subsq_minor_rslt = this.branches
                                    .find!(a=>a > next_ver &&
                                              a.major == next_ver.major &&
                                              a.type == Type.Minor);

        if (!subsq_minor_rslt.empty)
        {
            auto subsq_minor = subsq_minor_rslt.front;

            assert(subsq_minor.type == Type.Minor);

            // Merge our release into the minor branch
            this.actions ~= checkoutMerge(next_ver, subsq_minor);

            this.pending_branches ~= Pending(subsq_minor, prev);
        }
        else
        {
            // This was the latest patch release on this major version, merge it
            // back into the major version branch
            this.actions ~= checkoutMerge(next_ver,
                                          SemVerBranch(next_ver.major));
        }

        // Find next major branch
        auto next_major_rslt = this.branches
                                   .find!(a=>a.major > next_ver.major &&
                                             a.type == a.type.Major);

        if (next_major_rslt.empty)
        {
            return;
        }

        SemVerBranch next_minor_branch;
        // Find next minor branch within that major branch that corresponds to
        // our current branch
        if (!this.findCorrespondingBranch(next_major_rslt.front.major, next_ver,
                                         next_minor_branch))
        {
            return;
        }

        // Merge into that minor branch
        this.actions ~= checkoutMerge(next_ver, next_minor_branch);

        // Repeat all for that minor branch
        if (!this.pending_branches.canFind(next_minor_branch))
        {
            this.tagAndMerge(next_minor_branch, prev);
        }
    }

    /***************************************************************************

        Finds the corresponding minor branch in the next major version for the
        given minor branch.

        Params:
            major = major version to check for
            ver   = current minor branch
            branch = out param, corresponding minor branch in next major version

        Returns:
            true if a branch was found

    ***************************************************************************/

    bool findCorrespondingBranch ( int major, in Version ver,
                                   out SemVerBranch branch )
    {
        import internal.git.helper;

        import std.algorithm;
        import std.range;

        assert(ver.patch > 0);

        const prev_ver = Version(ver.major, ver.minor, ver.patch-1,
            ver.prerelease, ver.metadata.dup);

        // Find oldest minor branch in major version that is an ancestor to
        // the last made patch release before <ver>
        auto rslt = this.branches.find!(a=>a.major == major &&
                                           a.type == a.type.Minor &&
                                           isAncestor(prev_ver.toString, a.toString));

        if (rslt.empty)
            return false;

        // Check for false positives: Our next higher feature/minor release must
        // NOT be an ancestor to the one we found
        auto next_rls_rslt = this.versions.find!(a=>a.major == ver.major &&
                                                    a.minor >  ver.minor);

        // There is no next minor/feature release, return our result
        if (next_rls_rslt.empty)
        {
            branch = rslt.front;
            return true;
        }

        // The next release IS an ancestor, false positive, return
        if (isAncestor(next_rls_rslt.front.toString, rslt.front.toString))
            return false;

        branch = rslt.front;
        return true;
    }

    /***************************************************************************

        Finds the next patch release to be done after the current one

        Params:
            br = current branch/patch version

        Returns:
            next higher patch version

    ***************************************************************************/

    Version findNewPatchRelease ( SemVerBranch br )
    {
        import std.algorithm;
        import std.range;
        import std.exception : enforce;

        // Find latest patch release of this minor branch
        auto latest_patch = this.versions
            .retro.find!(a=>a.minor == br.minor &&
                         a.major == br.major &&
                         a.prerelease.length == 0 &&
                         a.metadata.length == 0);


        // A minor branch MUST have a release
        enforce(!latest_patch.empty, "No release found for minor branch");

        with (latest_patch.front)
        {
            auto next_ver = Version(major, minor, patch+1, prerelease,
                                    metadata.dup);

            return next_ver;
        }
    }
}

/*******************************************************************************

    Checksout & merges two refs

    Params:
        merge = ref to merge
        checkout = ref to merge into

    Returns:
        list of actions to do the checkout / merge

*******************************************************************************/

ActionList checkoutMerge ( in Version merge, in SemVerBranch checkout )
{
    import std.format;

    ActionList list;

    list.actions ~= new LocalAction(["git", "checkout", checkout.toString],
                                    format("Checkout %s locally", checkout));
    list.actions ~= new MergeAction(checkout.toString, merge.toString);

    list.affected_refs ~= checkout.toString;

    return list;
}
