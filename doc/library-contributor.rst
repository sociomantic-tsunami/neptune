===========================================
Contributing to Neptune-Versioned Libraries
===========================================

This is a guide for contributors to libraries which are using a strict,
Neptune-based versioning scheme. Users of Neptune-versioned libraries should
also read `Using Neptune Libraries <library-user.rst>`_ and maintainers of
Neptune-versioned libraries should read
`Maintaining Neptune Libraries <library-maintainer.rst>`_.

.. contents::

How to become a contributor and submit your own code
----------------------------------------------------

We'd love to accept your issues and (especially) patches! If you have found a
bug you can submit an issue describing it and one of the repo maintainers will
get back to you. Alternately you can submit a PR and the sections below outline
the process.

Contributing a Patch
.....................

1. Fork the desired repo, develop and test your code changes.

2. Ensure that your code has an appropriate set of unit tests which all pass.

3. Break your changes into a series of logical self-contained commits.

4. Include release notes files when appropriate following the guidelines
   below.

5. Submit your pull request.

Reviewing and Rebasing and Merging Patches
...........................................

1. All feedback should be professionally given and non-personal. Offensive,
   intimidating, insulting, racist, homophobic, and sexist comments and
   behavior will not be tolerated.

2. Reviewers will comment on your code providing feedback to point out any
   problems and improve the quality of the code. Feel free to respond to these
   comments if you have any questions to clarify the meaning of the comments.

3. Please try and pay attention to all the comments and address them all.

4. Reviewers can mark a PR as "changes requested" or "approved".

5. Once a PR has been approved by at least one reviewer and they are no
   outstanding comments that have not been addressed from other reviewers,
   either a reviewer or the submitter (providing they have push access) can
   rebase and merge the PR.

6. Repo owners try to review PRs promptly, you can feel free to give a "Ping!"
   if there has been no response for a few days.

Release Notes
-------------

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

