/*******************************************************************************

    Functions required to parse & render the data flow graph from the YML format
    into a usable file for graphviz

    Copyright:
        Copyright (c) 2018 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module data_flow_mapper.DotNodes;

import dyaml.node;
import std.stdio;


/*******************************************************************************

    Any kind of channel, mostly storage channels. E.g. a dht channel, dmq
    channel or dsl channel but could also be a mysql table

*******************************************************************************/

class Channel
{
    /// Type of the channel (e.g. dht, dls, dmq, mysql)
    string type;

    /// Name of the channel
    string name;

    /***************************************************************************

        C'tor

        Params:
            type = type of the channel
            name = name of the channel

    ***************************************************************************/

    this ( string type, string name )
    {
        this.type = type;
        this.name = name;
    }

    /// Function to format the channel as string
    override string toString ( ) const
    {
        import std.format;
        return format("Channel(%s, %s)", this.type, this.name);
    }
}


/// App class
class App
{
    /// Name of the app
    string name;

    /***************************************************************************

        C'tor

        Params:
            name = name of the app

    ***************************************************************************/

    this ( string name )
    {
        this.name = name;
    }

    /// Format function for output
    override string toString ( ) const
    {
        import std.format;
        return format("App(%s)", this.name);
    }
}


/// Any kind of connection between an app and a channel
class Connection
{
    /// Type of the connection
    enum Type
    {
        Read,
        Write,
        Subscribe,
    }

    /// Type of the connection
    Type type;

    /// Source of the connection
    App source;

    /// Target of the connection
    Channel target;

    /***************************************************************************

        C'tor

        Params:
            type = type of the connection
            app = app of the connection
            channel = channel of the connection

    ***************************************************************************/

    this ( Type type, App app, Channel channel )
    {
        this.type = type;
        this.source = app;
        this.target = channel;
    }

    /// Provide text output for the connection
    override string toString ( ) const
    {
        import std.format;
        return format("Con(%s, %s -> %s)", this.type, this.source, this.target);
    }
}


/*******************************************************************************

    Writes a graphviz graph file to the given file object using the given
    channels, connections and apps

    Params:
        file = file to write the graphviz graph to
        channels = channels to render
        connections = connections to render
        apps = apps to render

*******************************************************************************/

void render ( File file, Channel[] channels, Connection[] connections, App[] apps )
{
    import std.algorithm;
    import std.range;

    file.writefln("digraph G {");

    // Step one: Write out all the app nodes
    foreach (app; apps)
        file.writefln("\t"~`"%s-app" [color=green]`, app.name);

    file.writefln("");


    // Step two: write out all the storage types
    auto stor_colors = [
        "dht" : "lightyellow",
        "dls" : "lightblue",
        "dmq" : "#f4a442",
        "mysql" : "lightgrey"];

    foreach (channel; channels)
        file.writefln("\t\"%s\" [style=filled,color=\"%s\"]",
            channel.name, stor_colors[channel.type]);


    // Step three: write out the connections
    auto operations = connections.map!(a=>a.type).array.sort.uniq();

    auto op_colors = [
        Connection.Type.Read : "darkgreen",
        Connection.Type.Write : "red",
        Connection.Type.Subscribe : "lightblue"];

    foreach (operation; operations)
    {
        file.writefln("\tedge [color=%s]", op_colors[operation]);

        foreach (connection; connections.filter!(a=>a.type == operation))
        {
            if (operation == operation.Write)
                file.writefln("\t\"%s-app\" -> \"%s\";",
                    connection.source.name, connection.target.name);
            else
                file.writefln("\t\"%s\" -> \"%s-app\";",
                    connection.target.name, connection.source.name);
        }
        file.writefln("");
    }

    file.writefln("}");
}


/*******************************************************************************

    Fill channels, connections and apps arrays from a yml structure

    Params:
        yml = structure to parse
        channels = channel array that will be filled
        connections = connection array that will be filled
        apps = apps array that will be filled

*******************************************************************************/

void parseFromYML ( Node yml, ref Channel[] channels,
    ref Connection[] connections, ref App[] apps )
{
    enum Key = "dataflow";

    if (!yml.containsKey(Key))
    {
        import std.stdio;
        writefln("Skipping app: no dataflow info");
        return;
    }

    auto dataflow = yml[Key];

    foreach (string app, Node flow; dataflow)
    {
        auto appinst = new App(app);
        apps ~= appinst;

        foreach (string storage_type, Node operations; flow)
            foreach (string operation, Node channel_list; operations)
            {
                import std.algorithm;
                import std.range;
                import std.stdio;

                foreach (string channel_name; channel_list)
                {
                    writefln("OP: %s | CHANNAME: %s", operation, channel_name);
                    Channel channel;
                    auto channel_rslt = channels.find!(
                        a=>a.name == channel_name && a.type == storage_type);

                    if (channel_rslt.empty)
                    {
                        channel = new Channel(storage_type, channel_name);
                        channels ~= channel;
                    }
                    else
                        channel = channel_rslt.front;

                    Connection.Type type;

                    switch(operation)
                    {
                        case "read":
                            type = type.Read;
                            break;
                        case "write":
                            type = type.Write;
                            break;
                        case "subscribe":
                            type = type.Subscribe;
                            break;
                        default:
                            import std.stdio;
                            writefln("%s: Unknown operation %s, skipping",
                                     app, operation);
                            continue;
                    }

                    connections ~= new Connection(type, appinst, channel);
                }
            }


    }

}


unittest
{
    string test_str =
`dataflow:
    reef:
        dht:
            subscribe:
                - adpan_metadata
                - campaign_metadata
                - currency_metadata
                - clearing_price_metadata
        dls:
            read:
                - adpan_*
        mysql:
            write:
                - daily_adv
                - daily_ssp
                - hourly_ssp_campaign_currency

    madtom:
        dht:
            subscribe:
                - campaign_metadata
                - campaign_optimization
                - campaign_ssp_yield
                - campaign_yield
                - currency_metadata
            write:
                - campaign_optimization
    thruster:
        dht:
            subscribe:
                - adpan_activity
                - adpan_metadata
                - campaign_metadata
                - campaign_optimization
                - campaign_yield
                - currency_metadata
                - ssp_data
            read:
                - admedia_metadata
                - admedia_categories
                - admedia_related
                - campaign_publisher_yield
                - publisher_yield
                - purchase_history
                - user_retargeting
                - user_yield
        dmq:
            write:
                - cliff
                - ysgadan
                - test_cliff
    cliff:
        dht:
            write:
                - bid_request_distribution
        dmq:
            read:
                - cliff
                - test_cliff
        mysql:
            write:
                - bid_hour_history
                - daily_bid_requests
    nautica:
        dht:
            read:
                - admedia_categories
                - admedia_metadata
                - admedia_related
                - adpan_metadata
                - campaign_metadata
            subscribe:
                - admedia_recommendation
            write:
                - admedia_related
        dls:
            read:
                - adpan_*
    wave-ripple:
        dht:
            subscribe:
                - admedia_source
                - adpan_metadata
            read:
                - admedia_metadata
            write:
                - admedia_metadata
        dmq:
            read:
                - admedia
            write:
                - images
    wave-wave:
        dht:
            subscribe:
                - admedia_source
                - adpan_metadata
            read:
                - admedia_metadata
            write:
                - admedia_metadata
        dmq:
            read:
                - images

    atlantis:
        dht:
            read:
                - admedia_metadata
                - admedia_source
                - adpan_metadata
                - campaign_metadata
        dls:
            read:
                - adpan_*
    ice:
        dls:
            write:
                - adpan_*
        dht:
            subscribe:
                - adpan_metadata
        dmq:
            read:
                - ice

`;

    import internal.yaml.parse;

    auto node = parseYAML(test_str);

    import std.stdio;

    Connection[] cons;
    Channel[] channels;
    App[] apps;

    parseFromYML(node, channels, cons, apps);
}
