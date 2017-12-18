module common.yaml;
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
