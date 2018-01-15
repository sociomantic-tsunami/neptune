/*******************************************************************************

    Helper methods to access the octod/github API

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module lib.github.GithubConfig;

// Fixing import detection
static import lib.github.oauth;

import octod.core;
import octod.api.repos;

/// Helper methods to access github and local github configuration
struct GithubConfig
{
    /// Name of the application accessing github
    string app_name;

    /*******************************************************************************

        Returns:
            octod configuration. If it doesn't exists, will prompt the user for
            the required infomation

    *******************************************************************************/

    public Configuration getConf ( )
    {
        import lib.git.helper;
        import std.exception;

        Configuration cfg;
        cfg.dryRun = false;

        cfg.oauthToken = getConfig(this.app_name ~ ".oauthtoken");

        enforce(cfg.oauthToken.length > 0);

        return cfg;
    }


    /*******************************************************************************

        Checks whether the oauth config is setup and starts the setup process if not

    *******************************************************************************/

    public void checkOAuthSetup ( bool assume_yes )
    {
        import std.exception;

        getConf().ifThrown(githubSetup(assume_yes));
    }


    /*******************************************************************************

        Sets up the interaction with github using an oauth token

        Params:
            assume_yes = whether to assume yes to potential questions asked

        Returns:
            set up configuration object

    *******************************************************************************/

    private Configuration githubSetup ( bool assume_yes )
    {
        import lib.shell.helper;
        import lib.git.helper;

        import std.stdio;
        import std.string;
        import std.exception;


        Configuration cfg;
        cfg.dryRun = false;

        static string tryHubToken ( string app_name, bool assume_yes )
        {
            auto hub_oauth = getConfig("hub.oauthtoken");

            enforce(hub_oauth.length > 0);

            writefln("No oauth token was found under "~app_name~".oauthtoken, "~
                     "however an hub.oauthtoken was found. ");

            if (getBoolChoice(assume_yes,
                "Would you like to use it as "~app_name~".oauthtoken config?"))
            {
                return hub_oauth;
            }

            throw new Exception("");
        }

        static string askUserAndCreate ( string app_name )
        {
            import lib.github.oauth;

            auto username = readString("Please enter your username: ");
            auto password = readPassword("Please provide your password: ");

            return createOAuthToken(username, password, ["repo"], app_name);
        }

        //import vibe.core.log;
        //setLogLevel(LogLevel.trace);

        writefln("Setting up an oauth token for github access");

        cfg = cfg.init;
        cfg.dryRun = false;
        cfg.oauthToken = tryHubToken(this.app_name, assume_yes)
            .ifThrown(askUserAndCreate(this.app_name,));

        cmd("git config --global "~this.app_name~".oauthtoken " ~ cfg.oauthToken);

        return cfg;
    }

    string getRemote ( string upstream )
    {
        import lib.git.helper : getRemote;

        return getRemote(this.app_name, upstream);
    }
}

