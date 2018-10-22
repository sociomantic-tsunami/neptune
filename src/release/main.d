/*******************************************************************************

    Library release tool.

    Copyright:
        Copyright (c) 2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.main;

import internal.RemoteConfig;
import release.actions;
import release.versionHelper;
import release.releaseHelper;
import release.mergeHelper;
import release.options;

import semver.Version;

import provider.api.Repos;
import provider.api.issues;
import provider.core;

import std.variant;

/// This apps configuration app name
enum AppName = "neptune";

/// Invalid version marker used with ReleaseVersion
struct InvalidVersion {}

/// Wrap a version and an invalid-version marker
alias ReleaseVersion = Algebraic!(Version, InvalidVersion);


/*******************************************************************************

    Programs entry point

*******************************************************************************/

version(UnitTest) {} else
void main ( string[] params )
{
    import release.shellHelper;

    import vibe.core.log;

    import std.stdio;
    import std.algorithm : map, sort, uniq, filter, splitter, canFind;
    import std.range : array;
    import std.exception : ifThrown;
    import colorize;

    auto opts = parseOpts(params);

    if (opts.help_triggered)
        return;

    setLogLevel(opts.logging);
    import internal.git.helper : getRemote;

    setBaseURL(opts);

    auto gc = RemoteConfig(AppName, opts.base_url, opts.assume_yes,
        opts.provider);

    auto con = HTTPConnection.connect(gc.config);
    auto repo = con.repository(getUpstream());

    auto tags = repo
        .releasedTags()
        .map!(a=>ReleaseVersion(Version.parse(a.name)).ifThrown(ReleaseVersion(InvalidVersion.init)))
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
    myrelease.metadata = opts.metadata.splitter("+").array;

    sanityCheckMilestone(con, repo, myrelease);

    ActionList list;

    with (Type) final switch (myrelease.type)
    {
        case Patch:
            auto remote_name = getRemote(AppName, getUpstream());

            list = preparePatchRelease(con, repo, tags_no_prerelease, myrelease,
                                       remote_name);
            break;
        case Minor:
            list = prepareMinorRelease(con, repo,
                options.pre_release ? tags_with_prereleases : tags_no_prerelease,
                myrelease, opts.release_subsequent);
            break;
        case Major:
            list = prepareMajorRelease(con, repo, tags_no_prerelease, myrelease);
            break;
    }

    // No actions? Stop.
    if (list == ActionList())
        return;

    writefln("Actions to be done:".color(fg.green));

    foreach (action; list.actions)
        writefln(" * %s (%s)", action.description, action.command);

    if (!getBoolChoice("\nWould you like to continue?"))
    {
        stderr.writefln("Aborting...".color(fg.red));
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
        stderr.writefln("Aborting...");
        return;
    }

    import internal.git.helper;
    import std.format;
    import std.range : chunks;

    // Push references in chunks of 3, as GitHub will not trigger
    // push hooks otherwise:
    foreach (chunk; unique_refs.chunks(3))
        cmd(["git", "push", gc.getRemote(getUpstream())] ~ array(chunk));

    writefln("Some tags on github should be released: %s",
             list.releases);

    if (!getBoolChoice("Would you like to release those tags now?"))
    {
        stderr.writefln("Aborting...");
        return;
    }

    auto issues = myrelease.type != Type.Patch ? [] :
        getIssues(con, repo.login(), repo.name());

    foreach (i, ver; list.releases)
        keepTrying(
        {
            writef("Creating %s ... ", ver);

            // Create list of issues based on the oldest release we're doing and
            // any further up until the current one
            auto relnotes = myrelease.type == Type.Patch ?
                formatPatchGithubRelease(list.releases[0..i+1], issues) :
                ver.toString.getTagMessage();

            createGithubRelease(con, repo, ver, relnotes);
        });

    import std.algorithm : filter, canFind;

    auto open_milestones = repo.listMilestones(con)
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
                    writef("Closing %s ("~"%s open issues".color(fg.red)~") ... ",
                        milestone.title.color(mode.bold), milestone.open_issues);

                    repo.updateMilestoneState(con, milestone,
                        Repository.Milestone.State.closed);
                });
        }
    }

    auto recipient = getConfig("neptune.mail-recipient").ifThrown("");

    auto email = craftMail(con, repo, myrelease.type, recipient, issues,
        list.actions
            .map!(a=>cast(ReleaseAction) a)
            .filter!(a=>a !is null)
            .array);

    writefln("This is the announcement email:\n///////\n%s\n///////", email);

    if (recipient.length == 0)
    {
        writeln("Warning: neptune.mail-recipient is empty! "
            ~ "E-mail won't be sent.".color(fg.red));
    }
    else
    {
        if (!opts.no_send_mail &&
            getBoolChoice("Would you like to send it to %s now?", recipient))
        {
            sendMail(email, recipient);
        }
    }

    writefln("All done.".color(fg.green));
}

/*******************************************************************************

    Checks if the base url was given in the options, if not extracts it from the
    upstream url

    Params:
        opts = options passed to the program

*******************************************************************************/

void setBaseURL ( ref Options opts )
{
    import internal.git.helper : getRemote;
    import release.shellHelper;
    import provider.core;
    import std.algorithm : canFind;

    if (opts.base_url.length > 0)
        return;

    auto upstream_repo = getUpstream();
    auto remote_name = getRemote(AppName, upstream_repo);
    auto remote_url = cmd("git remote get-url " ~ remote_name);
    auto domain = extractDomain(remote_url);

    if (domain.canFind("github.com"))
        opts.base_url = GitHubURL;
    else
        opts.base_url = "https://" ~ domain;
}

/*******************************************************************************

    Creates a github release, including the associated milestone link at the top

    Params:
        con = connection to use
        repo = repo to use
        ver = version to release
        notes = version notes

*******************************************************************************/

void createGithubRelease ( HTTPConnection con, Repository repo, Version ver,
                           string notes )
{
    import std.typecons;

    auto ver_str = ver.toString();

    auto mstone_link = getMilestoneLink(con, repo, ver_str);

    auto prerelease = ver.prerelease.length > 0 ?
        Yes.prerelease : No.prerelease;

    repo.createRelease(con, ver_str, ver_str, mstone_link ~ notes, prerelease);
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
    import internal.git.helper;

    import std.algorithm;
    import std.stdio;
    import std.range;
    import std.exception : enforce;

    auto mstone_list = repo.listMilestones(con).find!(a=>a.title == ver);

    if (!mstone_list.empty)
        return mstone_list.front.url ~ "?closed=1\n\n";

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
    import internal.git.helper;

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
    Type rel_type, string recipient, Issue[] issues, Range releases )
{
    import internal.git.helper;

    import provider.api.issues;

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
    string formatRelNotes ( ReleaseAction ver, Issue[] rissues )
    {
        enum inherited_str = "\n\nThis release additionally inherits changes from ";

        auto inheritance_chain = ver.prev_release
            .recurrence!((s, n)=>s[n-1] !is null ? s[n-1].prev_release : null)
            .until!(a=>a is null)
            .map!(a=>a.tag_version);

        auto filteredIssues ( )
        {
            import std.string : strip;

            return format("%-(%s\n%)", rissues
                .filter!(a=>a.json["milestone"]["title"] ==
                         ver.tag_version.toString)
                .map!(a=>format("* %s\n  %s",
                    strip(a.title()),
                    a.json["html_url"].get!string)));
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
            repo.login(), repo.name(), ver);
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
        upstream = upstream to use for local branch remotes
        branches = remote branches to create local branches from

***************************************************************************/

void createLocalBranches ( R ) ( string upstream, R branches )
{
    import release.shellHelper;
    import internal.git.helper;
    import std.format;

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
                                 Version[] tags, Version patch_version,
                                 string upstream )
{
    import release.mergeHelper;
    import release.versionHelper;

    import internal.git.helper;

    import colorize;

    import std.format;
    import std.algorithm;
    import std.range;
    import std.stdio;

    // Get version tracking branches
    auto branches = getBranches(con, repo, patch_version);

    createLocalBranches(upstream, branches);

    auto current_branch = getCurrentBranch();

    ActionList list;

    scope(exit)
        list.actions ~= new LocalAction(["git", "checkout", current_branch],
                                        format("Checkout original branch %s",
                                               current_branch.color(mode.bold)));

    auto releaser = new PatchMerger(branches, tags, patch_version.metadata);

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
    import internal.git.helper;

    import colorize;

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
                                            current_branch.toString.color(mode.bold)));
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
            auto latest_rel = tags.retro.find!(a=>
                a.major == major_branches.front.major);

            // No release? Stop then, this is an unreleased major branch
            if (latest_rel.empty)
                follow = false;
            else
            {
                // merge
                list ~= checkoutMerge(current_release, major_branches.front);

                // Checkout previous branch so we can remove the rel notes
                list.actions ~= new LocalAction(
                                 ["git", "checkout", current_branch.toString],
                                 format("Checkout previous branch %s",
                                        current_branch.toString.color(mode.bold)));

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

                auto next_release = getNextMinor(latest_rel.front);
                next_release.metadata = current_release.metadata;
                current_release = next_release;
            }
        }
        else
            follow = false;

        // Keep release notes if it is a prerelease
        if (minor_version.prerelease.length == 0)
            list ~= clearReleaseNotes();
    }
    while (follow);

    scope(exit)
    {
        current_branch = SemVerBranch(getCurrentBranch());
        list.actions ~= new LocalAction(
                                ["git", "checkout", current_branch.toString],
                                format("Checkout original branch %s", current_branch.toString.color(mode.bold)));
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
    import internal.git.helper;

    import std.algorithm : find;
    import std.range : empty;
    import std.format : format;
    import release.options;

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
            stderr.writefln("Found merges between this and the last major "~
                     "branch:\n-----\n%s\n-----\nPlease rebase the current branch and "~
                     "retry.\n", merges);
            return ActionList();
        }

        // Make sure the last major is an ancestor of this major
        if (options.check_ancestor &&
            !isAncestor(previous_major_branch.toString, current_branch.toString))
        {
            import std.stdio;
            stderr.writefln("%s is not decending from %s! Aborting!",
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
        list ~= clearReleaseNotes();

        if (next_major_rslt.empty)
        {
            list.actions ~= new LocalAction(["git", "branch", next_major.toString],
                                            format("Create next major branch %s",
                                                   next_major));
        }

        list.actions ~= new LocalAction(["git", "checkout", next_major.toString],
                                        format("Checkout next major branch %s",
                                               next_major));

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
    import std.stdio;
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

    bool isSemVerBranch ( GitRef git_ref )
    {
        try
        {
            auto _ = SemVerBranch(git_ref.name);
            return true;
        }
        catch (Exception)
            return false;
    }

    auto branches = repo.branches()
        .filter!isSemVerBranch
        .map!(a=>SemVerBranch(a.name))
        .filter!(a=>!thisVersion(a) &&
            (newerVersion(a) ||
            (same_major && ourMajorRelease(a))))
        .array();

    branches.sort();

    auto ignored_branches = repo.branches()
        .filter!(name => !isSemVerBranch(name))
        .map!(a => a.name);
    writefln("List of ignored non-semver branches: %s", ignored_branches);

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
    import release.versionHelper;
    import release.options;

    import internal.git.helper;

    import colorize;

    import std.stdio;
    import std.range;
    import std.algorithm;
    import std.exception : enforce;

    SemVerBranch current;

    try
    {
        current = SemVerBranch(getCurrentBranch());
        writefln("We are on branch %s", current);
    }
    catch (Exception exc)
    {
        throw new Exception(format("Error: %s‚ Currently checked out branch" ~
            "\"%s\" is not SemVer compatible!", exc.msg, getCurrentBranch()));
    }

    if (tags.length == 0)
        stderr.writefln(("Warning: No previous releases found. "~
                 "This should only be the case for your very first release!").color(fg.red, bg.init, mode.bold));

    auto matching_major = tags.retro.find!((a)
    {
        if (a.major != current.major)
            return false;

        if (!options.pre_release && a.prerelease.length > 0)
            return false;

        if (a.prerelease.length > 0 && !a.prerelease.startsWith(RCPrefix))
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

        if (a.prerelease.length > 0 && !a.prerelease.startsWith(RCPrefix))
            return false;

        return true;
    });

    Version rel_ver;

    sanityCheck(matching_major, matching_minor, current);

    bool detected =
        needPatchRelease(matching_major, matching_minor, current, rel_ver) ||
        needMinorRelease(matching_major, matching_minor, current, rel_ver) ||
        needMajorRelease(matching_major, matching_minor, current, rel_ver);

    enforce(detected);

    if (rel_ver.type == rel_ver.type.Patch)
        enforce(!options.pre_release,
            "Pre-releases are only allowed for upcoming minors and majors (not patch releases)");

    writefln("Detected release %s", rel_ver.toString.color(mode.bold));

    return rel_ver;
}


/*******************************************************************************

    Checks if the current state is valid. Throws if not.

    Params:
        A = result type of a search for a matching major version
        B = result type of a search for a matching minor version
        matching_major = result of a search for a matching major version
        matching_minor = result of a search for a matching minor version
        current = currently checked out branch

*******************************************************************************/

void sanityCheck ( A, B ) ( A matching_major, B matching_minor,
    SemVerBranch current )
{
    import std.exception : enforce;

    if (current.type == current.type.Minor)
    {
        enforce(!matching_major.empty,
            "No existing major version found for the current minor branch " ~
            current.toString);

        enforce(!matching_minor.empty,
            "No existing minor version found for the current minor branch " ~
            current.toString);
    }
}


/*******************************************************************************

    Accuires the upstream location

    Returns:
        the upstream

*******************************************************************************/

string getUpstream ( )
{
    import release.shellHelper;
    import internal.git.helper;
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
              .ifThrown(configureUpstream(AppName, getUpstreamFromUser()));
}


/*******************************************************************************

    Checks if the corresponding milestone exists and has no open issues.
    Warns the user on stdout if either condition is fulfilled

    Params:
        con = connection to use
        repo = repo to operate on
        ver = version to find milestone for

*******************************************************************************/

void sanityCheckMilestone ( ref HTTPConnection con, ref Repository repo,
    Version ver )
{
    import std.algorithm;
    import std.stdio;
    import std.range;

    import colorize;

    Version ver_norc = ver;

    ver_norc.prerelease = "";

    auto mstone_list = repo.listMilestones(con)
        .find!(a=>a.title == ver_norc.toStringNoMetadata());

    if (mstone_list.empty)
    {
        stderr.writefln("Warning: No corresponding milestone found for %s"
            .color(fg.red), ver_norc);
        return;
    }

    auto mstone = mstone_list.front;

    if (mstone.open_issues > 0)
    {
        stderr.writefln("Warning: Corresponding milestone still has %s open issues!"
                 .color(fg.red, bg.init, mode.bold), mstone.open_issues);
    }
}


/*******************************************************************************

    Fetches the list of issues

    Params:
        owner = owner of the repo
        repo = name of the repo

    Returns:
        issues that have a milestone

*******************************************************************************/

Issue[] getIssues ( ref HTTPConnection con, string owner, string repo )
{
    import release.shellHelper;
    import vibe.data.json;
    import std.format;
    import std.algorithm;
    import std.range;

    Issue[] issues;

    keepTrying({
        issues = con
            .listIssues(format("%s/%s", owner, repo), IssueState.Closed)
            .filter!(a=>a.json["milestone"].type == Json.Type.object)
            .array;
    });

    return issues;
}


/*******************************************************************************

    Formats patch release notes for a github release

    Params:
        vers = versions to get issues for
        issues = list of issues for the repo

    Returns:
        formatted patch release notes

*******************************************************************************/

string formatPatchGithubRelease ( Version[] vers, Issue[] issues )
{
    import vibe.data.json;
    import std.format;
    import std.algorithm;
    import std.string;

    return format("%-(%s\n%)",
        issues
            .filter!(a=>
                vers.map!(a=>a.toString())
                    .canFind(a.json["milestone"]["title"].get!string))
            .map!(a=>format("* %s #%s", strip(a.title()), a.number())));
}
