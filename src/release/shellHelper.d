/*******************************************************************************

    Command line interaction helper

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.shellHelper;

import core.time;
import std.stdio;

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

    Runs a command and returns the output

    Params:
        command = command to run

    Returns:
        output of the command

*******************************************************************************/

string cmd ( string command )
{
    import std.process : executeShell;
    import std.string : strip;

    auto c = executeShell(command);

    if (c.status != 0)
        throw new ExitCodeException(c.output, c.status);

    return strip(c.output);
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
    Respects global assume_yes option and skips user interaction in that case.

    Params:
        fmt = question to ask
        args = fields to format the question

    Returns:
        true if user decided for yes, else false

*******************************************************************************/

public bool getBoolChoice ( Args... ) ( string fmt, Args args )
{
    import std.stdio;
    import std.string;
    import release.options;

    if (options.assume_yes)
        return true;

    writef(fmt ~ " y/n: ", args);

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
        max_attempts = amount of attempts (defaults to 10)
        wait_time = time to wait between attempts (defaults to 1 second)
        printer = function to use to print output (defaults to stdout)

*******************************************************************************/

void keepTrying ( alias printer = writefln ) ( void delegate ( ) dg,
    int max_attempts = 10, Duration wait_time = 1.seconds )
{
    import core.thread;

    Exception exception;

    foreach (_; 0..max_attempts) try
    {
        if (exception !is null)
            printer("retrying ...");

        dg();

        stdout.flush();
        exception = null;
        break;
    }
    catch (Exception exc)
    {
        exception = exc;

        printer("failed: %s", exc.msg);

        Thread.sleep(wait_time);
    }

    if (exception !is null)
    {
        printer("Giving up after %s attempts", max_attempts);
        throw exception;
    }

    printer("success");
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

        try keepTrying!format(&fail!Attempts, MaxAttempts, 0.seconds);
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
