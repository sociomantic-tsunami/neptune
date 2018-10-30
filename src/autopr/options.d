/*******************************************************************************

    Options module.

    Copyright:
        Copyright (c) 2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module autopr.options;

/// Global accessible options
public Options options;

/// Options struct
struct Options
{
    // Amount of entries to fetch per query
    int num_entries;

    // Delay in seconds between each PR
    uint delay_seconds;

    string[] orgas;

    string key;

    bool quit;
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
    import std.math;

    import std.range;
    import std.algorithm;

    options.num_entries = 100;

    auto help_info = getopt(opts,
        // -------------
        "num-entries", "Amount of entries to fetch per query (max & default: 100)",
        &options.num_entries,
        // -------------
        "delay", "How many seconds to wait between each PR",
        &options.delay_seconds
    );

    options.num_entries = min(100, options.num_entries);

    immutable ReasonableMaxDelay = 3600;
    if (options.delay_seconds > ReasonableMaxDelay)
    {
        import std.stdio;
        writefln("Warning: A delay of %s seconds seems unreasonable high.",
            options.delay_seconds);
    }

    bool show_help = help_info.helpWanted;

    string desc = "Neptune AutoPR";

    if (opts.length < 3)
    {
        import std.stdio;
        writefln("Not enough parameters!\n");
        desc ~= format("\nUsage: ./%s token org1 [org2...]\n", opts[0]);
        show_help = true;
    }

    if (show_help)
    {
        defaultGetoptPrinter(desc, help_info.options);
        options.quit = true;
    }

    options.key = opts[1];
    options.orgas = opts[2..$];

    return options;
}
