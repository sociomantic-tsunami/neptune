/*******************************************************************************

    Various helper functions

    Copyright:
        Copyright (c) 2017 sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module autopr.helper;

import vibe.data.json;

/*******************************************************************************

    Short-hand access function for Json objects.
    Instead of writiting json["abc"]["efg"]["hij"] you can do
    json.path!"abc.efg.hij".

    Params:
        path_str = string making up the path to access the field
        obj = object to access on

    Returns:
        json object at the given path

*******************************************************************************/

public Json path ( string path_str ) ( Json obj )
{
    import std.algorithm : splitter, joiner;
    import std.range : array;

    return mixin(`obj["` ~ path_str.splitter('.').joiner(`"]["`).array ~ `"]`);
}

