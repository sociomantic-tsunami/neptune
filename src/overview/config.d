module overview.config;

import provider.core : ProviderConfiguration = Configuration;

/**
    Overview tool own configuration
 **/
struct Configuration
{
    /// configuration required for provider client
    ProviderConfiguration provider;
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
    import vibe.core.log : logWarn;

    auto yml = Loader.fromFile(path).load();

    ProviderConfiguration provider;
    provider.dryRun = false;
    provider.oauthToken = yml["oauthtoken"].get!string;

    auto conf = typeof(return)(
        provider,
        yml["organization"].get!string,
        yml["exclude"].get!(Node[])
            .map!(node => node.get!string).array().ifThrown(null),
        yml["include"].get!(Node[])
            .map!(node => node.get!string).array().ifThrown(null),
    );

    if (conf.organization.length == 0)
        logWarn("Empty organization name, likely misconfiguration");
    if (conf.provider.oauthToken.length != 40)
        logWarn("OAuth Token doesn't look valid");

    return conf;
}
