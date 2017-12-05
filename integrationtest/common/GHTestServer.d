/*******************************************************************************

    Github Test Server class

    Copyright:
        Copyright (c) 2017 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.common.GHTestServer;

import vibe.data.json;
import vibe.web.rest;

/// Json API offered by the GH test server
interface IRestAPI
{
    @path("repos/:owner/:name")
    Json getRepos ( string _owner, string _name );

    @path("repos/:owner/:name/branches")
    Json getBranches ( string _owner, string _name );

    @path("repos/:owner/:name/releases")
    Json getReleases ( string _owner, string _name );

    @path("repos/:owner/:name/tags")
    Json getTags ( string _owner, string _name );

    @path("repos/:owner/:name/milestones")
    Json getMilestones ( string _owner, string _name );

    @path("repos/:owner/:name/releases")
    Json postReleases ( string _owner, string _name, string tag_name,
                        string name, string body_, string target_committish );
}

/// Implementation of the JSON API
class RestAPI : IRestAPI
{
    /// Structure collecting data about a release
    struct Release
    {
        string name;
        string tag_name;
        string content;
        string target_committish;
        bool draft;
    }

    struct Ref
    {
        string name;
        string sha;
    }

    /// Releases done over the API so far
    Release[] releases;

    /// Tags that gh should be aware of
    Ref[] tags;

    /// Branches that gh should be aware of
    Ref[] branches;

    void reset ( )
    {
        this.releases.length = this.tags.length = 0;
    }

    /***************************************************************************

        Repos API endpoint

        Params:
            _owner = owner of the qeueried repo
            _name  = name of the repo

        Returns:
            a dummy repo response containing always the requested repo

    ***************************************************************************/

    Json getRepos ( string _owner, string _name )
    {
        return this.prepJson(_owner, _name);
    }

    /***************************************************************************

        Branches API endpoint

        Params:
            _owner = owner of the qeueried repo
            _name  = name of the repo

        Returns:
            empty json array (no branches)

    ***************************************************************************/

    Json getBranches ( string _owner, string _name )
    {
        auto ret = Json.emptyArray;

        foreach (branch; this.branches)
        {
            Json jsn = Json.emptyObject, cmmt = Json.emptyObject;

            cmmt["sha"] = branch.sha;
            jsn["name"] = branch.name;
            jsn["commit"] = cmmt;

            ret ~= jsn;
        }

        return ret;
    }

    /***************************************************************************

        Releases API endpoint

        Params:
            _owner = owner of the qeueried repo
            _name  = name of the repo

        Returns:
            empty json array (no releases)

    ***************************************************************************/

    Json getReleases ( string _owner, string _name )
    {
        return serializeToJson(this.releases);
    }

    /***************************************************************************

        Tags API endpoint

        Params:
            _owner = owner of the qeueried repo
            _name  = name of the repo

        Returns:
            empty json array (no tags)

    ***************************************************************************/

    Json getTags ( string _owner, string _name )
    {
        auto ret = Json.emptyArray;

        foreach (tag; this.tags)
        {
            Json jsn = Json.emptyObject, cmmt = Json.emptyObject;

            cmmt["sha"] = tag.sha;
            jsn["name"] = tag.name;
            jsn["commit"] = cmmt;

            ret ~= jsn;
        }

        return ret;
    }

    /***************************************************************************

        Milestones API endpoint

        Params:
            _owner = owner of the qeueried repo
            _name  = name of the repo

        Returns:
            empty json array (no milestones)

    ***************************************************************************/

    Json getMilestones ( string _owner, string _name )
    {
        return Json.emptyArray;
    }

    /***************************************************************************

        Release creation API endpoint

        Params:
            _owner = owner of the qeueried repo
            _name  = name of the repo
            tag_name = name of the tag to associate the release with
            title = title of the release
            body_ = content of the release
            target_committish = ref object to associate the release with

        Returns:
            empty json object

    ***************************************************************************/

    Json postReleases ( string _owner, string _name, string tag_name,
                        string title, string body_, string target_committish )
    {
        this.releases ~= Release(title, tag_name, body_, target_committish);

        return Json.emptyObject;
    }

    /***************************************************************************

        Sets common json response fields

        Params:
            owner = owner to set
            name  = repository to set

        Returns:
            A json object with common values set according to the parameters

    ***************************************************************************/

    private Json prepJson ( string owner, string name )
    {
        auto json = Json.emptyObject;

        json["owner"] = Json.emptyObject;
        json["owner"]["login"] = owner;
        json["name"] = name;

        return json;
    }
}
