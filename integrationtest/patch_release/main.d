/*******************************************************************************

    Tests the 'first release' scenario with the neptune-release tool

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.patch_release.main;

import integrationtest.common.GHTestServer;

import integrationtest.common.TestCase;

import integrationtest.common.shellHelper;

class PatchRelease : TestCase
{
    this ( )
    {
        super(8004);
    }

    override protected void run ( )
    {
        import std.stdio: toFile;
        import semver.Version;

        // Create a v1.0.0 dummy
        git.cmd("git checkout -B v1.x.x");
        toFile("bla", git ~ "/somefile.txt");
        git.cmd("git add somefile.txt");
        git.cmd(["git", "commit", "-m", "Add some file"]);
        git.cmd(`git tag -a v1.0.0 -m v1.0.0`);

        auto sha1 = git.cmd("git rev-parse v1.0.0");

        with (this.fake_github)
        {
            import std.typecons;
            import std.range;

            // Also create the release in the fake-github server
            releases ~= Release("v1.0.0", "v1.0.0", "", sha1);
            tags ~=     Ref("v1.0.0", sha1);
            branches ~= Ref("v1.x.x", sha1);
            branches ~= Ref("v1.0.x", sha1);

            milestones ~= Milestone(
               10, // id
               20, // number
               "v1.0.1", // title
               "https://github.com/sociomantic/sandbox/milestone/20", // html url
               "open", // state
               0, // open issues
               3); // closed issues

            issues = [
                Issue(
                    "Terrible bug", // title
                    55, // number
                    "closed", // state
                    "https://github.com/tester/sandbox/issues/55",
                    nullable(milestones.front)),
                Issue(
                    "Sneaky bug", // title
                    56, // number
                    "closed", // state
                    "https://github.com/tester/sandbox/issues/56",
                    nullable(milestones.front)),
                Issue(
                    "Obvious bug", // title
                    57, // number
                    "closed", // state
                    "https://github.com/tester/sandbox/issues/57",
                    nullable(milestones.front)),
                Issue(
                    "Unrelated bug", // title
                    58, // number
                    "open", // state
                    "https://github.com/tester/sandbox/issues/58",
                    Nullable!Milestone()),
                Issue(
                    "Completely unrelated bug", // title
                    59, // number
                    "closed", // state
                    "https://github.com/tester/sandbox/issues/59",
                    Nullable!Milestone())
                    ];
        }

        git.cmd("git checkout -B v1.0.x");


        auto neptune_out = this.startNeptuneRelease();

        this.checkTerminationStatus();
        this.checkRelNotes(Version(1, 0, 1), this.data ~ "/relnotes.md");
        this.checkTagNotes(Version(1, 0, 1), this.data ~ "/tagnotes.md");
        this.checkReleaseMail(neptune_out.stdout);

        assert(this.fake_github.milestones[0].state == "closed");
    }
}

/*******************************************************************************

    Main function, sets up tests & runs event loop

*******************************************************************************/

version(UnitTest) {} else
void main ( )
{
    auto test = new PatchRelease();

    test.startTest();
}
