/*******************************************************************************

    Tests the 'first release' scenario with the neptune-release tool

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.first_release.main;

import integrationtest.common.GHTestServer;

import integrationtest.common.TestCase;

import integrationtest.common.shellHelper;

class InitialRelease : TestCase
{
    this ( )
    {
        super(8001);
    }

    override protected void run ( )
    {
        import semver.Version;

        git.cmd("git checkout -B nonsemver");
        this.prepareRelNotes("v1.x.x");

        with (this.fake_github)
            milestones ~= Milestone(
               10, // id
               20, // number
               "v1.0.0", // title
               "https://github.com/sociomantic/sandbox/milestone/20", // html url
               "open", // state
               0, // open issues
               0); // closed issues

        auto output = this.startNeptuneRelease();

        this.checkTerminationStatus();
        this.checkRelNotes(Version(1, 0, 0));
        this.checkTagNotes(Version(1, 0, 0));
        this.checkReleaseMail(output.stdout);

        assert(this.git.branchExists("v1.0.x"), "Tracking branch is missing!");
    }
}

/*******************************************************************************

    Main function, sets up tests & runs event loop

*******************************************************************************/

version(UnitTest) {} else
void main ( )
{
    auto test = new InitialRelease();

    test.startTest();
}
