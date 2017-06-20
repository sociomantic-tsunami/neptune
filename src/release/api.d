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
        neptune configuration. If it doesn't exists, will prompt the user for
        the required infomation

*******************************************************************************/

public Configuration getConf ( )
{
    import release.gitHelper;
    import std.exception;

    Configuration cfg;
    cfg.dryRun = false;

    cfg.oauthToken = getConfig("neptune.oauthtoken");

    enforce(cfg.oauthToken.length > 0);

    return cfg;
}


/*******************************************************************************

    Checks whether the oauth config is setup and starts the setup process if not

*******************************************************************************/

public void checkOAuthSetup ( )
{
    import std.exception;

    getConf().ifThrown(githubSetup());
}


/*******************************************************************************

    Sets up the interaction with github using an oauth token

    Returns:
        set up configuration object

*******************************************************************************/

private Configuration githubSetup ( )
{
    import release.shellHelper;
    import release.gitHelper;

    import std.stdio;
    import std.string;
    import std.exception;


    Configuration cfg;
    cfg.dryRun = false;

    static string tryHubToken ( )
    {
        auto hub_oauth = getConfig("hub.oauthtoken");

        enforce(hub_oauth.length > 0);

        writefln("No oauth token was found under neptune.oauthtoken, "~
                 "however an hub.oauthtoken was found. ");

        if (readYesNoResponse("Would you like to use it as neptune.oauthtoken config?"))
            return hub_oauth;

        throw new Exception("");
    }

    static string askUserAndCreate ( )
    {
        auto username = readString("Please enter your username: ");
        auto password = readPassword("Please provide your password: ");

        return createOAuthToken(username, password, ["repo"], "Neptune");
    }

    //import vibe.core.log;
    //setLogLevel(LogLevel.trace);

    writefln("Setting up an oauth token for github access");

    cfg = cfg.init;
    cfg.dryRun = false;
    cfg.oauthToken = tryHubToken().ifThrown(askUserAndCreate());

    cmd("git config --global neptune.oauthtoken " ~ cfg.oauthToken);

    return cfg;
}


/*******************************************************************************

    Uses the given user/pass to create a connection which is then used to setup
    an oauth token with the given scopes and note

    Params:
        user = github username
        pass = github password
        scopes = oauth permission scopes
        note = oauth note

    Returns:
        oauth token code

*******************************************************************************/

public string createOAuthToken ( string user, string pass,
                                 string[] scopes, string note )
{
    import vibe.data.json;

    Configuration cfg;

    cfg.dryRun = false;
    cfg.username = user;
    cfg.password = pass;

    auto connection = HTTPConnection.connect(cfg);

    Json json = Json.emptyObject;

    json["scopes"] = Json.emptyArray;

    foreach (_scope; scopes)
        json["scopes"] ~= _scope;

    json["note"] = note;

    auto response = connection.post("/authorizations", json);

    return response["token"].to!string;
}
