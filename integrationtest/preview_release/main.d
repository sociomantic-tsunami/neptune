/*******************************************************************************

    Tests the 'first release' scenario with the neptune-release tool

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.preview_release.main;

import integrationtest.common.GHTestServer;

import integrationtest.common.TestCase;

class InitialRelease : TestCase
{
    this ( )
    {
        super(8003);
    }

    override protected void run ( )
    {
        import semver.Version;

        this.prepareRelNotes("v0.x.x");

        with (this.fake_github)
            milestones ~= Milestone(
               10, // id
               20, // number
               "v0.1.0", // title
               "https://github.com/sociomantic/sandbox/milestone/20", // html url
               "open", // state
               0, // open issues
               0); // closed issues

        auto neptune_out = this.startNeptuneRelease();

        this.checkTerminationStatus();
        this.checkRelNotes(Version(0, 1, 0));
        this.checkTagNotes(Version(0, 1, 0));
        this.checkReleaseMail(neptune_out.stdout);

        assert(this.git.branchExists("v0.1.x"), "Tracking branch is missing!");
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
