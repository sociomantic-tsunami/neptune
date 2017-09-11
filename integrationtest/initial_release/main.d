/*******************************************************************************

    Tests the 'first release' scenario with the neptune-release tool

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.initial_release.main;

import integrationtest.initial_release.GHTestServer;
import vibe.web.rest;
import vibe.http.router;

/// Set to true if the test failed
bool failed;

/*******************************************************************************

    Main function, sets up tests & runs event loop

*******************************************************************************/

version(UnitTest) {} else
void main ( )
{
    import vibe.core.core;
    import std.stdio;

    RestAPI gh_test;


    auto router = new URLRouter;
	router.registerRestInterface(gh_test = new RestAPI);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	listenHTTP(settings, router);

    import std.functional : toDelegate;

    auto task = runTask(toDelegate(&runNeptune), gh_test);

    runEventLoop();

    task.join();

    assert(!failed);
}

/*******************************************************************************

    Runs the test

    Params:
        gh_test = github mockup server instance

*******************************************************************************/

void runNeptune ( RestAPI gh_test )
{
    import integrationtest.initial_release.shellHelper;

    import vibe.core.core;
    import vibe.core.args;

    import std.stdio;
    import std.process;
    import std.format;

    import core.time;

    enum GitRepo = "tester/sandbox";
    enum GitPath = "github.com:" ~ GitRepo;

    scope(failure)
        failed = true;

    scope(exit)
        exitEventLoop();

    auto tmp = readRequiredOption!string("tmp", "Temporary directory");
    auto bin = readRequiredOption!string("bin", "Binary directory");
    auto data = __FILE_FULL_PATH__[0 .. $-"main.d".length] ~ "data";

    auto git = tmp ~ "/" ~ GitPath;

    tmp.cmd("rm -rf " ~ GitPath);
    tmp.cmd("mkdir -p " ~ GitPath);
    git.cmd("git init");
    git.cmd("git config neptune.upstream " ~ GitRepo);
    git.cmd("git config neptune.oauthtoken 0000");
    // avoid side effects
    git.cmd("git config commit.gpgSign false");
    git.cmd("git config neptune.mail-recipient dummy@notexisting.example");
    git.cmd("git remote add origin " ~ git);

    git.cmd("git checkout -B v1.x.x");

    git.cmd(format("cp -r %s/relnotes ./", data));

    git.cmd("git add relnotes");
    git.cmd(`git commit -m "Add rel notes"`);

    auto neptune = pipeProcess([format("%s/neptune-release", bin),
                               "--assume-yes=true",
                               "--no-send-mail",
                               "--verbose",
                               "--base-url=http://127.0.0.1:8080"],
                               Redirect.all, null, Config.none, git);

    bool killed = false;

    void timeout ( )
    {
        kill(neptune.pid);
        killed = true;
    }

    // fallback timeout timer
    setTimer(10.seconds, &timeout);


    // Capture stdout/stderr
    string ret, line, stdout, stderr;
    {
        import vibe.stream.stdio;
        import vibe.stream.operations;

        auto _stdout = new StdFileStream(true, false);
        auto _stderr = new StdFileStream(true, false);

        _stdout.setup(neptune.stdout);
        _stderr.setup(neptune.stderr);

        stderr = _stderr.readAllUTF8();
        stdout = _stdout.readAllUTF8();
    }

    scope(failure)
    {
        writefln("Failure! Neptune output was:\n------\n%s\n-----\n%s",
                 stderr, stdout);
    }

    // Check if neptune timed out
    assert(!killed);


    auto w = neptune.pid.tryWait();

    // Check for correct termination status
    assert(w.terminated);
    assert(w.status == 0);

    import std.stdio;
    import std.string : strip;
    import std.algorithm : startsWith, findSplitAfter, findSplitBefore;
    import std.range : empty;

    // Check for correct release notes file
    const(char)[] correct_relnotes;
    {
        auto file = File(format("%s/relnotes.md", data), "r");
        auto fsize = file.size();
        assert(fsize < 1024 * 16, "relnotes file unexpectedly large!");

        correct_relnotes = strip(file.rawRead(new char[fsize]));
        auto test_relnotes = strip(gh_test.releases[0].content);

        assert(correct_relnotes == test_relnotes);
    }


    // Check for correct tag text
    {
        auto tagmsg = git.cmd("git cat-file v1.0.0 -p | tail -n+6");
        assert(tagmsg.startsWith(correct_relnotes));
    }


    // Check for correct release email
    {
        auto begin = stdout.findSplitAfter("This is the announcement email:\n-----\n");
        auto skip_first = begin[1].findSplitAfter("\n");
        auto content = skip_first[1].findSplitBefore("-----\nAll done.");

        assert(!begin[1].empty);
        assert(!skip_first[1].empty);
        assert(!content[1].empty);

        auto test_mail = strip(content[0]);
        auto correct_mail = git.cmd(format("tail %s/mail.txt -n+2", data));
        assert(test_mail == correct_mail);
    }
}
