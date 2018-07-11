===========================================
Contributing to Neptune-Versioned Libraries
===========================================

This is a guide for contributors to libraries which are using a strict,
Neptune-based versioning scheme. Users of Neptune-versioned libraries should
also read `Using Neptune Libraries <library-user.rst>`_ and maintainers of
Neptune-versioned libraries should read
`Maintaining Neptune Libraries <library-maintainer.rst>`_.

.. contents::

Submitting Pull Requests
------------------------

When making a PR to a Neptune-versioned library, the choice of which branch to
submit a PR against is important. A branch should be chosen as follows:

* If your change is a bug fix, the PR should be submitted against the oldest
  supported minor branch. The name of the PR will be listed in the release notes
  of the release (see Patch Releases, below).
* If your change is a new feature, refactoring, or deprecation, the PR should be
  submitted against the oldest supported major branch.
* If your change is a breaking change to the API, the PR should be submitted
  against the next unreleased major branch.

Release Notes
-------------

The ``neptune-release`` tool automatically collates release notes when making a
release. To make this possible, contributors must write release notes in a
specific format (described below), and place them in the ``relnotes`` folder.
When the corresponding branch is released, the files in that folder will be
collated to form the notes for the release.

The following procedure should be followed:

1. Look at each commit you're making and note whether it contains any of the
   following:

   * Breaking changes to user-available features (i.e. to the library's API).
   * New user-available features.
   * Deprecations of user-available features.
   * Bug fixes that warrant a note to users of the library. (Also see Patch
     Releases, below.)

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
     ``deprecation``, ``bug``.
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

For patch releases, a list of all fixed issues will additionally be appended to
the release notes. The title of the bug fix pull request is used for this, so it
is important to choose a clear and descriptive name for PRs containing bug
fixes.

