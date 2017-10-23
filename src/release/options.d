/*******************************************************************************

    Options module.

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.options;

/// Global accessible options
public Options options;

/// Options struct
struct Options
{
    import vibe.core.log;

    /// Level of desired logging
    LogLevel logging;

    /// Whether we should release subsequent branches that were merged
    bool release_subsequent = true;

    bool help_triggered;

    string github_url = "https://api.github.com";

    bool assume_yes = false;

    bool no_send_mail = false;

    bool pre_release;
}


/*******************************************************************************

    Parses the options

    Params:
        opts = options array to parse

    Returns:
        an options struct

*******************************************************************************/

Options parseOpts ( string[] opts )
{
    import vibe.core.log;
    import std.getopt;
    import std.format;

    import std.range;
    import std.algorithm;

    options.logging = LogLevel.info;

    bool verbose;

    auto help_info = getopt(opts,
           "log|l", format("Set the logging level, one of %s",
                           iota(LogLevel.min, LogLevel.max).map!LogLevel), &options.logging,
           "verbose|v", "Set logging to verbose", &verbose,

           "release-all|a",
           "If set, branches that were merged due to a minor release will also be released (default: true)",
           &options.release_subsequent,
           "base-url", "Github API base URL", &options.github_url,
           "assume-yes", "Assumes yes for all questions", &options.assume_yes,
           "pre-release|p", "Creates a release candidate (pre-release)",
           &options.pre_release,
           "no-send-mail", "When set, will not send the release email",
           &options.no_send_mail);

    if (verbose)
        options.logging = options.logging.trace;

    if (help_info.helpWanted)
    {
        options.help_triggered = true;

        defaultGetoptPrinter("Neptune release helper.", help_info.options);
    }

    return options;
}
