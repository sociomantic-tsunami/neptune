/*******************************************************************************

    Various helper functions

    Copyright:
        Copyright (c) 2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module internal.json;

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


/*******************************************************************************

    Merge two identically structured json objects

    Params:
        from = json object to merge
        to   = json object to merge into
        overwrite_existing = if true, prefers the new value when there are
                             conflicts

*******************************************************************************/

void mergeJson ( Json from, ref Json to, bool overwrite_existing = true )
{
    import std.range;
    import std.algorithm;
    import std.typecons;

    foreach (from_el; from.byKeyValue())
    {
        if (from_el.key !in to)
            // Insert
            to[from_el.key] = from_el.value.clone;
        else
        {
            // Append
            if (to[from_el.key].type == Json.Type.array)
                to[from_el.key] ~= from_el.value.clone;
            // Recursive merge
            else if (to[from_el.key].type == Json.Type.object)
                mergeJson(from_el.value, to[from_el.key], overwrite_existing);
            // Overwrite
            else if (overwrite_existing)
                to[from_el.key] = from_el.value.clone;
        }
    }
}

unittest
{
    auto a = Json.emptyObject;
    auto b = Json.emptyObject;

    a["num1"] = 1;
    a["array"] = Json.emptyArray;
    a["array"] ~= Json(1);
    a["object"] = Json.emptyObject;
    a["object"]["num2"] = 2;
    a["object"]["num1"] = 2; // Will overwrite
    a["object"]["array"] = Json.emptyArray;
    a["object"]["array"] ~= Json(10);

    b["num2"] = 2;
    b["num3"] = 3;
    b["array"] = Json.emptyArray;
    b["array"] ~= Json(2);
    b["object"] = Json.emptyObject;
    b["object"]["num1"] = 1; // will be overwriten
    b["object"]["array"] = Json.emptyArray;
    b["object"]["array"] ~= Json(2);

    mergeJson(a, b);

    assert(b["array"].length == 2);
    assert(b["array"][0] == 2);
    assert(b["array"][1] == 1);
    assert("num1" in b);
    assert(b["num2"].get!int == 2);
    assert("num2" in b, "Num 2 is missing");
    assert("num3" in b);
    assert(b["object"]["num1"] == 2);
    assert(b["object"]["num2"] == 2);
    assert(b["object"]["array"].length == 2);
    assert(b["object"]["array"][0] == 2);
    assert(b["object"]["array"][1] == 10);
}
