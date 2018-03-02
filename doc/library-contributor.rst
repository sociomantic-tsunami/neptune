===========================================
Contributing to Neptune-Versioned Libraries
===========================================

This is a guide for contributors to libraries which are using a strict,
Neptune-based versioning scheme. Users of Neptune-versioned libraries should
also read `Using Neptune Libraries <library-user.rst>`_ and maintainers of
Neptune-versioned libraries should read
`Maintaining Neptune Libraries <library-maintainer.rst>`_.

.. contents::

Release Notes
-------------

The ``neptune-release`` tool automatically collates release notes when making a
release. To make this possible, contributors must follow the following
guidelines.

Major and Minor Releases
........................

When making a commit to a Neptune-versioned library, API-affected changes should
be noted in a file in the ``relnotes`` folder, as follows. When the
corresponding branch is released, the files in that folder will be collated to
form the notes for the release.

The following procedure should be followed:

1. Look at each commit you're making and note whether it contains any of the
   following:

   * Breaking changes to user-available features (i.e. to the library's API).
   * New user-available features.
   * Deprecations of user-available features.

2. For each change noted in step 1, write a description of the change. The
   descriptions should be written so as to be understandable to users of the
   library and should explain the impact of the change, as well as any helpful
   procedures to adapt existing code (as necessary).

   The descriptions of changes should be written in the following form::

     ### Catchy, max 80 characters description of the change

     `name.of.affected.module` [, `name.of.another.affected.module`]

     One or more lines describing the changes made. Each of these description
     lines should be at most 80 characters long.

3. Insert your descriptions into files in the library's ``relnotes`` folder,
   named as follows: ``<name>.<change-type>.md``:

   * ``<name>`` can be whatever you want, but should indicate the change made.
   * ``<change-type>`` should be one of: ``migration``, ``feature``,
     ``deprecation``.
   * e.g. ``add-suspendable-throttler.feature.md``,
     ``change-epoll-selector.migration.md``.

   Normally, you'll create a new file with the selected name, but it's also ok
   to add further notes to an existing file, if the new changes fall under the
   same area. It is also sometimes possible that a change will require the
   release notes for a previous change to be modified.

4. Add your release notes in the same commit where the corresponding changes
   occur.

Patch Releases
..............

Descriptions of bug fixes are not added to the ``relnotes`` folder. Instead, the
titles of bug fix pull requests are used to generate the release notes for a
patch release. It is thus important to choose a clear and descriptive name for
PRs containing bug fixes.

