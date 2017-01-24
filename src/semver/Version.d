/*******************************************************************************

    Utility to simplify working with semantic versioning entities, including
    parsing and comparison.

    Copyright:
        Copyright (c) 2009-2016 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module semver.Version;

/**
    Describes SemVer aware version instance
 **/
struct Version
{
    /// major version number
    int major;

    /// minor version number
    int minor;

    /// patch version number
    int patch;

    /// optional pre-release string
    string prerelease;

    /// optional metadata string
    string metadata;

    /**
        Constructor to require setting all fields explicitly
     **/
    this (int major, int minor, int patch, string prerelease = "",
        string metadata = "")
    {
        this.major = major;
        this.minor = minor;
        this.patch = patch;
        this.prerelease = prerelease;
        this.metadata = metadata;
    }

    /**
        Returns:
            standard string representation of the version
     **/
    string toString ( ) const pure
    {
        import std.format;
        return format(
            "v%s.%s.%s%s%s", this.major, this.minor, this.patch,
            this.prerelease.length ? "-" ~ this.prerelease : "",
            this.metadata.length ? "+" ~ this.metadata : ""
        );
    }

    /**
        Parses version string of form vX.Y.Z

        Params:
            ver = string to parse

        Returns:
            matching Version struct

        Throws:
            Exception if string pattern doesn't match
     **/
    static Version parse ( string ver )
    {
        import std.exception : enforce;
        import std.conv;
        import std.regex;

        static verRegex = regex(r"^v?(\d+)\.(\d+)\.(\d+)(-[^+]+)?(\+.+)?$", "g");

        auto hit = ver.matchFirst(verRegex);
        enforce(!hit.empty, ver);

        auto result = Version.init;
        result.major = to!int(hit[1]);
        result.minor = to!int(hit[2]);
        result.patch = to!int(hit[3]);
        if (hit[4].length)
            result.prerelease = hit[4][1 .. $];
        if (hit[5].length)
            result.metadata   = hit[5][1 .. $];
        return result;
    }

    unittest
    {
        auto ver = Version.parse("v30.20.10");
        assert(ver.major == 30);
        assert(ver.minor == 20);
        assert(ver.patch == 10);
        assert(ver.toString() == "v30.20.10");

        ver = Version.parse("0.1.2");
        assert(ver.major == 0);
        assert(ver.minor == 1);
        assert(ver.patch == 2);
        assert(ver.toString() == "v0.1.2");

        ver = Version.parse("v1.1.1-alpha+breaking");
        assert(ver.major == 1);
        assert(ver.minor == 1);
        assert(ver.patch == 1);
        assert(ver.prerelease == "alpha", ver.prerelease);
        assert(ver.metadata == "breaking");
        assert(ver.toString() == "v1.1.1-alpha+breaking");

        import std.exception : assertThrown;
        assertThrown(Version.parse("gibberish"));
    }

    /**
        Ensures ordering according to SemVer rules
     **/
    int opCmp ( const Version rhs ) const pure
    {
        if (this.major > rhs.major)
            return 1;
        if (this.major < rhs.major)
            return -1;

        if (this.minor > rhs.minor)
            return 1;
        if (this.minor < rhs.minor)
            return -1;

        if (this.patch > rhs.patch)
            return 1;
        if (this.patch < rhs.patch)
            return -1;

        return 0;
    }

    unittest
    {
        import std.algorithm : sort;

        auto vers = [
            Version.parse("v2.2.0"),
            Version.parse("v1.3.0"),
            Version.parse("v1.2.3"),
            Version.parse("v1.2.4"),
        ];

        sort(vers);

        assert(vers == [
               Version(1, 2, 3),
               Version(1, 2, 4),
               Version(1, 3, 0),
               Version(2, 2, 0),
            ]
        );
    }

    /**
        Detects equality of versions including ones not complying to SemVer
     **/
    equals_t opEquals ( const Version rhs ) const pure
    {
        return this.tupleof[] == rhs.tupleof[];
    }

    unittest
    {
        assert(Version.parse("0.1.2") == Version(0, 1, 2));
    }
}
