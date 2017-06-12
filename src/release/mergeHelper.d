/*******************************************************************************

    Helper classes to tag & merge

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.mergeHelper;

import release.versionHelper;

/*******************************************************************************

    Structure to define a command to be run locally along with a description of
    it

*******************************************************************************/

struct LocalAction
{
    string command;
    string description;
}

/*******************************************************************************

    Structure to collect actions and metatadata about those actions

*******************************************************************************/

struct ActionList
{
    /// List of actions to execute, local only
    LocalAction[] local_actions;

    /// tags/branches that were locally modified and will be pushed
    string[] affected_refs;

    /// Releases to do on github
    string[] github_releases;

    ref ActionList opOpAssign ( string op ) ( const ActionList list )
    {
        this.local_actions ~= list.local_actions;
        this.affected_refs ~= list.affected_refs;
        this.github_releases ~= list.github_releases;

        return this;
    }

    void reset ( )
    {
        this.local_actions.length = 0;
        this.affected_refs.length = 0;
        this.github_releases.length = 0;
    }
}

/*******************************************************************************

    Class to build the list of actions required to make a patch release

*******************************************************************************/

class PatchMerger
{
    /// List of actions that will result in a release
    ActionList actions;

    /// Branches that received merges and will need to be released
    Version[] pending_branches;

    /// All branches of this repo
    const(Version[]) branches;

    /// All versions/tags of this repo
    const(Version[]) versions;

    /***************************************************************************

        Contsructor

        Params:
            branches = all existing branches of the repository
            versions = all existing versions/tags of the repository

    ***************************************************************************/

    this ( in Version[] branches, in Version[] versions )
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
        releasing of v1.2.x, merging itt into v2.2.x and releasing that.

        Params:
            ver_branch = branch to release

        Returns:
            A list of actions to make this release

    ***************************************************************************/

    ActionList release ( Version ver_branch )
    {
        this.actions.reset();

        this.tagAndMerge(ver_branch);

        do
        {
            import std.algorithm;

            this.pending_branches.sort();
            this.pending_branches.uniq();

            // Make sure that the array we're actively iterating over is not
            // changed
            auto local_pending_branches = this.pending_branches.dup;

            foreach (pending; local_pending_branches)
                this.tagAndMerge(pending);

            this.pending_branches.sort();
            this.pending_branches.uniq();

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

    void tagAndMerge ( Version ver_branch )
    {
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
                                              a.major == next_ver.major);

        if (!subsq_minor_rslt.empty)
        {
            auto subsq_minor = subsq_minor_rslt.front;

            assert(subsq_minor.type == Version.Type.Minor);

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
                                          Version(Version.Type.Major, next_ver.major));
        }

        // Find next major branch
        auto next_major_rslt = this.branches
                                   .find!(a=>a.major > next_ver.major &&
                                             a.type == a.type.Major);

        if (next_major_rslt.empty)
        {
            return;
        }

        // Find next minor branch within that major branch that corresponds to
        // our current branch
        auto next_minor_branch = this.findCorrespondingBranch(
                                                      next_major_rslt.front.major,
                                                      next_ver);

        if (next_minor_branch == Version())
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

        Returns:
            corresponding minor branch in next major version

    ***************************************************************************/

    Version findCorrespondingBranch ( int major, in Version ver )
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
            return Version();

        // Check for false positives: Our next higher feature/minor release must
        // NOT be an ancestor to the one we found
        auto next_rls_rslt = this.versions.find!(a=>a.major == ver.major &&
                                                    a.minor >  ver.minor);

        // There is no next minor/feature release, return our result
        if (next_rls_rslt.empty)
            return rslt.front;

        // The next release IS an ancestor, false positive, return
        if (isAncestor(next_rls_rslt.front.toString, rslt.front.toString))
            return Version();

        return rslt.front;
    }

    /***************************************************************************

        Finds the next patch release to be done after the current one

        Params:
            br = current branch/patch version

        Returns:
            next higher patch version

    ***************************************************************************/

    Version findNewPatchRelease ( Version br )
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

    /***************************************************************************

        Checksout & merges two refs

        Params:
            merge = ref to merge
            checkout = ref to merge into

        Returns:
            list of actions to do the checkout / merge

    ***************************************************************************/

    ActionList checkoutMerge ( in Version merge, in Version checkout )
    {
        import std.format;

        ActionList list;

        list.local_actions ~=
            LocalAction(format("git checkout %s",
                               checkout),
                        format("Checkout %s locally", checkout));
        list.local_actions ~=
            LocalAction(format(`git merge -m "Merge tag %s into %s" %s`,
                               merge, checkout, merge),
                        format("Merge %s into %s", merge, checkout));

        return list;
    }
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
    assert(!release_version.major.isNull &&
           !release_version.minor.isNull &&
           !release_version.patch.isNull);

    import std.format;
    auto v = release_version.toString();

    return ActionList([LocalAction(format("git tag -m %s %s %s", v, v, target),
                                  format("Create annotated tag %s", v))],
                      [v],
                      [v]);
}
