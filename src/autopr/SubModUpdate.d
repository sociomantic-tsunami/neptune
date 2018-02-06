/*******************************************************************************

    Contains the structure and logic to perform a submodule update in a
    repository

    Copyright:
        Copyright (c) 2017 sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module autopr.SubModUpdate;

/// Format to use for update PR titles
enum PRTitleFormat = "[neptune] Update %s to %s";
/// Format to use to match existing PR titles
enum PRTitleFormatMatch = PRTitleFormat[0 .. 23]; // ends at "to"

/// Structure & logic to perform a submodule update
struct SubModUpdate
{
    import semver.Version;
    import octod.core;
    import std.typecons;

    /// Possible actions we can do on PRs
    enum PRAction { Updated, Created, None };

    /// Struct to encapsulate repository owner and name
    struct NameWithOwner
    {
        /// Repo name
        string name;
        /// Repo owner
        string owner;

        /// Returns: repo name and owner
        string toString ( ) const
        {
            import std.format : format;
            return format("%s/%s", owner, name);
        }
    }

    /// Encapsulcates submodule informationü
    struct SubModVer
    {
        /// Submodule SHA
        string sha;
        /// Submodule version
        Version ver;
    }

    /// Repository that receives the update PR
    NameWithOwner repo;

    /// Submodule to be updated
    NameWithOwner submod;

    /// Current submodule sha/version
    SubModVer submod_cur;

    /// New submodule sha/version
    SubModVer submod_new;

    /// PR number, if it already exists for an earlier update
    Nullable!int pr_number;

    /// SHA of current latest commit
    string commit_sha;
    /// SHA of root tree in latest commit
    string tree_sha;
    /// Branch name used for the update
    string branch;


    /***************************************************************************

        Creates or updates an existing PR for this update

        Params:
            con = octod connection reference to use
            fork_owner = owner of the fork from which the PR will be created
            fork_name = name the fork repository has

        Returns:
            Whether the PR was created or only updated (or no action was taken)

    ***************************************************************************/

    void createOrUpdatePR ( ref HTTPConnection con, string fork_owner,
        string fork_name )
    {
        import autopr.github;
        import std.stdio;
        import std.format;

        // Create Tree with updated submodule
        auto tree = con.createTree(fork_owner,
            fork_name, this.tree_sha,
            format("submodules/%s", this.submod.name),
            this.submod_new.sha, Type.Submodule);

        writefln("%s> Created updated tree for %s (%s)",
            this.repo, this.submod, tree["sha"].get!string);

        auto commit_msg = format("Advance %s from %s to %s\n\n%s %s(%s)...%s(%s)",
           this.submod.name, this.submod_cur.ver, this.submod_new.ver,
           this.submod.name,
           this.submod_cur.ver, this.submod_cur.sha[0..7],
           this.submod_new.ver, this.submod_new.sha[0..7]);

        auto commit = con.createCommit(fork_owner,
            fork_name, this.commit_sha, tree["sha"].get!string, commit_msg);

        writefln("%s> Created commit for %s (%s)",
            this.repo, this.submod, commit["sha"].get!string);

        import vibe.data.json;

        Json reference;

        auto refname = format("refs/heads/update-%s", this.submod.name);

        // Always try updating first. Chances are that the branch already exists
        try
        {
            writefln("%s> Updating reference %s", this.repo, refname);
            reference = con.updateReference(fork_owner,
                fork_name, refname, commit["sha"].get!string);
        }
        catch (HTTPAPIException exc)
        {
            writef("%s> Failed to update reference, trying create ... ",
                this.repo);

            stdout.flush();

            reference = con.createReference(fork_owner,
                fork_name, refname, commit["sha"].get!string);

            writefln("Ok");
        }

        auto title =
            format(PRTitleFormat, this.submod.name, this.submod_new.ver);

        auto content = format(
"This PR has been automatically created by *neptune-autopr* and
updates submodule **%s** from version **%s** to version **%s**

You can modify this behavior using your `.neptune.yml` file as described in the
[documentation]((https://github.com/sociomantic-tsunami/neptune/blob/master/doc/neptune-metadata.rst#automatic-update-prs).

 * [Release notes](https://github.com/%s/%s/releases/tag/%s)
 * [Changed commits](https://github.com/%s/%s/compare/%s...%s)",
        this.submod.name, this.submod_cur.ver, this.submod_new.ver,
        this.submod.owner, this.submod.name, this.submod_new.ver,
        this.submod.owner, this.submod.name, this.submod_cur.ver, this.submod_new.ver);

        if (this.pr_number.isNull)
        {
            writefln("%s> Creating PR ...", this.repo);
            auto pr = con.createPullrequest(this.repo.owner, this.repo.name,
                title, content, fork_owner,  this.branch,
                format("update-%s", this.submod.name));
            this.pr_number = pr["number"].get!int;
        }
        else
        {
            writefln("%s> Adding comment to PR %s", this.repo, this.pr_number);
            auto pr = con.updatePullrequest(this.repo.owner, this.repo.name,
                this.pr_number, title, content);

            auto msg = format("This PR has been updated to %s %s",
                this.submod.name, this.submod_new.ver);

            con.addComment(pr["id"].get!string, msg);
        }
    }
}
