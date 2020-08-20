/*******************************************************************************

    Contains the structure and logic to perform a submodule update in a
    repository

    Copyright:
        Copyright (c) 2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module autopr.SubModsUpdate;

/// Format to use for update PR titles, matches the index with RCFlag values
public enum PRTitles = [
    "[neptune] [Rc+NoRc] Update submodules",
    "[neptune] [Rc] Update submodules",
    "[neptune] Update submodules"]; // non-rc, our default

/// refs to use for update PRs, matches the index with RCFlag values
public enum PRRefNames = [
    "refs/heads/neptune-update",
    "refs/heads/neptune-update-rc",
    "refs/heads/neptune-update-no-rc"
    ];

/// Flag to mark updates as RCs
public enum RCFlag
{
    All=0, Yes, No
}

/// Structure & logic to perform a submodule update
struct SubModsUpdate
{
    import semver.Version;
    import provider.core;
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

    /// Information about a specific submodule update
    struct SubModUpdate
    {
        /// Submodule to be updated
        NameWithOwner repo;

        /// Current submodule sha/version
        SubModVer cur;

        /// New submodule sha/version
        SubModVer target;

        /// Breaking versions included in the update
        SubModVer[] breaking;
    }

    /// Repository that receives the update PR
    NameWithOwner repo;

    /// SHA of current latest commit
    string commit_sha;
    /// SHA of root tree in latest commit
    string tree_sha;
    /// Branch name used for the update
    string branch;

    /// Whether this is an RC update or a stable update PR
    RCFlag release_candidates;

    /// PR number, if it already exists for an earlier update
    Nullable!int pr_number;

    /// List of submodule updates to perform
    SubModUpdate[] updates;

    /// List of already existing submodule updates
    SubModUpdate[] existing_updates;


    /***************************************************************************

        Creates or updates an existing PR for this update

        Params:
            con = provider connection reference to use
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

        string commit_sha = this.commit_sha;
        string tree_sha   = this.tree_sha;
        string pr_msg_part;

        if (this.updates.length == 0)
            return;

        foreach (update; this.updates)
            this.addUpdateCommit(con, fork_owner, fork_name, update,
                tree_sha, commit_sha, pr_msg_part);

        import vibe.data.json;

        Json reference;

        auto refname = PRRefNames[this.release_candidates];

        // Always try updating first. Chances are that the branch already exists
        try
        {
            writefln("%s> Updating reference %s", this.repo, refname);
            reference = con.updateReference(fork_owner,
                fork_name, refname, commit_sha);
        }
        catch (HTTPAPIException exc)
        {
            writef("%s> Failed to update reference, trying create ... ",
                this.repo);

            stdout.flush();

            reference = con.createReference(fork_owner,
                fork_name, refname, commit_sha);

            writefln("Ok");
        }

        auto content = format(
"This PR has been automatically created by *neptune-autopr* and
updates the following submodules:

%s
You can modify this behavior using your `.neptune.yml` file
as described in the [documentation](https://github.com/sociomantic-tsunami/neptune/blob/v0.x.x/doc/neptune-metadata.rst#automatic-update-prs).",
        pr_msg_part);

        if (this.pr_number.isNull)
        {
            writefln("%s> Creating PR (%s) ...",
                this.repo, this.release_candidates);

            auto pr = con.createPullrequest(this.repo.owner, this.repo.name,
                PRTitles[this.release_candidates], content, fork_owner,  this.branch, refname);
            this.pr_number = pr["number"].get!int;
        }
        else
        {
            writefln("%s> Adding comment to PR %s (%s)",
                this.repo, this.pr_number.get, this.release_candidates);

            auto pr = con.updatePullrequest(this.repo.owner, this.repo.name,
                this.pr_number.get, PRTitles[this.release_candidates], content);

            auto msg = format("This PR has been updated: \n\n%s",
                pr_msg_part);

            con.addComment(pr["node_id"].get!string, msg);
        }
    }

    void addUpdateCommit ( ref HTTPConnection con, string fork_owner,
        string fork_name, SubModUpdate update, ref string tree_sha,
        ref string commit_sha, ref string pr_msg_part )
    {
        import autopr.github;
        import std.stdio;
        import std.format;

        // Create Tree with updated submodule
        auto tree = con.createTree(fork_owner,
            fork_name, tree_sha,
            format("submodules/%s", update.repo.name),
            update.target.sha, Type.Submodule);

        tree_sha = tree["sha"].get!string;

        writefln("%s> Created updated tree for %s (%s)",
            this.repo, update.repo.name, tree_sha);

        auto relnotes = format(
            "https://github.com/%s/%s/releases/tag/%s",
            update.repo.owner, update.repo.name, update.target.ver);

        auto commits = format(
            "https://github.com/%s/%s/compare/%s...%s",
            update.repo.owner, update.repo.name, update.cur.ver, update.target.ver);

        string formatBreaking ( SubModVer v )
        {
            return format("[%s](https://github.com/%s/%s/releases/tag/%s)",
                v.ver, update.repo.owner, update.repo.name, v.ver);
        }

        import std.algorithm : map;

        auto breaking = format("%-(%s, %)",
            update.breaking.map!(a=>formatBreaking(a)));

        auto commit_msg = format(
           "Advance %s from %s to %s\n\n%s %s(%s)...%s(%s)\n\n" ~
           "Release notes: %s\nChanged commits: %s",
           update.repo.name, update.cur.ver, update.target.ver,
           update.repo.name,
           update.cur.ver,    update.cur.sha[0..7],
           update.target.ver, update.target.sha[0..7],
           relnotes, commits);

        auto commit = con.createCommit(fork_owner,
            fork_name, commit_sha, tree_sha, commit_msg);

        commit_sha = commit["sha"].get!string;

        writefln("%s> Created commit for %s (%s)",
            this.repo, update.repo.name, commit_sha);

        pr_msg_part ~= format(
            "* **%s** from version **%s** to version **%s** "~
            "([Release notes](%s), [Changed commits](%s))%s\n",
            update.repo.name, update.cur.ver, update.target.ver,
            relnotes, commits,
            update.breaking.length > 0 ? ("\n  * Breaking Updates: " ~ breaking) : "");
    }
}
