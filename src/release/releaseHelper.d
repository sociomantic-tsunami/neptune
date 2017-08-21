/*******************************************************************************

    Helper classes & functions to do a release

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.releaseHelper;

import release.actions;
import semver.Version;

/// Specialized action to craft a release
class ReleaseAction : Action
{
    /// Release that was merged into this release
    ReleaseAction prev_release;

    /// Release version to do
    Version tag_version;

    /// Branch to release on
    string tag_reference;

    /***************************************************************************

        C'tor

        Params:
            prev = previous release that was merged into this one
            ver  = this release
            reference = branch/ref to release on

    ***************************************************************************/

    this ( ReleaseAction prev, Version ver, string reference )
    {
        this.prev_release = prev;
        this.tag_version = ver;
        this.tag_reference = reference;
    }

    /// Execute the commands to do the release
    override string execute ( )
    {
        import std.process;
        import release.gitHelper;

        string prev_relnotes;

        auto prev_tag = this.prev_release !is null ?
            this.prev_release.tag_version.toString : "";

        if (prev_tag.length > 0)
            prev_relnotes = getTagMessage(prev_tag);

        string tag_msg;

        // Patch versions don't get release notes (yet)
        if (tag_version.patch > 0)
            tag_msg = tag_version.toString;
        else
        {
            tag_msg = buildReleaseNotes(prev_tag, prev_relnotes);
        }

        assert(tag_msg.length > 0, "No release notes found?!");

        auto proc = pipeShell(this.command, Redirect.all);

        proc.stdin.write(tag_msg);
        proc.stdin.flush();
        proc.stdin.close();

        string ret, line;

        wait(proc.pid);

        while ((line = proc.stdout.readln()) !is null)
            ret ~= line;

        return ret;
    }

    /// Returns description of this action
    override string description ( ) const
    {
        import std.format;
        return format("Creating annotated tag %s", this.tag_version);
    }

    /// Returns command of this action
    override string command ( ) const
    {
        import std.format;
        return format("git tag -F- %s %s",
                      this.tag_version,
                      this.tag_reference);
    }
}

/*******************************************************************************

    Range filter function to only match files ending with the given string

    Params:
        range = range to filter
        match_str = string to filter for

    Returns:
        filtered range

*******************************************************************************/

private auto match ( R ) ( R range, string match_str )
{
    import std.algorithm;

    return range.filter!(a=>a.endsWith(match_str));
}

/*******************************************************************************

    Creates release notes, including inherited notes.

    Params:
        previous_version = the previous release which this one inherited from
        previous_notes = the previous releases' notes

    Returns:
        this release' notes

*******************************************************************************/

string buildReleaseNotes ( string previous_version, string previous_notes  )
{
    import release.gitHelper;

    import std.file;
    import std.algorithm;
    import std.format;
    import std.range;
    import std.array : join;

    import std.stdio;

    immutable MigrationHeader = "Migration Instructions\n----------------------\n\n";
    immutable DeprecationsHeader = "Deprecations\n------------\n\n";
    immutable FeaturesHeader = "Features\n--------\n\n";

    auto files = dirEntries("relnotes/", SpanMode.shallow)
                        .map!(a=>a.name)
                        .filter!(a=>previous_version.length == 0 ||
                                    !isAncestor(getLastCommitOf(a),
                                                previous_version))
                        .array;

    string getNotes ( string file )
    {
        return files.match(file)
                    .map!(a=>a.readText ~ "\n")
                    .join;
    }

    auto migrations = getNotes("migration.md");
    auto deprecations = getNotes("deprecation.md");
    auto features = getNotes("feature.md");

    if (!migrations.empty)
        migrations = MigrationHeader ~ migrations;

    if (!deprecations.empty)
        deprecations = DeprecationsHeader ~ deprecations;

    if (!features.empty)
        features = FeaturesHeader ~ features;

    if (previous_notes.length > 0 && previous_version.length > 0)
    {
        auto previous_header = "Inherited changes from " ~ previous_version;

        previous_notes = format("%s\n%s\n\n%s",
                                previous_header,
                                repeat('=', previous_header.length),
                                previous_notes);
    }

    return (migrations ~ deprecations ~ features ~ previous_notes).dup;
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
    ReleaseAction dummy;
    return makeRelease(release_version, target, dummy);
}

/*******************************************************************************

    Params:
        release_version = release version to make
        target = target reference for the release
        previous = previous release that this one is based on. Will be
                   overwritten after usage with the ActionRelease object
                   of this release

    Returns:
        an actionlist element containing all the actions/refs required to do the
        requested release

*******************************************************************************/

ActionList makeRelease ( Version release_version, string target,
                         ref ReleaseAction previous )
{
    import std.format;
    import release.versionHelper;

    auto v = release_version.toString();

    ActionList list;

    with (list)
    {
        actions ~= previous = new ReleaseAction(previous, release_version, target);
        affected_refs ~= v;
        releases ~= v;
    }

    // Is this a major or minor release?
    with (release_version) if (patch == 0)
    {
        auto branch = SemVerBranch(major, minor);

        // Create the appropriate branch
        list.actions ~= new LocalAction(format("git branch %s %s", branch, v),
                                        format("Create tracking branch %s",
                                                 branch));

        list.affected_refs ~= branch.toString;
    }

    return list;
}
