/*******************************************************************************

    Helper methods to access the octod/github API

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module internal.RemoteConfig;

// Fixing import detection
static import internal.github.oauth;

import octod.core;
import octod.api.Repos;

/// Platform types
enum Platform { github, gitlab, detect };

/// Helper methods to access github and local github configuration
struct RemoteConfig
{
    /// Name of the application accessing github
    string app_name;

    /// Octo config
    Configuration config;

    /***************************************************************************

        Create instance of RemoteConfig, initializes an octod config as well
        and will ask the user to set one up if the config data can't be found

        Params:
            app_name = name of the app
            base_url = base url to the remote server, either github or gitlab
            assume_yes = bool, assume true for any questions
            provider = which provider type it is

    ***************************************************************************/

    public this ( string app_name, string base_url, bool assume_yes,
        Platform provider )
    {
        import internal.git.helper;
        import std.exception;

        this.app_name = app_name;

        immutable OldGitHubConfName = ".oauthtoken";
        immutable GitHubConfName = ".github-oauthtoken";
        immutable GitLabConfName = ".gitlab-oauthtoken";

        string conf_name = GitHubConfName;

        this.config.dryRun = false;
        this.config.baseURL = base_url;

        with (Platform) final switch (provider)
        {
            case github:
                this.config.platform = Configuration.Platform.Github;
                break;
            case gitlab:
                this.config.platform = Configuration.Platform.Gitlab;
                break;
            case detect:
                this.config.platform = this.guessPlatform();
                import std.stdio;
                writefln("Detected platform %s", this.config.platform);
                break;
        }

        with(Configuration.Platform) final switch (this.config.platform)
        {
            case Gitlab:
                conf_name = GitLabConfName;
                break;
            case Github:
                conf_name = GitHubConfName;
                break;
        }

        try
        {
            this.config.oauthToken = getConfig(this.app_name ~ conf_name);
        }
        catch (Exception exc)
        {
            conf_name = OldGitHubConfName;

            this.config.oauthToken =
                getConfig(this.app_name ~ conf_name).ifThrown("");
        }

        if (this.config.oauthToken.length == 0)
        {
            this.oauthSetup(conf_name, assume_yes);
        }
    }


    /*******************************************************************************

        Sets up the interaction with github/gitlab using an oauth token

        Params:
            conf_name = config key name
            assume_yes = whether to assume yes to potential questions asked

        Returns:
            set up configuration object

    *******************************************************************************/

    private void oauthSetup ( string conf_name, bool assume_yes )
    {
        import internal.shell.helper;
        import internal.git.helper;

        import std.stdio;
        import std.string;
        import std.exception;

        this.config.dryRun = false;

        static string tryHubToken ( string app_name, string conf_name, bool assume_yes )
        {
            // bail out if it's a gitlab token
            enforce(!conf_name.startsWith(".gitlab"));

            auto hub_oauth = getConfig("hub.oauthtoken");

            enforce(hub_oauth.length > 0);

            writefln("No oauth token was found under %s.%s, "~
                 "however an hub.oauthtoken was found. ", app_name, conf_name);

            if (getBoolChoice(assume_yes,
                "Would you like to use it as "~app_name~conf_name~" config?"))
            {
                return hub_oauth;
            }

            throw new Exception("");
        }

        static string askUserAndCreate ( string app_name, string conf_name )
        {
            import internal.github.oauth;

            if (conf_name.startsWith(".gitlab"))
            {
                return readString(
                    "Please enter your gitlab personal access token "~
                    "(create it at https://gitlab.com/profile"~
                    "/personal_access_tokens): ");
            }

            auto username = readString("Please enter your username: ");
            auto password = readPassword("Please provide your password: ");

            return createOAuthToken(username, password, ["repo"], app_name);
        }

        //import vibe.core.log;
        //setLogLevel(LogLevel.trace);

        writefln("Setting up an oauth/personal access token");

        this.config = this.config.init;
        this.config.dryRun = false;
        this.config.oauthToken = tryHubToken(this.app_name, conf_name, assume_yes)
            .ifThrown(askUserAndCreate(this.app_name, conf_name));

        cmd("git config --global "~this.app_name~conf_name ~ " " ~
            this.config.oauthToken);
    }

    string getRemote ( string upstream )
    {
        import internal.git.helper : getRemote;

        return getRemote(this.app_name, upstream);
    }

    /// Returns true if this is a github configuration
    private Configuration.Platform guessPlatform ( ) const
    {
        import std.algorithm;

        if (this.config.baseURL.canFind("github"))
            return Configuration.Platform.Github;

        return Configuration.Platform.Gitlab;
    }
}

