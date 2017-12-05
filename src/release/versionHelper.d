/*******************************************************************************

    Helper to deal with version strings

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.versionHelper;

import semver.Version;

import std.algorithm.iteration : splitter;

/// Type of the version / branches
enum Type { Major, Minor, Patch };

/// Structure to easily deal with semver branches
struct SemVerBranch
{
    import std.typecons : Nullable;

    /// major version number
    int major;

    /// Minor version mumber
    Nullable!int minor;


    /***************************************************************************

        Constructor to make a branch struct from the major and minor values

        Params:
            major = major version
            minor = minor version, optional

    ***************************************************************************/

    this ( int major, int minor = -1 )
    {
        this.major = major;

        if (minor >= 0)
            this.minor = minor;
    }


    /***************************************************************************

        Constructor to make a semver branch struct from a string

        Params:
            ver = semver branch name (e.g. "v1.4.x" or "v1.x.x")

    ***************************************************************************/

    this ( string ver )
    {
        import std.conv;
        import std.exception : enforce;

        auto splitted = ver.splitter(".");

        if (splitted.empty || splitted.front[0] != 'v')
            throw new Exception("Invalid branch name! Expected 'v..'!");

        this.major = splitted.front["v".length..$].to!int;

        splitted.popFront;

        enforce(!splitted.empty,
            "Invalid branch name! No minor version given!");

        if (splitted.front != "x")
            this.minor = splitted.front.to!int;

        splitted.popFront;

        enforce(!splitted.empty,
            "Invalid branch name! No patch version given!");

        enforce(splitted.front == "x",
            "Invalid branch name! Expected 'x' for patch value");
    }


    /***************************************************************************

        Comparison operator

        Params:
            v = other version to compare with

        Returns:
            -1 if less, 0 if equal and +1 if higher than v

    ***************************************************************************/

    int opCmp ( ref const typeof(this) v ) const
    {
        static int nullAs0 ( Nullable!int num )
        {
            return num.isNull ? 0 : num;
        }

        if (this.major != v.major)
            return this.major - v.major;

        // Consider x > number
        if (this.minor.isNull && !v.minor.isNull)
            return 1;

        if (!this.minor.isNull && v.minor.isNull)
            return -1;

        return nullAs0(this.minor) - nullAs0(v.minor);
    }


    /***************************************************************************

        Compares against a version

        Params:
            v = version to compare against

    ***************************************************************************/

    int opCmp ( ref const Version v ) const
    {
        if (this.major != v.major)
            return this.major - v.major;

        // Consider x > number
        if (this.minor.isNull)
            return 1;

        return this.minor - v.minor;
    }


    /***************************************************************************

        Equal comparison

    ***************************************************************************/

    equals_t opEquals ( ref const typeof(this) rhs ) const
    {
        return this.opCmp(rhs) == 0;
    }


    /***************************************************************************

        Returns:
            string representation of this version structure

    ***************************************************************************/

    string toString ( ) const
    {
        import std.format;
        import std.conv;

        return format("v%s.%s.x",
                      this.major,
                      this.minor.isNull ? "x" : this.minor.to!string);
    }


    /***************************************************************************

        Returns:
            Type of this semver branch

    ***************************************************************************/

    Type type ( ) const
    {
        if (this.minor.isNull)
            return Type.Major;

        return Type.Minor;
    }
}


/// Tests extracting of version information from strings
unittest
{
    alias SMB = SemVerBranch;
    alias T = Type;

    struct V
    {
        T test_type;

        SMB ver;
        bool should_fail;
        alias ver this;
    }

    enum V[string] versions = [
        "v1.5.x" : V(T.Minor, SMB(1, 5)),
        "v3.0.x" : V(T.Minor, SMB(3, 0)),
        "v1.x.x" : V(T.Major, SMB(1)),
        "v3.x.x" : V(T.Major, SMB(3)),
        "v4.x.x-rc1" : V(T.Major, SMB(4), true),
        ];

    foreach (name, ver; versions)
    {
        SemVerBranch v;

        scope(failure)
        {
            import std.stdio;
            writefln("%s Failed: %s(%s) != %s(%s)", name, v, v.type, ver, ver.type);
        }

        try v = SemVerBranch(name);
        catch (Exception exc)
            if (ver.should_fail)
                continue;
            else
                throw exc;

        assert(v == ver);
        assert(v.type == ver.test_type);
        assert(v.toString == name);
    }
}


/// Tests sorting of versions
unittest
{
    alias V = SemVerBranch;

    enum list = [V("v1.1.x"), V("v1.x.x"), V("v3.0.x"), V("v1.0.x"),
                 V("v3.x.x"),   V("v1.2.x"), V("v2.1.x"), V("v2.0.x")];
    enum list_sorted  =
                [V("v1.0.x"), V("v1.1.x"), V("v1.2.x"), V("v1.x.x"),
                 V("v2.0.x"), V("v2.1.x"), V("v3.0.x"),   V("v3.x.x")];

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
        new_version = out param, contains the patch version to be released

    Returns:
        true if a patch release was detected

*******************************************************************************/

public bool needPatchRelease ( A, B ) ( A matching_major, B matching_minor,
                                           SemVerBranch current,
                                           out Version new_version)
{
    if (current.type != current.type.Minor)
        return false;

    if (matching_major.empty)
        return false;

    if (matching_minor.empty)
        return false;

    new_version = Version(current.major, current.minor,
                          matching_minor.front.patch+1);

    return true;
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
        new_version = out param, contains the minor version to be released

    Returns:
        true if a minor release was detected

*******************************************************************************/

public bool needMinorRelease ( A, B ) ( A matching_major, B matching_minor,
                                        SemVerBranch current,
                                        out Version new_version )
{
    import std.range;

    if (!matching_major.empty && matching_minor.empty)
    {
        new_version = getNextMinor(matching_major.front);
        return true;
    }

    return false;
}

/*******************************************************************************

    Find out the minor version that would follow 'last'.
    Considers RC releases when the according global option was given.

    Returns:
        the next minor version to release

*******************************************************************************/

public Version getNextMinor ( Version last )
{
    import release.options;
    import std.algorithm;

    int rc = 1;

    Version new_version;

    if (options.pre_release && last.prerelease.startsWith(RCPrefix))
    {
        import std.conv;

        rc = last.prerelease[RCPrefix.length .. $].to!int + 1;
        new_version.minor = last.minor;
    }
    else if (last.prerelease.length == 0)
        // Only bump minor if previous minor was not a rc, too
        new_version.minor = last.minor + 1;

    if (options.pre_release)
    {
        import std.format;
        new_version.prerelease = format("%s%s", RCPrefix, rc);
    }

    new_version.major = last.major;
    new_version.patch = 0;

    return new_version;
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
        new_version = out param, contains the major version to be released

    Returns:
        true if a major release was detected

*******************************************************************************/

public bool needMajorRelease ( A, B ) ( A matching_major, B matching_minor,
                                        SemVerBranch current,
                                        out Version new_version )
{
    import release.options;

    if (current.type != current.type.Major)
        return false;

    if (!matching_major.empty && !options.pre_release)
        return false;

    if (!matching_minor.empty)
        return false;

    new_version.major = current.major;
    new_version.minor = 0;
    new_version.patch = 0;


    if (options.pre_release)
    {
        import std.format;

        int rc = 1;

        with (matching_major) if (!empty &&
            front.prerelease.length > RCPrefix.length)
        {
            import std.conv;

            rc = front.prerelease[RCPrefix.length .. $].to!int + 1;
        }

        new_version.prerelease = format("%s%s", RCPrefix, rc);
    }

    return true;
}


/*******************************************************************************

    Deducts the type of a Version

    Params:
        ver = version to deduct type for

    Returns:
        deducted type

*******************************************************************************/

public Type type ( const ref Version ver )
{
    if (ver.patch == 0 && ver.minor == 0)
        return Type.Major;

    if (ver.patch == 0)
        return Type.Minor;

    return Type.Patch;
}
