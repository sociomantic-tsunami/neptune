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
    /// C'tor, required so that the auto parameter __FILE_FULL_PATH__ is set
    this ( ) { super(8002); }

    /// Runs the actual test
    override protected void run ( )
    {
        this.testMajor();
        this.testMinor();
    }

    /// Tests prereleases with major versions
    protected void testMajor ( )
    {
        import integrationtest.common.shellHelper;
        import std.stdio: toFile;

        this.prepareGitRepo();
        this.prepareRelNotes("v1.x.x");

        this.testReleaseCandidate(0, 1);

        // simulate some changes fo rc 2
        toFile("bla", "somefile.txt");
        git.cmd("git add somefile.txt");
        git.cmd(["git", "commit", "-m", "Add some file"]);

        this.testReleaseCandidate(0, 2);

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
        toFile("bla", "somefile.txt");
        git.cmd("git add somefile.txt");
        git.cmd(["git", "commit", "-m", "Add some file"]);
        git.cmd(`git tag -a v1.0.0 -m v1.0.0`);

        auto sha = git.cmd("git rev-parse v1.0.0");

        // Also create the release in the fake-github server
        this.fake_github.releases ~= RestAPI.Release("v1.0.0", "v1.0.0", "", sha);
        this.fake_github.tags ~= RestAPI.Tag("v1.0.0", sha);

        // Prepare for release v1.1.0
        this.prepareRelNotes("v1.x.x");

        this.testReleaseCandidate(1, 1);

        // simulate some changes fo rc 2
        toFile("bla", "somefile2.txt");
        git.cmd("git add somefile2.txt");
        git.cmd(["git", "commit", "-m", "Add some file2"]);

        this.testReleaseCandidate(1, 2);

        this.testRelease(1);
    }

    /***************************************************************************

        Test non-rc releases with the given minor version (always major v. 1)

        Params:
            minor = minor version to test

    ***************************************************************************/

    protected void testRelease ( int minor )
    {
        import std.format;

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
        this.checkRelNotes(format("v1.%s.0", minor));
        this.checkReleaseMail(stdout, format("mail-v1.%s.0.txt", minor));

        assert(this.git.branchExists(format("v1.%s.x", minor)),
               "Tracking branch shouldn't exist!");

        this.fake_github.tags ~= RestAPI.Tag(format("v1.%s.0", minor));
    }

    /***************************************************************************

        Test rc releases with the given minor and rc version (always major v. 1)

        Params:
            minor = minor version to test
            rc = release candidate version to test

    ***************************************************************************/

    protected void testReleaseCandidate ( int minor, int rc )
    {
        import std.format;

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
        this.checkRelNotes(format("v1.%s.0-rc%s", minor, rc));
        this.checkReleaseMail(stdout, format("mail-v1.%s.0-rc%s.txt", minor, rc));

        assert(!this.git.branchExists(format("v1.%s.x", minor)),
               "Tracking branch shouldn't exist!");
        assert(!this.git.branchExists(format("v1.%s.x-rc%s", minor, rc)),
               "Tracking branch shouldn't exist!");

        this.fake_github.tags ~= RestAPI.Tag(format("v1.%s.0-rc%s", minor, rc));
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
