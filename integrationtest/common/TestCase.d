/*******************************************************************************

    Test Case Base Class.

    Common functionality used by all tests.

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.common.TestCase;

import integrationtest.common.shellHelper;

import std.stdio : File;

// Hack to make rdmd report dependencies properly
static import lib.shell.helper;

/// TestCase from which other tests can derive
class TestCase
{
    import integrationtest.common.GHTestServer : RestAPI;
    import std.process;

    enum GitRepo = "tester/sandbox";
    enum GitPath = "github.com:" ~ GitRepo;

    /// Temporary dir
    protected string tmp;

    /// Binary dir
    protected string bin;

    /// Data dir
    protected string data;

    /// Git repo dir
    protected string git;

    /// Shared data dir
    protected string common_data;

    /// Set to true if the test failed
    protected bool failed;

    /// Set to true if the timeout killed neptune
    protected bool killed;

    /// Pid of the neptune process
    protected Pid neptune_pid;

    /// Fake Github Class
    protected RestAPI fake_github;

    /// Port to use for github server
    protected ushort gh_port;

    /***************************************************************************

        C'tor

        Params:
            gh_port = port to use for github
            test_file = path to the main.d file of the test

    ***************************************************************************/

    public this ( ushort gh_port, string test_file = __FILE_FULL_PATH__ )
    {
        import vibe.core.args;
        import vibe.web.rest;
        import vibe.http.router;
        import std.format;
        import std.random;

        this.tmp = format("%s/%x",
            readRequiredOption!string("tmp", "Temporary directory"),
            uniform!ulong());

        "/usr/bin".cmd("mkdir " ~ this.tmp);

        this.gh_port = gh_port;

        assert(this.gh_port != 0);

        this.bin = readRequiredOption!string("bin", "Binary directory");
        this.data = test_file[0 .. $-"main.d".length] ~ "data";
        this.common_data = __FILE_FULL_PATH__[0 .. $-"TestCase.d".length] ~ "data";
        this.git = this.tmp ~ "/" ~ GitPath;


        auto router = new URLRouter;
        router.registerRestInterface(this.fake_github = new RestAPI);

        auto settings = new HTTPServerSettings;
        settings.port = this.gh_port;
        listenHTTP(settings, router);

        this.prepareGitRepo();
    }

    /// Starts the test task
    public void startTest ( )
    {
        import vibe.core.core;

        auto task = runTask(&this.internalRun);

        runEventLoop();

        task.join();

        assert(!this.killed, "Neptune process timed out!");
        assert(!this.failed, "Test failed!");
    }

    /// Runs the test and stops the eventloop on exit
    private void internalRun ( )
    {
        import vibe.core.core;

        scope(exit)
            exitEventLoop();

        scope(failure)
            this.failed = true;

        this.run();
    }

    /// child-class implemented test run function
    abstract protected void run ( );

    /// Sets up the git repository
    protected void prepareGitRepo ( )
    {
        this.tmp.cmd("rm -rf " ~ GitPath);
        this.tmp.cmd("mkdir -p " ~ GitPath);

        git.cmd("git init");

        git.cmd("git config neptune.upstream " ~ GitRepo);
        git.cmd("git config neptune.upstreamremote origin");
        git.cmd("git config neptune.oauthtoken 0000");
        git.cmd("git config user.name Tes Ter");
        git.cmd("git config user.email tester@notexisting.example");
        git.cmd("git config neptune.mail-recipient dummy@notexisting.example");

        git.cmd("git remote add origin " ~ this.git);
    }

    /***************************************************************************

        Adds release notes to the test git repo

        Params:
            branch = branch to add release notes to

    ***************************************************************************/

    protected void prepareRelNotes ( string branch )
    {
        import std.format;

        git.cmd(["git", "checkout", "-B", branch]);

        git.cmd(["cp", "-r", this.common_data ~ "/relnotes",  "./"]);

        git.cmd("git add relnotes");
        git.cmd(["git", "commit", "-m", "Add rel notes"]);
    }

    /***************************************************************************

        Starts the neptune-release process.
        Uses a set of default parameters and overwrites $HOME to be the same as
        the git directory

        Any desired additional parameters can simply be passed as strings to
        this function.

        If the instance is running for more than 10 seconds, it will be
        force-killed and this.killed will be set to true.

        Params:
            args... = further parameters forwarded to neptune-release

        Returns:
            PipeProcess object associated with the neptune instance

    ***************************************************************************/

    protected auto startNeptuneRelease ( Args... ) ( Args args )
    {
        import vibe.core.core;
        import std.format;
        import core.time;

        auto neptune = pipeProcess([format("%s/neptune-release", this.bin),
                               args,
                               "--assume-yes=true",
                               "--no-send-mail",
                               "--verbose",
                               format("--base-url=http://127.0.0.1:%s",
                                   this.gh_port)],
                               Redirect.all, ["HOME" : this.git],
                               Config.none, this.git);

        this.neptune_pid = neptune.pid;

        setTimer(10.seconds, &this.neptuneTimeout);

        return neptune;
    }

    /// Timer callback to kill neptune-process
    protected void neptuneTimeout ( )
    {
        kill(this.neptune_pid);
        this.failed = true;
    }

    /// Validates the release notes in the TAG and github
    protected void checkRelNotes ( string ver, string path = "" )
    {
        import std.format;
        import std.string : strip;
        import std.algorithm : startsWith, find;
        import std.range : empty, front;

        if (path == "")
            path = format("%s/relnotes.md", this.common_data);

        // Check for correct release notes file
        const(char)[] correct_relnotes;
        {
            auto file = File(path, "r");
            auto fsize = file.size();
            assert(fsize < 1024 * 16, "relnotes file unexpectedly large!");

            correct_relnotes = strip(file.rawRead(new char[fsize]));

            auto gh_rel = this.fake_github.releases.find!(a=>a.name == ver);
            assert(!gh_rel.empty, "Release "~ ver ~" not found on gh fake server!");

            auto test_relnotes = strip(gh_rel.front.content);

            assert(correct_relnotes == test_relnotes);
        }

        // Check for correct tag text
        {
            import lib.shell.helper : linesFrom;
            auto tagmsg =
                linesFrom(this.git.cmd(["git", "cat-file", ver, "-p"]), 6);

            assert(tagmsg.startsWith(correct_relnotes));
        }
    }

    /***************************************************************************

        Validates the release mail

        Params:
            stdout = stdout from neptune-process
            file = file that contains correct email

    ***************************************************************************/

    protected void checkReleaseMail ( string stdout, string file = "mail.txt" )
    {
        import lib.shell.helper : linesFrom;
        import std.algorithm : findSplitAfter, findSplitBefore;
        import std.file : readText;
        import std.range : empty;
        import std.string : strip;
        import std.format;

        auto begin = stdout.findSplitAfter("This is the announcement email:\n///////\n");
        auto skip_first = begin[1].findSplitAfter("\n");
        auto content = skip_first[1].findSplitBefore("///////\n");

        assert(!begin[1].empty);
        assert(!skip_first[1].empty);
        assert(!content[1].empty);

        auto test_mail = content[0];
        auto correct_mail = readText(data ~ "/" ~ file).linesFrom(2);
        if (test_mail != correct_mail)
        {
            import std.stdio;
            writeln("Generated Email is incorrect");
            writeln("--------------------- bad --------------------------");
            write(test_mail);
            writeln("--------------------- good -------------------------");
            write(correct_mail);
            writeln("--------------------- end --------------------------");
            assert(false);
        }
    }

    /// Checks the termination status & code of neptune-process
    protected void checkTerminationStatus ( )
    {
        auto w = this.neptune_pid.tryWait();

        // Check for correct termination status
        assert(w.terminated);
        assert(w.status == 0);
    }
}

/*******************************************************************************

    Asynchronously reads a file stream stream

    Params:
        stream = file stream to read

    Returns:
        text of the file stream

*******************************************************************************/

public string getAsyncStream ( File stream )
{
    import vibe.stream.stdio;
    import vibe.stream.operations;

    auto stdstream = new StdFileStream(true, false);

    stdstream.setup(stream);

    return stdstream.readAllUTF8();
}

/*******************************************************************************

    Checks if the given branch exists

    Params:
        wd = working directory to use
        branch = branch to check for

    Returns:
        true if branch exists, else false

*******************************************************************************/

public bool branchExists ( string wd, string branch )
{
    import std.format;

    int status;

    wd.cmd(format("git rev-parse --verify %s", branch), status);

    // 0 means local branch with <branch-name> exists.
    return status == 0;
}
