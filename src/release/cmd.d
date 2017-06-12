/*******************************************************************************

    Command line interaction helper

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.cmd;

/// Exception to be thrown when the exit code is unexpected
class ExitCodeException : Exception
{
    this ( string msg, int status, string file = __FILE__, int line = __LINE__ )
    {
        import std.format;
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


/***************************************************************************

    Finds out if ref1 is an ancestor of ref2

    Params:
        ref1 = ref to check if it is an ancestor of ref2
        ref2 = ref to check if it is a decendant of ref1

    Returns:
        true if ref1 is an ancestor of ref2

***************************************************************************/

bool isAncestor ( string ref1, string ref2 )
{
    import std.process : executeShell;
    import std.format;

    auto upstream = getRemote();

    auto c = executeShell(format("git merge-base --is-ancestor %s %s",
                                 ref1, ref2));

    if (c.status != 0 && c.status != 1)
        throw new Exception(c.output);

    return c.status == 0;
}


/*******************************************************************************

    Returns:
        the currently checked out branch

*******************************************************************************/

string getCurrentBranch ( )
{
    import release.cmd;
    return cmd("git symbolic-ref --short HEAD");
}


/*******************************************************************************

    Returns:
        The upstream remote name

*******************************************************************************/

string getRemote ( )
{
    import std.algorithm.iteration : splitter, uniq, map, filter;
    import std.algorithm.searching: canFind;
    import std.range;
    import std.conv;

    auto remotes = cmd("git remote -v")
                      .uniq()
                      .splitter!(a=>a == '\n')
                      .filter!(a=>a.canFind("github.com:" ~ getUpstream()))
                      .map!(a=>a.splitter!(a=>a == ' ' || a == '\t').front);

    if (remotes.empty)
        throw new Exception("Can't find your upstream remote for %s",
                            getUpstream());

    return remotes.front.array.to!string;
}


/*******************************************************************************

    Returns:
        the configured neptune.upstream variable. If not found, asks the user to
        set it up.

*******************************************************************************/

string getUpstream ( )
{
    try return cmd("git config neptune.upstream");
    catch (Exception e)
    {
        import std.stdio;
        import std.string;

        writefln("No neptune upstream config found.");

        try
        {
            auto hubupstream = cmd("git config hub.upstream");

            writefln("However, an hub.upstream configuration was found: %s",
                     hubupstream);

            if (readYesNoResponse("Would you like to use it as neptune.upstream config?"))
            {
               cmd("git config neptune.upstream " ~ hubupstream);
               return hubupstream;
            }

        }
        catch (ExitCodeException e) {}

        writef("Please enter the upstream location: ");

        string upstream = strip(readln());

        while (upstream.length == 0)
        {
            writef("Empty input. Please enter the upstream location: ");
            upstream = strip(readln());
        }

        cmd("git config neptune.upstream " ~ upstream);
        return upstream;
    }
}


/*******************************************************************************

    Prompts the user for a yes or no response, returns the response

    Params:
        fmt = question to ask
        args = fields to format the question

    Returns:
        true if user decided for yes, else false

*******************************************************************************/

public bool readYesNoResponse ( Args... ) ( string fmt, Args args )
{
    import std.stdio;
    import std.string;

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
