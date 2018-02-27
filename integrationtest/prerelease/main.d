/*******************************************************************************

    Tests the 'pre-release' scenario with the neptune-release tool

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.prerelease.main;

import integrationtest.common.GHTestServer;

import integrationtest.common.TestCase;

/// PreRelease test class
class Prerelease : TestCase
{
    import semver.Version;

    struct VersionSha
    {
        Version ver;
        string sha;
    }

    /// C'tor, required so that the auto parameter __FILE_FULL_PATH__ is set
    this ( ) { super(8002); }

    /// Runs the actual test
    override protected void run ( )
    {
        this.testMajor();
        this.testMinor();
        this.testMultipleMinor();
    }

    /// Tests prereleases with major versions
    protected void testMajor ( )
    {
        import integrationtest.common.shellHelper;
        import std.stdio: toFile;

        this.prepareGitRepo();
        this.prepareRelNotes("v1.x.x");

        auto sha = git.cmd("git rev-parse v1.x.x");

        this.testReleaseCandidate(VersionSha(Version(1, 0, 0, "rc.1"), sha));

        // simulate some changes fo rc 2
        toFile("bla", git ~ "/somefile.txt");
        git.cmd("git add somefile.txt");
        git.cmd(["git", "commit", "-m", "Add some file"]);

        sha = git.cmd("git rev-parse v1.x.x");

        this.testReleaseCandidate(VersionSha(Version(1, 0, 0, "rc.2"), sha));

        this.testRelease(0);
    }

    /// Tests prereleases with minor versions
    protected void testMinor ( )
    {
        import integrationtest.common.shellHelper;
        import std.stdio: toFile;

        this.prepareGitRepo();
        this.fake_github.reset();

        // Create a v1.0.0 dummy
        git.cmd("git checkout -B v1.x.x");
        toFile("bla", git ~ "/somefile.txt");
        git.cmd("git add somefile.txt");
        git.cmd(["git", "commit", "-m", "Add some file"]);
        git.cmd(["git", "tag", "-a", "v1.0.0", "-m", "v1.0.0"]);
        git.cmd(["git", "tag", "-a", "v1.0.0-norc", "-m", "v1.0.0-norc"]);

        auto sha = git.cmd("git rev-parse v1.0.0");

        // Also create the release in the fake-github server
        this.fake_github.releases ~= RestAPI.Release("v1.0.0", "v1.0.0", "", sha);
        this.fake_github.releases ~= RestAPI.Release("v1.1.0-norc", "v1.1.0-norc", "", sha);
        this.fake_github.tags ~= RestAPI.Ref("v1.0.0", sha);
        this.fake_github.tags ~= RestAPI.Ref("v1.1.0-norc", sha);

        // Prepare for release v1.1.0
        this.prepareRelNotes("v1.x.x");

        sha = git.cmd("git rev-parse HEAD");

        this.testReleaseCandidate(VersionSha(Version(1, 1, 0, "rc.1"), sha));

        // simulate some changes fo rc 2
        toFile("bla", git ~ "/somefile2.txt");
        git.cmd("git add somefile2.txt");
        git.cmd(["git", "commit", "-m", "Add some file2"]);

        sha = git.cmd("git rev-parse HEAD");

        this.testReleaseCandidate(VersionSha(Version(1, 1, 0, "rc.2"), sha));

        this.testRelease(1);
    }

    /// Tests prereleases with minors on multiple majors
    protected void testMultipleMinor ( )
    {
        import integrationtest.common.shellHelper;
        import std.stdio: toFile;

        this.prepareGitRepo();
        this.fake_github.reset();

        // Create a v1.0.0 dummy
        git.cmd("git checkout -B v1.x.x");
        toFile("bla", git ~ "/somefile.txt");
        git.cmd("git add somefile.txt");
        git.cmd(["git", "commit", "-m", "Add some file"]);
        git.cmd(`git tag -a v1.0.0 -m v1.0.0`);

        auto sha1 = git.cmd("git rev-parse v1.0.0");

        // Create a v2.0.0 dummy
        git.cmd("git checkout -B v2.x.x");
        toFile("bla2", git ~ "/somefile.txt");
        git.cmd("git add somefile.txt");
        git.cmd(["git", "commit", "-m", "Add some file2"]);
        git.cmd(`git tag -a v2.0.0 -m v2.0.0`);

        auto sha2 = git.cmd("git rev-parse v2.0.0");

        git.cmd("git checkout v1.x.x");

        // Also create the release in the fake-github server
        this.fake_github.releases ~= RestAPI.Release("v1.0.0", "v1.0.0", "", sha1);
        this.fake_github.tags ~= RestAPI.Ref("v1.0.0", sha1);
        this.fake_github.releases ~= RestAPI.Release("v2.0.0", "v2.0.0", "", sha2);
        this.fake_github.tags ~= RestAPI.Ref("v2.0.0", sha2);
        this.fake_github.branches ~= RestAPI.Ref("v1.x.x", sha1);
        this.fake_github.branches ~= RestAPI.Ref("v2.x.x", sha2);

        // Prepare for release v1.1.0
        this.prepareRelNotes("v1.x.x");

        import std.format;
        import semver.Version;
        this.testReleaseCandidate(VersionSha(Version(1, 1, 0, "rc.1"), sha1),
                                  VersionSha(Version(2, 1, 0, "rc.1"), sha2));

        // simulate some changes fo rc 2
        toFile("bla", git ~ "/somefile2.txt");
        git.cmd("git add somefile2.txt");
        git.cmd(["git", "commit", "-m", "Add some file2"]);

        this.testReleaseCandidate(VersionSha(Version(1, 1, 0, "rc.2"), sha1),
                                  VersionSha(Version(2, 1, 0, "rc.2"), sha2));

        this.testRelease(1, 1, 2);
    }

    /***************************************************************************

        Test non-rc releases with the given minor version (always major v. 1)

        Params:
            minor = minor version to test

    ***************************************************************************/

    protected void testRelease ( int minor, int[] majors... )
    {
        import std.format;

        if (majors.length == 0)
            majors ~= 1;

        auto neptune = this.startNeptuneRelease();

        // Capture stdout/stderr
        string stdout = getAsyncStream(neptune.stdout);
        string stderr = getAsyncStream(neptune.stderr);

        scope(failure)
        {
            import std.stdio;

            writefln("Failure! Neptune output was:\n------\n%s\n-----\n%s",
                     stderr, stdout);
        }

        this.checkTerminationStatus();
        this.checkRelNotes(Version(1, minor, 0));
        this.checkReleaseMail(stdout, format("mail-v%(%s,%).%s.0.txt", majors, minor));

        assert(this.git.branchExists(format("v1.%s.x", minor)),
               "Tracking branch shouldn't exist!");

        this.fake_github.tags ~= RestAPI.Ref(format("v1.%s.0", minor));
    }

    /***************************************************************************

        Test rc releases with the given minor and rc version (always major v. 1)

        Params:
            vers = Versions and their sha value to test

    ***************************************************************************/

    protected void testReleaseCandidate ( VersionSha[] vers... )
    {
        import std.format;
        import std.range;
        import std.algorithm;


        auto neptune = this.startNeptuneRelease("--pre-release");

        // Capture stdout/stderr
        string stdout = getAsyncStream(neptune.stdout);
        string stderr = getAsyncStream(neptune.stderr);

        scope(failure)
        {
            import std.stdio;

            writefln("Failure! Neptune output was:\n------\n%s\n-----\n%s",
                     stderr, stdout);
        }

        this.checkTerminationStatus();

        import std.stdio;

        foreach (i, ver; vers)
        {
            string relnote_file;

            if (ver.ver.major > 1)
            {
                relnote_file = format("%s/relnotes.%s.md",
                    this.data, ver.ver.prerelease);
            }

            this.checkRelNotes(ver.ver, relnote_file);
        }

        this.checkReleaseMail(stdout,
            format("mail-v%(%s,%).%s.0-%s.txt",
                vers.map!(a=>a.ver.major),
                vers.front.ver.minor, // all vers should have the same minor
                vers.front.ver.prerelease)); // and the same prerelease

        assert(!this.git.branchExists(format("v1.%s.x", vers.front.ver.minor)),
               "Tracking branch shouldn't exist!");
        assert(!this.git.branchExists(
            format("v1.%s.x-%s",
                vers.front.ver.minor,
                vers.front.ver.prerelease)),
            "Tracking branch shouldn't exist!");

        foreach (ver; vers)
            if (ver.sha.length > 0)
                this.fake_github.tags ~= RestAPI.Ref(ver.ver.toString, ver.sha);
    }
}

/*******************************************************************************

    Main function, sets up tests instance

*******************************************************************************/

version(UnitTest) {} else
void main ( )
{
    auto test = new Prerelease();

    test.startTest();
}
