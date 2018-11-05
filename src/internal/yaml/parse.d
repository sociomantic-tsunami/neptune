/*******************************************************************************

    Yaml parsing wrapper method

    Copyright:
        Copyright (c) 2018 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module internal.yaml.parse;

/**
    YAML parsing helper for usage in pipeline

    Params:
        content = raw data that is expected to contain UTF-8 YAML text
 **/
public auto parseYAML ( const void[] content )
{
    import std.utf;
    import dyaml.loader;

    auto s = cast(char[]) content.dup;
    validate(s);
    return Loader.fromString(s).load();
}
