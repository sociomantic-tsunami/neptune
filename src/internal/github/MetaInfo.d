/*******************************************************************************

    Structure to extract & remember meta information about all repositories

    Copyright:
        Copyright (c) 2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module internal.github.MetaInfo;

import internal.yaml.parse;

import dyaml.node;

import std.typecons : Nullable;


/// Structure to extract & remember meta information about all repositories
class MetaInfo
{
    import vibe.data.json;

    /// Encapsulates meta information about a repository
    struct MetaInfo
    {
        /// Neptune file object internal ID
        public string neptune_id;

        /// Yaml parse result of neptune file
        public Nullable!Node neptune_yaml;

        /// Submodule hashes: name => sha
        public string[string] submodules;

        /// default branch name
        public string def_branch;

        /// name of owner of repo
        public string owner;

        /// Sha of latest commit
        public string latest_commit_sha;

        // Sha of the tree of the latest commit
        public string latest_commit_tree_sha;
    }

    /// Name of the neptune definition file
    enum NeptuneFile = ".neptune.yml";
    /// Name of the submodules folder
    enum Submodules  = "submodules";

    /// Hashmap of owner/repo -> metainfo
    MetaInfo[string] meta_info;

    /// Query to extract our info
    enum Query = `
{
  name
  owner { login }
  defaultBranchRef {
    name
    target {
      ... on Commit {
        oid
        tree {
          oid
          ... on Tree {
            entries {
              name
              object {
                id
                ... on Tree {
                  entries {
                    name
                    oid
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
`;

    /// Query to fetch the individual neptune files in one go
    enum NodeQuery = `
nodes(ids:%s) {
    id
    ... on Blob {
      text
    }
}
`;

    /***************************************************************************

        Process one repository entry, extracting submodule & netptune sha info
        as well as owner of the repo

        Params:
            json = json of one query result entry

    ***************************************************************************/

    public void processEntry ( Json json )
    {
        import internal.json;
        import std.format : format;

        MetaInfo info;

        info.owner = json["owner"]["login"].get!string;

        if (json["defaultBranchRef"].type != Json.Type.null_)
        {
            info.latest_commit_sha =
                json.path!"defaultBranchRef.target.oid".get!string;
            info.latest_commit_tree_sha =
                json.path!"defaultBranchRef.target.tree.oid".get!string;
            info.def_branch = json.path!"defaultBranchRef.name".get!string;

            auto root_entries =
                json.path!"defaultBranchRef.target.tree.entries";

            // Iterate through top level files
            foreach (entry; root_entries)
            {
                // Found neptune, remember id
                if (entry["name"] == NeptuneFile)
                    info.neptune_id = entry["object"]["id"].get!string;
                // Found submodule dir, iterate files
                else if (entry["name"] == Submodules)
                {
                    // Remember SHA of each submodule entry
                    foreach (submodule; entry["object"]["entries"])
                        info.submodules[submodule["name"].get!string] =
                        submodule["oid"].get!string;
                }
            }
        }
        else
        {
            import std.stdio;
            writefln("No default branch found: %s", json);
        }

        auto key = format("%s/%s", info.owner, json["name"].get!string);

        this.meta_info[key] = info;
    }

    /***************************************************************************

        Parses all neptune file contents and caches the result

        Params:
            nodes = json containing the nodes

    ***************************************************************************/

    public void extractNeptuneYaml ( Json nodes )
    {
        import internal.yaml.parse;
        import std.format;

        foreach (name, ref entry; this.meta_info)
        foreach (neptune_file; nodes) try
        {
            if (entry.neptune_id != neptune_file["id"].get!string)
                continue;

            entry.neptune_yaml = parseYAML(neptune_file["text"].get!string);
        }
        catch (Exception exc)
        {
            import std.stdio;
            writefln("%s: Failed to parse yml: %s", name, exc.msg);
        }
    }
}
