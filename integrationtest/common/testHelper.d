module integrationtest.common.testHelper;

import std.stdio : File;

string getAsyncStream ( File stream )
{
    import vibe.stream.stdio;
    import vibe.stream.operations;

    auto stdstream = new StdFileStream(true, false);

    stdstream.setup(stream);

    return stdstream.readAllUTF8();
}
