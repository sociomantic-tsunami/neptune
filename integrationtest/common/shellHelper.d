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
        command = command to run

    Returns:
        output of the command

*******************************************************************************/

string cmd ( string wd, string command )
{
    int status;

    auto output = cmd(wd, command, status);

    if (status != 0)
        throw new Exception(output);

    return output;
}

/*******************************************************************************

    Runs a command and returns the output

    Params:
        wd = directory to run the command in
        command = command to run
        status = the return status of the command will be written to this out
                 parameter

    Returns:
        output of the command

*******************************************************************************/

string cmd ( string wd, string command, out int status )
{
    import std.process : executeShell, Config;
    import std.string : strip;

    string[string] env;
    env["HOME"] = wd;

    auto c = executeShell(command, env, Config.none, size_t.max, wd);

    status = c.status;

    return strip(c.output);
}
