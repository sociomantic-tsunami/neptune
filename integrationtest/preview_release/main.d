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
        this.prepareRelNotes("v0.x.x");

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
        this.checkRelNotes("v0.1.0");
        this.checkReleaseMail(stdout);

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
