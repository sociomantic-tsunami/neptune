/*******************************************************************************

    Shell helper functions

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.common.shellHelper;

/*******************************************************************************

    Runs a command and returns the output

    Params:
        wd = directory to run the command in
        command = command to run and arguments to pass to it

    Returns:
        output of the command

*******************************************************************************/

string cmd ( string wd, const(string[]) command )
{
    int status;
    return cmd(wd, command, status);
}

/*******************************************************************************

    Runs a command and returns the output

    Params:
        wd = directory to run the command in
        command = command to run (including arguments). Arguments will be split
                  based on spaces

    Returns:
        output of the command

*******************************************************************************/

string cmd ( string wd, string command )
{
    int status;
    return cmd(wd, command, status);
}

/*******************************************************************************

    Runs a command and returns the output

    Params:
        wd = directory to run the command in
        command = command to run (including arguments). Arguments will be split
                  based on spaces
        status = the return status of the command will be written to this out
                 parameter

    Returns:
        output of the command

*******************************************************************************/

string cmd ( string wd, string command, out int status )
{
    import std.string: split;
    return cmd(wd, command.split(), status);
}

/*******************************************************************************

    Runs a command and returns the output

    Params:
        wd = directory to run the command in
        command = command to run and arguments to pass to it
        status = the return status of the command will be written to this out
                 parameter

    Returns:
        output of the command

*******************************************************************************/

string cmd ( string wd, const(string[]) command, out int status )
{
    import std.process : execute, Config;
    import std.string : strip;

    string[string] env;
    env["HOME"] = wd;

    auto c = execute(command, env, Config.none, size_t.max, wd);

    status = c.status;

    return strip(c.output);
}
