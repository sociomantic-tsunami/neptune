/*******************************************************************************

    Command line interaction helper

    Copyright:
        Copyright (c) 2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module internal.shell.helper;

import core.time;
import std.stdio;
import std.typecons;

/// Exception to be thrown when the exit code is unexpected
class ExitCodeException : Exception
{
    int status;
    string raw_msg;

    this ( string msg, int status, string file = __FILE__, int line = __LINE__ )
    {
        import std.format;

        this.status = status;
        this.raw_msg = msg;

        super(format("Cmd Failed: %s (status %s)", msg, status), file, line);
    }
}

/*******************************************************************************

    Emulates "tail -n+<n>" (gets the lines from <n> till the end)

    This can also be seen as a line-based slice "text[n-1..$]".

    Params:
        text = text to get the tail from
        n = starting line to get from text

    Returns:
        line-sliced text

*******************************************************************************/

string linesFrom ( string text, size_t n )
{
    import std.string: splitLines, join;
    import std.typecons: Yes;
    return text
        .splitLines(Yes.keepTerminator)[n-1..$]
        .join;
}

/*******************************************************************************

    Runs a command and returns the output

    Params:
        command = command and arguments to run (as a list)

    Returns:
        output of the command

*******************************************************************************/

string cmd ( const(string[]) command )
{
    import std.process : execute;
    import std.string : strip;

    auto c = execute(command);

    if (c.status != 0)
        throw new ExitCodeException(c.output, c.status);

    return strip(c.output);
}

/*******************************************************************************

    Runs a command and returns the output

    Params:
        command = command and arguments to run (it will be split based on spaces)

    Returns:
        output of the command

*******************************************************************************/

string cmd ( string command )
{
    import std.string : split;

    return cmd(command.split);
}

/*******************************************************************************

    Asks the user about the upstream location

    Returns:
        upstream location

*******************************************************************************/

string askUpstreamName ( )
{
    import std.stdio;
    import std.string;

    writef("Please enter the upstream location: ");

    string upstream = strip(readln());

    while (upstream.length == 0)
    {
        writef("Empty input. Please enter the upstream location: ");
        upstream = strip(readln());
    }

    return upstream;
}


/*******************************************************************************

    Prompts the user for a yes or no response, returns the response.

    Params:
        assume__yes = return yes
        fmt = question to ask
        args = fields to format the question

    Returns:
        true if user decided for yes, else false

*******************************************************************************/

public bool getBoolChoice ( Args... ) ( bool assume_yes, string fmt, Args args )
{
    import std.stdio;
    import std.string;
    import colorize;

    if (assume_yes)
        return true;

    writef((fmt ~ " y/n: ").color(fg.light_blue), args);

    while (true)
    {
        auto resp = strip(readln());

        import std.ascii;

        if (resp.length > 0)
        {
           if (toLower(resp[0]) == 'y')
               return true;
           else if (toLower(resp[0]) == 'n')
               return false;
        }

        writef("Please write Y or N: ");
    }
}


/*******************************************************************************

    Reads a string from the user after asking them the given question

    Params:
        question = question to ask the user
        do_strip = whether to strip whitespaces
        allow_empty = whether to allow empty responses

*******************************************************************************/

public string readString ( string question, bool do_strip = true,
    bool allow_empty = false )
{
    import std.string;
    import std.stdio;

    writef(question);

    auto str = strip(readln());

    while (str.length == 0 && !allow_empty)
    {
        writef("Empty input. %s", question);

        str = readln();

        if (do_strip)
            str = strip(str);
        else
            str = str[0..$-1]; // only cut off the \n
    }

    return str;
}


/*******************************************************************************

    Reads a password from the user.

    Asks the user the given question, then disables terminal echo during
    password entry and then reenables it.

    Params:
        question = question to ask the user

    Returns:
        the entered password

*******************************************************************************/

public string readPassword ( string question )
{
    import core.sys.posix.termios;
    import std.stdio;

    writef(question);

    // Disable terminal echo for password entering
    termios old, _new;
    if (tcgetattr(stdout.fileno, &old) != 0)
        throw new Exception("Unable to fetch termios attr");

    _new = old;
    _new.c_lflag &= ~ECHO;

    if (tcsetattr (stdout.fileno, TCSAFLUSH, &_new) != 0)
        throw new Exception("Unable to set termios attr");

    // Reenable upon scope exit
    scope(exit)
        tcsetattr(stdout.fileno, TCSAFLUSH, &old);

    auto password = readln()[0 .. $-1];

    while (password.length == 0)
    {
        writef("Empty input. %s", question);
        password = readln()[0..$-1];
    }

    return password;
}


/*******************************************************************************

    Repeatetly tries to call dg() if it threw an exception, while also keeping
    the user informed about the attempts.

    Works visually best if the dg() function prints it's actions according to
    this pattern: "doing action abc ... " (no new line)

    The function will then add either "success\n" or "failure: reason\n".

    Params:
        dg = delegate to call until it succeeds
        printer = file to use to print normal output (defaults to stdout)
        wprinter = file to use to print error/warning output (defaults to stderr)

*******************************************************************************/

void keepTrying ( void delegate ( ) dg,
    Nullable!File outstream, Nullable!File errstream )
{
    keepTrying(dg, 10, 1.seconds, outstream, errstream);
}

/*******************************************************************************

    Repeatetly tries to call dg() if it threw an exception, while also keeping
    the user informed about the attempts.

    Works visually best if the dg() function prints it's actions according to
    this pattern: "doing action abc ... " (no new line)

    The function will then add either "success\n" or "failure: reason\n".

    Params:
        dg = delegate to call until it succeeds
        max_attempts = amount of attempts (defaults to 10)
        wait_time = time to wait between attempts (defaults to 1 second)

*******************************************************************************/

void keepTrying ( void delegate ( ) dg,
    int max_attempts = 10, Duration wait_time = 1.seconds )
{
    keepTrying(dg, max_attempts, wait_time, nullable(stdout), nullable(stderr));
}

/*******************************************************************************

    Repeatetly tries to call dg() if it threw an exception, while also keeping
    the user informed about the attempts.

    Works visually best if the dg() function prints it's actions according to
    this pattern: "doing action abc ... " (no new line)

    The function will then add either "success\n" or "failure: reason\n".

    Params:
        dg = delegate to call until it succeeds
        max_attempts = amount of attempts (defaults to 10)
        wait_time = time to wait between attempts (defaults to 1 second)
        printer = file to use to print normal output (defaults to stdout)
        wprinter = file to use to print error/warning output (defaults to stderr)

*******************************************************************************/

void keepTrying ( void delegate ( ) dg, int max_attempts, Duration wait_time,
    Nullable!File outstream, Nullable!File errstream )
{
    import core.thread;

    Exception exception;

    auto tryWritefln ( Args... ) ( Nullable!File stream, Args args )
    {
        if (!stream.isNull)
            stream.get.writefln(args);
    }

    foreach (_; 0..max_attempts) try
    {
        if (exception !is null)
            tryWritefln(errstream, "retrying ...");

        dg();

        stdout.flush();
        exception = null;
        break;
    }
    catch (Exception exc)
    {
        exception = exc;

        tryWritefln(errstream, "failed: %s", exc.msg);

        Thread.sleep(wait_time);
    }

    if (exception !is null)
    {
        tryWritefln(errstream, "Giving up after %s attempts", max_attempts);

        throw exception;
    }

    tryWritefln(outstream, "success");
}


unittest
{
    enum MaxAttempts = 10;

    void fail ( int times ) ( )
    {
        static int failnum = times;

        if (failnum-- > 0)
            throw new Exception("planned failure");
    }


    void testWith ( int Attempts ) ( )
    {
        import std.exception : ifThrown;
        import std.format;

        try keepTrying(&fail!Attempts, MaxAttempts, 0.seconds,
            Nullable!File(), Nullable!File());
        catch (Exception exc)
        {
                assert(Attempts >= MaxAttempts,
                    format("Function didn't repeat often enough! (%s)",
                        Attempts));
        }


        static if (Attempts > 0)
        {
            testWith!(Attempts-1);
        }
    }


    testWith!(MaxAttempts*2);
}
