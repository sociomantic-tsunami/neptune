/*******************************************************************************

    Command line interaction helper

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.shellHelper;

public import common.shellHelper;

import release.options;

/*******************************************************************************

    Prompts the user for a yes or no response, returns the response.

    Params:
        fmt = question to ask
        args = fields to format the question

    Returns:
        true if user decided for yes, else false

*******************************************************************************/

public bool getBoolChoice ( Args... ) ( string fmt, Args args )
{
    import common.shellHelper : getBoolChoice;
    return getBoolChoice(options.assume_yes, fmt, args);
}
