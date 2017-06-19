/*******************************************************************************

    Options module.

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.options;

struct Options
{
    import vibe.core.log;

    /// Level of desired logging
    LogLevel logging;

    bool help_triggered;
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

    Options options;
    options.logging = LogLevel.info;

    bool verbose;

    auto help_info = getopt(opts,
           "log|l", format("Set the logging level, one of %s",
                           iota(LogLevel.min, LogLevel.max).map!LogLevel), &options.logging,
           "verbose|v", "Set logging to verbose", &verbose);


    if (verbose)
        options.logging = options.logging.trace;

    if (help_info.helpWanted)
    {
        options.help_triggered = true;

        defaultGetoptPrinter("Neptune release helper.", help_info.options);
    }

    return options;
}
