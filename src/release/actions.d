/*******************************************************************************

    Action System Definitions

    Before any actual modification is done, all actions are collected and
    presented to the user.

    To enable this, every function returns (and optionally receives) an instance
    of ActionList which the caller then appends to their instance and so on
    so that a list of actions is accumulated.

    That list will then be shown to the user and after a confirmation executed
    in the order in which they were appended.

    Copyright:
        Copyright (c) 2017 sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module release.actions;

/// Interface for an action
interface Action
{
    /***************************************************************************

        Called to execute the action

        Returns:
            output of the command than ran

    ***************************************************************************/

    string execute ( );

    /// Returns the description of the action
    string description ( ) const;

    /// Returns the command the action does
    string command ( ) const;
}

/*******************************************************************************

    Structure to collect actions and metatadata about those actions

*******************************************************************************/

struct ActionList
{
    /// List of actions to execute, local only
    Action[] actions;

    /// tags/branches that were locally modified and will be pushed
    string[] affected_refs;

    /// Release notes per version
    string[string] release_notes;

    /***************************************************************************

        Appends one action list to another

        Params:
            op = append operator
            list = list to append

        Returns:
            reference to this

    ***************************************************************************/

    ref ActionList opOpAssign ( string op ) ( ActionList list )
        if (op == "~")
    {
        this.actions ~= list.actions;
        this.affected_refs ~= list.affected_refs;

        foreach (ver, notes; list.release_notes)
            this.release_notes[ver] = notes;

        return this;
    }

    /// Resets internal members
    void reset ( )
    {
        this.actions.length = 0;
        this.affected_refs.length = 0;
        this.release_notes.clear();
    }
}

/*******************************************************************************

    Structure to define a command to be run locally along with a description of
    it

*******************************************************************************/

class LocalAction : Action
{
    /// The command this action is going to run
    string _command;

    /// The description of this command
    string _description;

    /***************************************************************************

        C'tor

        Params:
            command = command to execute
            description = description of the action


    ***************************************************************************/

    this ( string command, string description )
    {
        this._command = command;
        this._description = description;
    }

    /***************************************************************************

        Executes the command

        Returns:
            command output

    ***************************************************************************/

    override string execute ( )
    {
        import release.shellHelper;
        import std.string : strip;

        return strip(cmd(this.command()));
    }

    /***************************************************************************

        Returns:
            description of the action

    ***************************************************************************/

    override string description ( ) const
    {
        return this._description;
    }

    /***************************************************************************

        Returns:
            command to be run

    ***************************************************************************/

    override string command ( ) const
    {
        return this._command;
    }
}
