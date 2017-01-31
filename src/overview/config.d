module overview.config;

import octod.core : OctodConfiguration = Configuration;

/**
    Overview tool own configuration
 **/
struct Configuration
{
    /// configuration required for octod client
    OctodConfiguration octod;
    /// GitHub organization name to query repositories from
    string organization;
    /// List of organization repositories to remove from initial one
    string[] excludedRepos;
    /// List of additional repositories (can be from different organizations)
    string[] includedRepos;
}

/**
    Encapsulates config file parsing

    Params:
        path = path to YAML file with configuration

    Returns:
        parsed configuration
 **/
Configuration readConfigFile (string path)
{
    import std.algorithm.iteration : map;
    import std.array;
    import std.exception : ifThrown;
    import dyaml.loader;
    import dyaml.node;

    auto yml = Loader(path).load();

    OctodConfiguration octod;
    octod.dryRun = false;
    octod.oauthToken = yml["oauthtoken"].get!string;

    return typeof(return)(
        octod,
        yml["organization"].get!string,
        yml["exclude"].get!(Node[])
            .map!(node => node.get!string).array().ifThrown(null),
        yml["include"].get!(Node[])
            .map!(node => node.get!string).array().ifThrown(null),
    );
}
