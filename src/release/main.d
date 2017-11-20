/*******************************************************************************

    Library release tool.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

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
import octod.api.releases;
import octod.core;


import std.variant;

/// Invalid version marker used with GithubReleaseVersion
struct InvalidVersion {}

/// Wrap a version and an invalid-version marker
alias GithubReleaseVersion = Algebraic!(Version, InvalidVersion);

/*******************************************************************************

    Programs entry point

*******************************************************************************/

version(UnitTest) {} else
void main ( string[] params )
{
    import release.shellHelper;
    import release.options;

    import vibe.core.log;

    import std.stdio;
    import std.algorithm : map, sort, uniq, filter;
    import std.range : array;
    import std.exception : ifThrown;

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

    auto conf = getConf();
    conf.baseURL = opts.github_url;

    auto con = HTTPConnection.connect(conf);
    auto repo = con.repository(getUpstream());

    auto tags = repo
        .releasedTags()
        .map!(a=>GithubReleaseVersion(Version.parse(a.name)).ifThrown(GithubReleaseVersion(InvalidVersion.init)))
        .filter!(a=>a.peek!Version)
        .map!(a=>a.get!Version);

    auto tags_with_prereleases = tags
        .array;

    auto tags_no_prerelease = tags
        .filter!(a=>a.prerelease.length == 0)
        .array;

    sort(tags_with_prereleases);
    sort(tags_no_prerelease);


    cmd("git remote update");

    auto myrelease = autodetectVersions(tags_with_prereleases);

    sanityCheckMilestone(con, repo, myrelease.toString);

    ActionList list;

    with (Type) final switch (myrelease.type)
    {
        case Patch:
            list = preparePatchRelease(con, repo, tags_no_prerelease, myrelease);
            break;
        case Minor:
            list = prepareMinorRelease(con, repo, tags_no_prerelease, myrelease,
                                       opts.release_subsequent);
            break;
        case Major:
            list = prepareMajorRelease(con, repo, tags_no_prerelease, myrelease);
            break;
    }

    // No actions? Stop.
    if (list == ActionList())
        return;

    writefln("Actions to be done:");

    foreach (action; list.actions)
        writefln(" * %s (%s)", action.description, action.command);

    if (!getBoolChoice("\nWould you like to continue?"))
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

    if (!getBoolChoice("Would you like to push the modified references now?"))
    {
        writefln("Aborting...");
        return;
    }

    import release.gitHelper;
    import std.format;

    cmd(["git", "push", getRemote(getUpstream())] ~ array(unique_refs));

    writefln("Some tags on github should be released: %s",
             list.releases);

    if (!getBoolChoice("Would you like to release those tags now?"))
    {
        writefln("Aborting...");
        return;
    }

    foreach (ver; list.releases)
        keepTrying(
        {
            writef("Creating %s ... ", ver);
            createGithubRelease(con, repo, ver, getTagMessage(ver));
        });

    import release.github;
    import std.algorithm : filter, canFind;

    auto open_milestones = listMilestones(con, repo)
        .filter!(a=>list.releases.canFind(a.title));

    if (!open_milestones.empty)
    {
        writefln("Some milestones on github should be closed: %s",
                 open_milestones.map!(a=>a.title));

        if (getBoolChoice("Would you like to close them now?"))
        {
            foreach (milestone; open_milestones)
                keepTrying(
                {
                    writef("Closing %s (%s open issues) ... ",
                        milestone.title, milestone.open_issues);

                    updateMilestoneState(con, repo, milestone.number, State.closed);
                });
        }
    }

    auto recipient = getConfig("neptune.mail-recipient").ifThrown("");

    if (recipient.length > 0)
    {
        auto email = craftMail(con, repo, myrelease.type, recipient,
            list.actions
                .map!(a=>cast(ReleaseAction) a)
                .filter!(a=>a !is null)
                .array);

        writefln("This is the announcement email:\n-----\n%s\n-----", email);

        if (!opts.no_send_mail &&
            getBoolChoice("Would you like to send it to %s now?", recipient))
        {
            sendMail(email, recipient);
        }
    }
    else
    {
        writefln("Can't send email, neptune.mail-recipient config missing or corrupt!");
    }

    writefln("All done.");
}


/*******************************************************************************

    Creates a github release, including the associated milestone link at the top

    Params:
        con = connection to use
        repo = repo to use
        ver = version to release
        notes = version notes

*******************************************************************************/

void createGithubRelease ( HTTPConnection con, Repository repo, string ver,
                           string notes )
{
    auto mstone_link = getMilestoneLink(con, repo, ver);

    con.createRelease(repo, ver, ver, mstone_link ~ notes);
}


/*******************************************************************************

    Acquires the milestone link or and empty string if no milestone was found

    Params:
        con = connection to use
        repo = repo to use
        ver = version associated with the milestone

    Returns:
        mile stone link as string or empty string if no milestone found

*******************************************************************************/

string getMilestoneLink ( HTTPConnection con, Repository repo, string ver )
{
    import release.github;
    import release.gitHelper;

    import std.algorithm;
    import std.stdio;
    import std.range;
    import std.exception : enforce;

    auto mstone_list = listMilestones(con, repo).find!(a=>a.title == ver);

    if (!mstone_list.empty)
        return mstone_list.front.url ~ "\n\n";

    return "";
}


/*******************************************************************************

    Sends the announcement email

    Params:
        email = complete email, including headers and body
        recipient = recipient email

*******************************************************************************/

void sendMail ( string email, string recipient )
{
    import release.gitHelper;

    import std.process;
    import std.format;
    import std.stdio;
    import std.exception : ifThrown;

    auto sendmailbin = getConfig("neptune.sendmail").ifThrown("sendmail");
    auto proc = pipeProcess([sendmailbin, recipient]);

    proc.stdin.write(email);
    proc.stdin.flush();
    proc.stdin.close();

    string _stdout, _stderr, errline, outline;

    while (true)
    {
        if ((outline = proc.stdout.readln()) !is null)
            _stdout ~= outline;

        if ((errline = proc.stderr.readln()) !is null)
            _stderr ~= errline;

        if (errline is null && outline is null)
            break;
    }

    write(_stdout);
    write(_stderr);

    wait(proc.pid);
}


/*******************************************************************************

    Crafts a release announcement email

    Params:
        Range = range type of the releases
        con = connection to use
        repo = repo to use
        rel_type = type of release this is
        releases = all the releases that have been done

    Returns:
        complete email text with From and Subject headers

*******************************************************************************/

string craftMail ( Range ) ( ref HTTPConnection con, Repository repo,
    Type rel_type, string recipient, Range releases )
{
    import release.gitHelper;

    import octod.api.issues;

    import std.format;
    import std.range;
    import std.algorithm;
    import std.stdio;

    // Introducing paragraphs for the release notes, depending on the type
    enum PreTexts = [
`If your application is using a %s %-(%s, %) release, it is recommended to plan to update to this new major release in the next 2-3 months. As this is a major release, it may contain API changes, removal of deprecated code, and other semantic changes; it is possible that you will need to change your code.

Release notes:`,
`If your application is using a previous %s %-(%s, %) release, it is recommended to update it to use this new minor release. As this is a minor release, it may contain new features, deprecations, or minor internal refactorings; it is guaranteed to not contain API changes and will not require you to change your code.

Release notes:`,
`If your application is using a previous %s %-(%s, %) release, it should be updated to use this new patch release as soon as possible. As this is a patch release, it contains only bugfixes; it is guaranteed not to contain new features or API changes and will not require you to change your code.

Issues fixed in this release:`];

    // Formats release notes for the given version
    string formatRelNotes ( ReleaseAction ver, Issue[] issues )
    {
        enum inherited_str = "\n\nThis release additionally inherits changes from ";

        auto inheritance_chain = ver.prev_release
            .recurrence!((s, n)=>s[n-1] !is null ? s[n-1].prev_release : null)
            .until!(a=>a is null)
            .map!(a=>a.tag_version);

        auto filteredIssues ( )
        {
            import std.string : strip;

            return format("%-(%s\n%)", issues
                .filter!(a=>a.json["milestone"]["title"] ==
                         ver.tag_version.toString)
                .map!(a=>format("* %s #%s", strip(a.title()), a.number())));
        }

        /* This complex format call basically creates a string like this:

           v1.2.3
           ======

           (if inherited changes)
           [This release [..] inherits [..] from v1.2.2, v1.1.1]

           (if patch)
           * Issue five #5
           * Another issue #45
           * and more #222

           (else)
           [Release notes of that version]
        */
        return format("%s\n%s%s%-(%s, %)\n\n%s",
            ver.tag_version, // Version
            repeat('=', ver.tag_version.toString.length), // to underline the version
            inheritance_chain.empty ? // string mentioning inherited changes
                "" :
                inherited_str,
            inheritance_chain, // list of versions we inherited from, if any
            rel_type == Type.Patch ? // if patch, use issue list, else use rel notes
                filteredIssues() :
                ver.rel_notes_without_inherited);
    }

    string formatRelLink ( string ver )
    {
        return format("http://github.com/%s/%s/releases/tag/%s",
            repo.json["owner"]["login"].get!string,
            repo.name(), ver);
    }

    /// Get branch for version
    string formatBranch ( ReleaseAction rel )
    {
        auto ver = rel.tag_version;

        /* Major releases want to have major version -1 here, e.g.
           v2.0.0 -> v1.x.x
         * Minor releases want the same major version
           number, e.g. v2.1.0 -> v2.x.x
         * Patch versions want all but the
           last number, e.g. v2.1.5 -> v2.1.x */
        return SemVerBranch(
            (rel_type == Type.Major ? -1 : 0) + ver.major,
            ver.patch == 0 ? -1 : ver.minor)
                .toString;
    }

    Issue[] issues;

    // Fetch issues only for patch releases
    if (rel_type == Type.Patch)
    {
        import release.shellHelper;
        import vibe.data.json;

        static void nullOut(A...)(A args) {}

        keepTrying!nullOut({
        issues = con
            .listIssues(format("%s/%s",
                               repo.json["owner"]["login"].get!string(),
                               repo.name), IssueState.Closed)
            .filter!(a=>a.json["milestone"].type == Json.Type.object)
            .array;
        });
    }

    auto name = getConfig("user.name");
    auto mail = getConfig("user.email");

    auto subject = format("[%sRelease] %s %-(%s, %)", rel_type, repo.name(),
                          releases.map!(a=>a.tag_version));

    string pretext;

    // Skip the whole pretext for v1.0.0 releases as it doesn't make sense here
    if (rel_type != Type.Major || releases.front.tag_version.major != 1)
        pretext = PreTexts[rel_type]
            .format(repo.name(), releases.map!formatBranch);

    auto full_mail = format(
`From: %s <%s>
To: %s
Subject: %s

%s`~ // Pretext
`
`/* Release notes  */~`
%-(%s
%)
`/* Release links */~`
%-(%s
%)
`,  name, mail, recipient, subject, pretext,
    releases.retro.map!(a=>formatRelNotes(a, issues)),
    releases.retro.map!(a=>formatRelLink(a.tag_version.toString)));

    return full_mail;
}


/***************************************************************************

    Creates local versions of all given remote branches

    Params:
        branches = remote branches to create local branches from

***************************************************************************/

void createLocalBranches ( R ) ( R branches )
{
    import release.gitHelper;
    import release.shellHelper;
    import std.format;

    auto upstream = getRemote(getUpstream());

    foreach (branch; branches)
        cmd(["git", "branch", "-f", branch.toString,
                format("%s/%s", upstream, branch)]);
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
        list.actions ~= new LocalAction(["git", "checkout", current_branch],
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
    ReleaseAction last_release;

    do
    {
        // Make sure we are on the branch we're operating on
        if (SemVerBranch(getCurrentBranch()) != current_branch)
            list.actions ~= new LocalAction(
                                     ["git", "checkout", current_branch.toString],
                                     format("Checkout next branch %s",
                                            current_branch));
        // Make the release
        list ~= makeRelease(current_release, current_branch.toString,
                            last_release);


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
                                 ["git", "checkouts", current_branch.toString],
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

        // Keep release notes if it is a prerelease
        if (minor_version.prerelease.length == 0)
            list ~= clearReleaseNotes();
    }
    while (follow &&
        minor_version.prerelease.length == 0/* never follow for prereleases's*/);

    scope(exit)
    {
        current_branch = SemVerBranch(getCurrentBranch());
        list.actions ~= new LocalAction(
                                ["git", "checkout", current_branch.toString],
                                format("Checkout original branch %s", current_branch));
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

    import std.file: dirEntries, SpanMode;
    import std.array: array;
    import std.algorithm.iteration: map;
    list.actions ~= new LocalAction(["git", "rm"] ~ array(dirEntries("relnotes", "*.md",
                                     SpanMode.shallow).map!("a.name")),
                                      "Removing release notes");
    list.actions ~= new LocalAction(["git", "commit", "-m",
                                     "Clear release notes after release"],
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

    static bool branchExists ( SemVerBranch branch )
    {
        import std.process : execute;

        auto res = execute(["git", "rev-parse", "--verify", branch.toString]);

        return res.status == 0;
    }

    auto previous_major_branch = current_branch;
    previous_major_branch.major--;

    // Make sure no merges are between the last major and this
    if (tags.length > 1 && branchExists(previous_major_branch))
    {
        import release.shellHelper;

        auto merges = cmd(["git", "log", "--oneline", "--merges",
                format("%s..%s", previous_major_branch, current_branch)]);

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

    auto list = makeRelease(major_version, current_branch.toString);

    list.affected_refs ~= current_branch.toString;

    auto next_major = current_branch;
    next_major.major++;

    auto branches = getBranches(con, repo, major_version, false);

    auto next_major_rslt = branches.find(next_major);

    // Only create next major branch and clear release notes when not doing a
    // prerelease
    if (major_version.prerelease.length == 0)
    {
        if (next_major_rslt.empty)
        {
            list.actions ~= new LocalAction(["git", "branch", next_major.toString],
                                            format("Create next major branch %s",
                                                   next_major));
        }

        list.actions ~= new LocalAction(["git", "checkout", next_major.toString],
                                        format("Checkout next major branch %s",
                                               next_major));

        list ~= clearReleaseNotes();

        list.affected_refs ~= next_major.toString;
    }

    list.actions ~= new LocalAction(["git", "checkout", current_branch.toString],
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

    auto branches = repo.branches()
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
    import release.options;

    import octod.api.repos;

    import std.stdio;
    import std.range;
    import std.algorithm;
    import std.exception : enforce;

    auto current = SemVerBranch(getCurrentBranch());
    writefln("We are on branch %s", current);

    if (tags.length == 0)
        writefln("Warning: No previous releases found. "~
                 "This should only be the case for your very first release!");

    auto matching_major = tags.retro.find!((a)
    {
        if (a.major != current.major)
            return false;

        if (!options.pre_release && a.prerelease.length > 0)
            return false;

        return true;
    });

    auto matching_minor = tags.retro.find!((a)
    {
        if (current.minor.isNull ||
            a.major != current.major ||
            a.minor != current.minor)
            return false;

        if (!options.pre_release && a.prerelease.length > 0)
            return false;

        return true;
    });

    Version rel_ver;

    bool detected =
        needPatchRelease(matching_major, matching_minor, current, rel_ver) ||
        needMinorRelease(matching_major, matching_minor, current, rel_ver) ||
        needMajorRelease(matching_major, matching_minor, current, rel_ver);

    enforce(detected);

    if (rel_ver.type == rel_ver.type.Patch)
        enforce(!options.pre_release,
            "Pre-releases are only allowed for upcoming minors and majors (not patch releases)");

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

        if (getBoolChoice("Would you like to use it as neptune.upstream config?"))
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


/*******************************************************************************

    Checks if the corresponding milestone exists and has no open issues.
    Warns the user on stdout if either condition is fulfilled

    Params:
        con = connection to use
        repo = repo to operate on
        name = name of the milestone

*******************************************************************************/

void sanityCheckMilestone ( ref HTTPConnection con, ref Repository repo, string name )
{
    import release.github;
    import std.algorithm;
    import std.stdio;
    import std.range;

    auto mstone_list = listMilestones(con, repo).find!(a=>a.title == name);

    if (mstone_list.empty)
    {
        writefln("Warning: No corresponding milestone found for %s", name);
        return;
    }

    auto mstone = mstone_list.front;

    if (mstone.open_issues > 0)
    {
        writefln("Warning: Corresponding milestone still has %s open issues!",
                 mstone.open_issues);
    }
}
