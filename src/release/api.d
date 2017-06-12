/*******************************************************************************

    helper methods to access the octod/github API

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.api;

import octod.core;
import octod.api.repos;


/*******************************************************************************

    Returns:
        global api object to interact with github

*******************************************************************************/

public ref HTTPConnection api ( )
{

    static HTTPConnection _api;
    static bool connected = false;

    if (!connected)
    {
        _api = HTTPConnection.connect(getConf());
        connected = true;
    }

    return _api;
}


/*******************************************************************************

    Returns:
        neptune configuration. If it doesn't exists, will prompt the user for
        the required infomation

*******************************************************************************/

public Configuration getConf ( )
{
    import release.cmd;

    Configuration cfg;
    cfg.dryRun = false;

    try cfg.oauthToken = cmd("git config neptune.oauthtoken");
    catch (ExitCodeException) {}

    if (cfg.oauthToken.length == 0)
        return githubSetup();

    return cfg;
}


/*******************************************************************************

    Sets up the interaction with github using an oauth token

    Returns:
        set up configuration object

*******************************************************************************/

private Configuration githubSetup ( )
{
    import release.cmd;

    import std.stdio;
    import std.string;

    string hub_oauth;

    Configuration cfg;
    cfg.dryRun = false;

    try hub_oauth = cmd("git config hub.oauthtoken");
    catch (ExitCodeException) {}

    if (hub_oauth.length > 0)
    {
        writefln("No oauth token was found under neptune.oauthtoken, however an hub.oauthtoken was found. ");
        if (readYesNoResponse("Would you like to use it as neptune.oauthtoken config?"))
        {
            cmd("git config --global neptune.oauthtoken " ~ hub_oauth);
            cfg.oauthToken = hub_oauth;
            return cfg;
        }
    }

    writefln("Setting up an oauth token for github access");
    writef("Please enter your username: ");

    cfg.username = strip(readln());

    while (cfg.username.length == 0)
    {
        writef("Empty input. Please provide your username: ");
        cfg.username = strip(readln());
    }

    writef("Please provide your password: ");
    {
        import core.sys.posix.termios;

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

        cfg.password = readln()[0 .. $-1];

        while (cfg.password.length == 0)
        {
            writef("Empty input. Please provide your password: ");
            cfg.password = strip(readln());
        }
    }

    import octod.core;
    import vibe.data.json;

    //import vibe.core.log;
    //setLogLevel(LogLevel.trace);

    auto client = HTTPConnection.connect(cfg);

    Json json = Json.emptyObject;

    json["scopes"] = Json.emptyArray;
    json["scopes"] ~= "repo";
    json["note"] = "Neptune";

    auto response = client.post("/authorizations", json);

    cfg = cfg.init;
    cfg.dryRun = false;
    cfg.oauthToken = response["token"].to!string;

    import release.cmd;

    cmd("git config --global neptune.oauthtoken " ~ cfg.oauthToken);

    return cfg;
}
