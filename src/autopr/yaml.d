/*******************************************************************************

    Yaml node information extractor functions

    Copyright:
        Copyright (c) 2018 sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module autopr.yaml;

import lib.yaml.parse;
import dyaml.node;

/// Types of update requests possible
enum RequestLevel
{
    Patch = "patch",
    Minor = "minor",
    Major = "major",
    None  = "none" ,
}

/// YML key for automatic update settings
enum AutoPRKey = "automatic-update-prs";

/// YML key for automatic update settings, global
enum AutoPRKeyGlobal = "default";
enum AutoPRKeyOverride = "override";

/*******************************************************************************

    Parses <content> as YML and extracts the automatic request settings from it

    They are returned as a struct with the memembers

        - global: global settings for all submodules
        - mods: hashmap, key is the submodule, value the specific setting

    Params:
        yaml = yml content to process

    Returns:
        struct with members
            global (RequestLevel)
            mods (RequestLevel[string])

*******************************************************************************/

auto getAutoPRSettings ( Node yaml )
{
    import std.conv : to;
    import std.typecons;

    auto ret = Tuple!(RequestLevel, "global", RequestLevel[string], "mods")();
    ret.global = RequestLevel.Minor;

    // Set defaults based on library value
    if (yaml.containsKey("library") && yaml["library"].get!bool)
        ret.global = RequestLevel.Patch;

    if (!yaml.containsKey(AutoPRKey))
        return ret;

    auto getReq ( string val )
    {
        import std.traits : EnumMembers;
        import std.algorithm : find;
        import std.range : empty;

        auto val_rl = cast(RequestLevel) val;
        auto enum_rslt = [EnumMembers!RequestLevel].find(val_rl);

        if (enum_rslt.empty)
            throw new Exception("Invalid enum value: " ~ val);

        return val_rl;
    }

    auto autopr = yaml[AutoPRKey];

    if (autopr.containsKey(AutoPRKeyGlobal))
        ret.global = getReq(autopr["default"].get!string);

    if (autopr.containsKey(AutoPRKeyOverride))
    {
        foreach (string lib, string opt; autopr[AutoPRKeyOverride])
            ret.mods[lib] = getReq(opt.to!string);
    }

    return ret;
}

/// Test patch level when no library
unittest
{

    string test_in = `library: false`;

    auto ret = getAutoPRSettings(parseYAML(test_in));

    assert(ret.global == RequestLevel.Minor);
    assert(ret.mods.length == 0);
}


/// Test patch level when library
unittest
{
    string test_in = `library: true`;

    auto ret = getAutoPRSettings(parseYAML(test_in));

    assert(ret.global == RequestLevel.Patch);
    assert(ret.mods.length == 0);
}

/// Test Patch level specification
unittest
{
    string test_in =
`library: true
automatic-update-prs:
  default: minor
  override:
    makd: major
    krill: minor
    swarm: patch`;

    auto ret = getAutoPRSettings(parseYAML(test_in));

    assert(ret.global == RequestLevel.Minor);
    assert(ret.mods.length == 3);
    assert(ret.mods["makd"] == RequestLevel.Major);
    assert(ret.mods["krill"] == RequestLevel.Minor);
    assert(ret.mods["swarm"] == RequestLevel.Patch);
}

/*******************************************************************************

    Extracts library information and according support windows from YML

    Params:
        yaml = yml content to process

    Returns:
        a struct with the members
            library: bool, if set, it's a library
            minor_versions: int, amount of minor versions supported
            major_months: int, amount of months a major version is supported
                          after the release of the last major

*******************************************************************************/

auto getSupportGuarantees ( Node yaml )
{
    import std.typecons;

    auto ret = Tuple!(bool, "library",
        int, "minor_versions", int, "major_months")();

    // Default values
    ret.minor_versions = 2;
    ret.major_months = 6;

    // Skip non-library projects
    if (!yaml.containsKey("library") || !yaml["library"].get!bool)
    {
        ret.library = false;
        return ret;
    }

    ret.library = true;

    if (yaml.containsKey("support-guarantees"))
    {
        auto sprt = yaml["support-guarantees"];

        if (sprt.containsKey("minor-versions"))
            ret.minor_versions = sprt["minor-versions"].get!int;

        if (sprt.containsKey("major-months"))
            ret.major_months = sprt["major-months"].get!int;
    }

    return ret;
}

/// Test specification of support levels
unittest
{
    string lib_test_in =
`
library: true
support-guarantees:
  minor-versions: 30
  major-months: 5
`;

    auto rslt = getSupportGuarantees(parseYAML(lib_test_in));

    assert(rslt.library);
    assert(rslt.minor_versions == 30);
    assert(rslt.major_months == 5);
}

/// Test skipping of parsing when not a library
unittest
{
    string lib_test_in =
`library: false
support-guarantees:
  minor-versions: 30
  major-months: 5`;

    auto rslt = getSupportGuarantees(parseYAML(lib_test_in));

    assert(!rslt.library);
    // Expecting default versions
    assert(rslt.minor_versions == 2);
    assert(rslt.major_months == 6);
}

/// Test skipping when library is not set at all
unittest
{
    string lib_test_in =
`support-guarantees:
  minor-versions: 30
  major-months: 5`;

    auto rslt = getSupportGuarantees(parseYAML(lib_test_in));

    assert(!rslt.library);
    // Expecting default versions
    assert(rslt.minor_versions == 2);
    assert(rslt.major_months == 6);
}
