/*******************************************************************************

    Options module.

    Copyright:
        Copyright (c) 2017 dunnhumby Germany GmbH. All rights reserved.

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
    import internal.RemoteConfig : Platform;

    /// Level of desired logging
    LogLevel logging;

    /// Whether we should release subsequent branches that were merged
    bool release_subsequent = true;

    bool help_triggered;

    string base_url = "";

    Platform provider = Platform.detect;

    bool assume_yes = false;

    bool no_send_mail = false;

    bool check_ancestor = true;

    bool pre_release;

    /// metadata to be appended to the version
    string metadata;
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
        // -------------
        "log|l", format("Set the logging level, one of %s",
            iota(LogLevel.min, LogLevel.max).map!LogLevel),
        &options.logging,
        // -------------
        "verbose|v", "Set logging to verbose",
        &verbose,
        // -------------
        "release-all|a", "If set, branches that were merged due to a minor "
            ~ "release will also be released (default: true)",
        &options.release_subsequent,
        // -------------
        "base-url", "Github or Gitlab API base URL",
        &options.base_url,
        // -------------
        "provider", "Which provider to use; one of [github, gitlab, detect]",
        &options.provider,
        // -------------
        "assume-yes", "Assumes yes for all questions",
        &options.assume_yes,
        // -------------
        "pre-release|p", "Creates a release candidate (pre-release)",
        &options.pre_release,
        // -------------
        "no-send-mail", "When set, will not send the release email",
        &options.no_send_mail,
        // -------------
        "no-check-ancestor", "When set, will not check if release branch"
            ~ "descends from HEAD of the previous branch",
        { options.check_ancestor = false; },
        // -------------
        "metadata|m", "When set, will be appended to the version as metadata string",
        &options.metadata
    );

    if (verbose)
        options.logging = options.logging.trace;

    if (help_info.helpWanted)
    {
        options.help_triggered = true;

        defaultGetoptPrinter("Neptune release helper.", help_info.options);
    }

    return options;
}


/*******************************************************************************

    Note: This doesn't strictly belong here, but it can't live in the main.d
    module because that one isn't unittested. Feel free to move if a better
    place comes to mind.

    Simple and stupid domain extractor. Looks for the string between @ and : and
    returns it. Throws an exception if either symbol wasn't found

    Params:
        url = url to find

    Returns:
        domain part of the url

*******************************************************************************/

public string extractDomain ( string url )
{
    import std.algorithm;
    import std.range : empty;
    import std.exception;

    auto begin = url.findSplitAfter("@");

    enforce(begin, "Failed to extract domain from remote url " ~ url);

    auto end = begin[1].findSplitBefore(":");

    enforce(end, "Failed to extract domain from remote url " ~ url);

    return end[0];
}

/// Tests the domain extraction function
unittest
{
    assert(extractDomain("git@gitlab.com:sociomantic-test/neptune-release-test.git")
        == "gitlab.com");
    assert(extractDomain("git@custom.gitlab.instance.de:sociomantic-test/neptune-release-test.git")
        == "custom.gitlab.instance.de");
}
