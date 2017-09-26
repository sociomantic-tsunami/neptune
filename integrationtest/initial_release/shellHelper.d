/*******************************************************************************

    Shell helper functions

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.initial_release.shellHelper;

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
    import std.process : executeShell, Config;
    import std.string : strip;

    string[string] env;
    env["HOME"] = wd;

    auto c = executeShell(command, env, Config.none, size_t.max, wd);

    if (c.status != 0)
        throw new Exception(c.output);

    return strip(c.output);
}
