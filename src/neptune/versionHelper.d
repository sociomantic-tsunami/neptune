/*******************************************************************************

    Helper to deal with version strings

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module neptune.versionHelper;

import std.algorithm.iteration : splitter;
import octod.api.repos : Tag;

/// Structure to easily deal with version strings
struct Version
{
    import std.typecons : Nullable;

    /// Type of the version
    enum Type { Major, Minor, Patch, Invalid };

    /// Type of this version
    Type type;

    /// Major, minor and patch version numbers
    Nullable!int major, minor, patch;

    /// Any extra letters to the version (e.g. -preview, -breaking)
    string extra;


    /***************************************************************************

        Constructor to make a version struct from the major, minor and patch
        values

        Params:
            type = type of the version
            major = major version
            minor = minor version, optional
            patch = patch version, optional
            extra = any extra string following the version

    ***************************************************************************/

    this ( Type type, int major, int minor = -1, int patch = -1,
           string extra = "" )
    {
        this.type = type;
        this.major = major;

        if (minor >= 0)
            this.minor = minor;

        if (patch >= 0)
            this.patch = patch;

        this.extra = extra;
    }


    /***************************************************************************

        Constructor to make a version struct from a string

        Params:
            ver = version string (e.g. "v1.4.2" or "v1.x.x")

    ***************************************************************************/

    this ( string ver )
    {
        import std.conv;

        auto splitted = ver.splitter(".");

        if (splitted.empty || splitted.front[0] != 'v')
            return;

        this.major = splitted.front["v".length..$].to!int;
        this.type = Type.Major;

        splitted.popFront;

        if (splitted.empty)
            return;

        if (splitted.front != "x")
        {
            this.minor = splitted.front.to!int;

            this.type = Type.Minor;
        }
        else
            return;

        splitted.popFront;

        if (splitted.empty)
            return;

        if (splitted.front != "x")
        {
            import std.algorithm.searching : findSplit;
            auto res = splitted.front.findSplit("-");

            this.patch = res[0].to!int;
            this.extra = res[2];

            if (this.patch > 0)
                this.type = Type.Patch;
        }

        if (this.minor == 0 && this.patch == 0)
            this.type = Type.Major;
    }


    /***************************************************************************

        Comparison operator

        Params:
            v = other version to compare with

        Returns:
            -1 if less, 0 if equal and +1 if higher than v

    ***************************************************************************/

    int opCmp ( ref const Version v ) const
    {
        int nullAs0 ( Nullable!int num )
        {
            return num.isNull ? 0 : num;
        }

        if (this.major != v.major)
            return nullAs0(this.major) - nullAs0(v.major);

        if (this.minor != v.minor)
            return nullAs0(this.minor) - nullAs0(v.minor);

        return nullAs0(this.patch) - nullAs0(v.patch);
    }

    /***************************************************************************

        Returns:
            string representation of this version structure

    ***************************************************************************/

    string toString ( ) const
    {
        import std.format;
        import std.conv;

        return format("v%s.%s.%s%s",
                      this.major,
                      this.minor.isNull ? "x" : this.minor.to!string,
                      this.patch.isNull ? "x" : this.patch.to!string,
                      this.extra.length > 0 ? "-" ~ this.extra : "");
    }
}


/// Tests extracting of version information from strings
unittest
{
    alias V = Version;
    alias T = Version.Type;

    enum V[string] versions = [
        "v1.5.3" : V(V.Type.Patch, 1, 5, 3),
        "v1.5.x" : V(V.Type.Minor, 1, 5),
        "v3.0.x" : V(V.Type.Minor, 3, 0),
        "v1.x.x" : V(V.Type.Major, 1),
        "v1.5.0" : V(V.Type.Minor, 1, 5, 0),
        "v1.0.0" : V(V.Type.Major, 1, 0, 0),
        "v1.0.1" : V(V.Type.Patch, 1, 0, 1),
        "v1.1.0" : V(V.Type.Minor, 1, 1, 0),
        "v1.5.3" : V(V.Type.Patch, 1, 5, 3),
        "v1.5.3-preview" : V(V.Type.Patch, 1, 5, 3, "preview"),
        ];

    foreach (name, ver; versions)
    {
        auto v = Version(name);

        scope(failure)
        {
            import std.stdio;
            writefln("Failed: %s(%s) != %s(%s)", v, v.type, ver, ver.type);
        }

        assert(v == ver);
    }
}


/// Tests sorting of versions
unittest
{
    alias V = Version;

    enum list = [V("v1.1.0"), V("v1.0.1"), V("v3.0.1"), V("v1.0.0"),
                 V("v3.0"),   V("v1.1.1"), V("v2.0.1"), V("v2.0.0")];
    enum list_sorted  =
                [V("v1.0.0"), V("v1.0.1"), V("v1.1.0"), V("v1.1.1"),
                 V("v2.0.0"), V("v2.0.1"), V("v3.0"),   V("v3.0.1")];

    import std.range;
    import std.algorithm;

    auto list_mutated = sort(list.dup);

    assert(equal(list_sorted, list_mutated));
}


/*******************************************************************************

    Checks if the current state suggests a patch release.

    Uses the existing tags and the current branch.

    Params:
        A = result type of a search for a matching major version
        B = result type of a search for a matching minor version
        matching_major = result of a search for a matching major version
        matching_minor = result of a search for a matching minor version
        current = currently checked out branch

    Returns:
        a version with type set to Invalid if we guess it will not be a patch
        release

*******************************************************************************/

public Version needPatchRelease ( A, B ) ( A matching_major, B matching_minor,
                                           Version current )
{
    auto invalid = Version(Version.Type.Invalid, 0);

    if (current.type != current.type.Minor)
        return invalid;

    if (matching_major.empty)
        return invalid;

    if (matching_minor.empty)
        return invalid;

    return Version(Version.Type.Patch, current.major, current.minor,
                   matching_minor.front.patch+1);
}


/*******************************************************************************

    Checks if the current state suggests a minor release.

    Uses the existing tags and the current branch.

    Params:
        A = result type of a search for a matching major version
        B = result type of a search for a matching minor version
        matching_major = result of a search for a matching major version
        matching_minor = result of a search for a matching minor version
        current = currently checked out branch

    Returns:
        a version with type set to Invalid if we guess it will not be a minor
        release

*******************************************************************************/

public Version needMinorRelease ( A, B ) ( A matching_major, B matching_minor,
                                           Version current )
{
    import std.algorithm;
    import std.range;
    import std.stdio;

    if (!matching_major.empty && matching_minor.empty)
        with (matching_major.front)
        {
            return Version(Version.Type.Minor, major, minor+1, 0);
        }

    return Version(Version.Type.Invalid, 0);
}


/*******************************************************************************

    Checks if the current state suggests a major release.

    Uses the existing tags and the current branch.

    Params:
        A = result type of a search for a matching major version
        B = result type of a search for a matching minor version
        matching_major = result of a search for a matching major version
        matching_minor = result of a search for a matching minor version
        current = currently checked out branch

    Returns:
        a version with type set to Invalid if we guess it will not be a major
        release

*******************************************************************************/

public Version needMajorRelease ( A, B ) ( A matching_major, B matching_minor,
                                           Version current )
{
    auto invalid = Version(Version.Type.Invalid, 0);

    if (current.type != current.type.Major)
        return invalid;

    if (!matching_major.empty)
        return invalid;

    if (!matching_minor.empty)
        return invalid;

    return Version(Version.Type.Major, current.major, 0, 0);
}
