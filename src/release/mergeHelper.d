/*******************************************************************************

    Helper classes to tag & merge

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.mergeHelper;

import release.versionHelper;
import release.actions;
import semver.Version;

/*******************************************************************************

    Class to build the list of actions required to make a patch release

*******************************************************************************/

class PatchMerger
{
    /// List of actions that will result in a release
    ActionList actions;

    /// Branches that received merges and will need to be released
    SemVerBranch[] pending_branches;

    /// All branches of this repo
    const(SemVerBranch[]) branches;

    /// All versions/tags of this repo
    const(Version[]) versions;

    /***************************************************************************

        Contsructor

        Params:
            branches = all existing branches of the repository
            versions = all existing versions/tags of the repository

    ***************************************************************************/

    this ( in SemVerBranch[] branches, in Version[] versions )
    {
        this.branches = branches;
        this.versions = versions;
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

        this.tagAndMerge(ver_branch);

        do
        {
            import std.algorithm;
            import std.array;

            this.pending_branches.sort();

            // Make sure that the array we're actively iterating over is not
            // changed
            auto local_pending_branches = this.pending_branches.uniq().array;

            foreach (pending; local_pending_branches)
                this.tagAndMerge(pending);

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

    void tagAndMerge ( SemVerBranch ver_branch )
    {
        import release.versionHelper;

        import std.algorithm;
        import std.range;
        import std.stdio;

        // Find next version to be released
        auto next_ver = this.findNewPatchRelease(ver_branch);

        // Release it
        this.actions ~= makeRelease(next_ver, ver_branch.toString);

        // Find next minor branch on current major branch
        auto subsq_minor_rslt = this.branches
                                    .find!(a=>a > next_ver &&
                                              a.major == next_ver.major &&
                                              a.type == Type.Minor);

        if (!subsq_minor_rslt.empty)
        {
            auto subsq_minor = subsq_minor_rslt.front;

            assert(subsq_minor.type == Type.Minor);

            this.actions.affected_refs ~= subsq_minor.toString();

            // Merge our release into the minor branch
            this.actions ~= checkoutMerge(next_ver, subsq_minor);

            this.pending_branches ~= subsq_minor;
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

        this.actions.affected_refs ~= next_minor_branch.toString();

        // Merge into that minor branch
        this.actions ~= checkoutMerge(next_ver, next_minor_branch);

        // Repeat all for that minor branch
        if (!this.pending_branches.canFind(next_minor_branch))
        {
            this.tagAndMerge(next_minor_branch);
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
        import release.gitHelper;

        import std.algorithm;
        import std.range;

        Version prev_ver = ver;
        assert(ver.patch > 0);
        prev_ver.patch--;

        // Find oldest minor branch in major version that is an ancestor to
        // the last made patch release before <ver>
        auto rslt = this.branches.find!(a=>a.major == major &&
                                           a.type == a.type.Minor &&
                                           isAncestor(prev_ver.toString, a.toString));

        import std.stdio;

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

        // Find latest patch release of this minor branch
        auto latest_patch = this.versions.retro.find!(a=>a.minor == br.minor &&
                                                         a.major == br.major);


        // A minor branch MUST have a release
        assert(!latest_patch.empty);

        Version next_ver = latest_patch.front;
        next_ver.patch++;

        return next_ver;
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

    list.actions ~= new LocalAction(format("git checkout %s",
                                           checkout),
                                    format("Checkout %s locally", checkout));
    list.actions ~= new LocalAction(format(`git merge -m %s "Merge tag %s into %s" %s`,
                                           merge, checkout, merge),
                                    format("Merge %s into %s", merge, checkout));

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

    ActionList list;

    with (list)
    {
        actions ~= new LocalAction(format("git tag -m %s %s %s", v, v, target),
                                   format("Create annotated tag %s", v));
        affected_refs ~= v;
    }

    // Is this a major or minor release?
    with (release_version) if (patch == 0)
    {
        auto branch = SemVerBranch(major, minor);

        // Create the appropriate branch
        list.actions ~= new LocalAction(format("git branch %s %s", branch, v),
                                        format("Create tracking branch %s",
                                               branch));

    }

    return list;
}
