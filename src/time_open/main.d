/*******************************************************************************

    Main file

    Lists the pull requests of a GitHub repository sorted by the time they are
    open.

    Copyright:
        Copyright (c) 2019 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module time_open.main;


/*******************************************************************************

    Main function

    Params:
        args = command line arguments

    Returns:
        the exit status to the operating system

*******************************************************************************/

version(unittest) {} else
int main ( string[] args )
{
    // parse configuration from arguments
    Config config = parseArgs(args);

    import provider.core;
    Configuration cfg;
    cfg.platform = cfg.platform.Github;

    // set up GitHub credentials
    // preferring GitHub token
    if (config.github_token.length)
    {
        cfg.oauthToken = config.github_token;
    }
    else
    {
        assert(config.username.length);

        import core.sys.linux.unistd : getpass;
        import std.string : fromStringz;
        // FIXME
        // getpass is obsolete
        auto password = getpass("Password: ".ptr).fromStringz().idup;

        cfg.username = config.username;
        cfg.password = password;
    }

    auto http_connection = HTTPConnection.connect(cfg);
    scope (exit)
    {
        http_connection.disconnect();
    }

    // GraphQL query for getting latest open PRs
    enum query_format_string = `
    {
        repository(owner: "%s", name: "%s")
        {
            pullRequests(states: [OPEN],
                         orderBy: {field: CREATED_AT, direction: ASC},
                         last: %s)
            {
                nodes
                {
                    title
                    url
                    createdAt
                }
            }
        }
    }`;

    import std.format : format;
    auto query = query_format_string.format(config.owner, config.repository,
        config.num_pull_requests);

    import internal.github.graphql : graphQL;
    auto result = http_connection.graphQL(query);
    import std.stdio;
    scope(failure)
    {
        stderr.writefln("Failed query: \n%s", query);
        stderr.writefln("with response: \n%s", result);
    }

    if ("errors" in result)
    {
        auto err = result["errors"];
        throw new Exception(err.get!(string)());
    }

    // extract pull requests
    auto latest_open_prs = result["data"]["repository"]["pullRequests"]["nodes"];

    import std.datetime : Clock;
    import std.datetime.timezone : UTC;
    auto now = Clock.currTime(UTC());
    import core.time : Duration;
    now.fracSecs = Duration.zero();

    // sort pull requests since they are open and outputs them
    import std.algorithm : map, sort, each;
    import std.array : array;
    import std.typecons : tuple;
    import std.datetime : SysTime;
    latest_open_prs.byValue()
                   .map!(pr => tuple!("title", "url", "time_since_open")
                                     (pr["title"].get!(string)(),
                                      pr["url"].get!(string)(),
                                      now - SysTime.fromISOExtString(pr["createdAt"].get!(string)())))()
                   .array()
                   .sort!((a,b) => a.time_since_open > b.time_since_open)()
                   .each!(pr => writefln("PR '%s' (%s) open since %s",
                           pr.title, pr.url, pr.time_since_open))();

    import core.stdc.stdlib : EXIT_SUCCESS;
    return EXIT_SUCCESS;
}


/// Configuration for querying pull requests from GitHub
struct Config
{
    /// Username for GitHub authentication
    string username = "";

    /// GitHub OAuth token for authentication
    string github_token = "";

    /// GitHub repository owner to query the repository for
    string owner = "sociomantic";

    /// GitHub repository to query for
    string repository = "";

    /// Number of last open pull requests to query for
    uint num_pull_requests = 5;
}


/*******************************************************************************

    Parses the config from program arguments

    Calls exit in case of errors with parsing arguments (EXIT_FAILURE) or if
    program help was requested (EXIT_SUCCESS).

    Params:
        args = arguments to parse

    Returns:
        the successfully parsed config

*******************************************************************************/

private Config parseArgs ( string[] args )
{
    void exit ( int exit_status, string message = "")
    {
        // require a failure message
        import core.stdc.stdlib : EXIT_SUCCESS;
        assert(exit_status == EXIT_SUCCESS || message.length);
        import std.stdio;
        stderr.writeln(message);
        import core.stdc.stdlib : exit;
        exit(exit_status);
        assert(false);
    }
    import core.stdc.stdlib : EXIT_FAILURE, EXIT_SUCCESS;

    Config config;
    import std.getopt;
    GetoptResult help_info;
    try
    {
        import std.format : format;
        // filter options from arguments
        help_info = getopt(args,
            "username",
            "Username for GitHub authentication asking later for a password",
            &config.username,

            "token",
            "token for GitHub authentication",
            &config.github_token,

            "num-pull-requests",
            "Maximal number of last open pull requests to fetch (defaults to %s)".format(
                config.num_pull_requests),
            &config.num_pull_requests,

            "owner",
            "Owner of the repository (defaults to %s)".format(
                config.owner),
            &config.owner,
        );
    }
    catch (Exception e)
    {
        exit(EXIT_FAILURE, e.msg);
    }

    void printUsage ()
    {
        import std.format : format;
        string desc = "Usage: %s [OPTION]... REPOSITORY\n\nLists GitHub pull requests longest in review.\n\nOptions:".format(args[0]);
        defaultGetoptPrinter(desc, help_info.options);
    }

    if (help_info.helpWanted)
    {
        printUsage();
        exit(EXIT_SUCCESS);
    }

    if (!config.username.length && !config.github_token.length)
    {
        exit(EXIT_FAILURE,
            "Either username or token must be specified for GitHub authentication.");
    }

    if (args.length != 2)
    {
        exit(EXIT_FAILURE,
            "Missing GitHub repository name.");
    }
    config.repository = args[1];

    return config;
}
