=======================================
Maintaining Neptune-Versioned Libraries
=======================================

This is a guide for maintainers of libraries which are using a strict, Neptune-
based versioning scheme. After some discussion, it provides a set of simple,
step-by-step guides describing the common procedures for various actions that
you'll need to perform as a maintainer of a Neptune-versioned library.

You should first read `Using Neptune-Versioned Libraries <neptune-user.rst>`_ to
get a grounding in the principles and theory of Neptune from the point-of-view
of a user of a library.

.. contents::

Branches, Tags, and Milestones
------------------------------

Library maintainers need to be careful to manage these correctly, as follows.

Version Branches
~~~~~~~~~~~~~~~~

At any given point of time, there must be at least these branches in the git
repo:

* The last released major version (e.g. v3.x.x), which is used for all feature
  development and is configured to be the default branch in GitHub.
* The last feature release (e.g. v3.1.x), where all bug fixes go by default.

Also, when the necessity of a breaking change is identified, the following
branch may also exist:

* The next planned major version (e.g. v4.x.x), where all long term cleanups and
  breaking changes go.

Every branch which refers to a version being maintained (receiving bug-fixes) or
developed (receiving new features) should have at least one *.x* in its name.

Release Tags
~~~~~~~~~~~~

Each release must have a corresponding tag. Release tags should have all
concrete numbers (no x's in the name).

Github Milestones
~~~~~~~~~~~~~~~~~

The issues addressed in each release should be grouped together in a milestone
with the same name as the release-to-be.

e.g. if you're planning a patch release on top of the already released v2.2.0,
you'd open a milestone named v2.2.1 and add the required issues to it. When all
issues in the milestone have been addressed, you should be ready to make the
release.

Example
~~~~~~~

* Current major/minor branch being developed (receiving new features): v3.x.x
* Current major/minor branch being maintained (receiving bug-fixes): v3.1.x
* Last released version: v3.1.1
* Milestone for the next patch release: v3.1.2
* Milestone for the next minor release: v3.2.0
* Next unreleased major: v4.x.x
* Milestone for next major release: v4.0.0

Removing the Master Branch
~~~~~~~~~~~~~~~~~~~~~~~~~~

When you start using Neptune versioning in a library, it is recommended that the
master branch be removed from the repository. This is not strictly necessary
from the git point of view but is related to how GitHub works.

The "default" base branch can be configured in the GitHub web interface. As the
most common type of pull request is adding a new feature, it makes most sense to
configure the repository to have the oldest supported major version branch as
the default one.

However, having a default branch which isn't ``master`` can be confusing for
those who are used to the more common GitHub repository model -- first
experiments have shown that developers make less mistakes when all branches have
an explicit relation with versions in their names.

Because of that, we suggest removing ``master`` and configuring the repository
to use the latest supported major version as the default -- changing it each
time the major version's support lifetime comes to an end.

A Note on Updating Submodules
-----------------------------

For libraries which include other libraries as submodules, it is important to
ensure that the usual Neptune rules for maintaining compatibility of users' code
are followed:

* In a patch release, it is safe to update submodules to new patch releases, as
  these will only include bug-fixes.
* In a minor release, updating a submodule to a minor release is acceptable, as
  long as no code changes are made (e.g. using newly introduced features) so
  users are not forced to also update their applications' submodules. (The
  reason for this clause is the following: as only a limited number of minor
  releases are maintained with bug-fixes, it is often the case that, in order to
  get a bug-fix, a submodule must be updated to a currently maintained new
  *minor* version.)
* In a major release, submodules may be updated to any version and code adapted
  to use new features as desired.

When to Make a Release
----------------------

* Patch releases should be made as soon as bug-fixes are committed, ensuring
  that users can update swiftly to the fixed code.
* Minor releases may be made as necessary. Unless there is pressing need for new
  features to be released, the release frequency should be limited to, for
  example, roughly once a month.
* Major releases should not be made frequently, as they usually require a
  greater update effort from users. One major release per specified support
  period of the library is reasonable. One thing to be careful of is not to make
  a major release prematurely. Once a new major version has been released, the
  corresponding major branch *cannot* accept any further breaking changes. That
  means it is a good idea to wait some time before tagging the first release of
  a new major branch, in case more breaking changes will be needed.

How to Make a Release
---------------------

1. Create a tag at the head of the appropriate branch. The tag should have all
   "concrete" numbers (i.e. no "x"s) and be annotated (an annotated tag is a
   real git object and has a message associated with it, specified by the ``-m``
   option). e.g. ``git tag -m v1.23.5 v1.23.5``
2. Push the tag to the upstream repo.
3. Create a new github release corresponding with the tag.
4. The release notes should contain a link to the milestone which corresponds
   to the release, plus one of the following:

   * For patch releases, links to the issues fixed in the release (or the PRs
     which fixed the issues), along with a one-line description of what was
     fixed (e.g. the PR or issue title).
   * For minor and major releases, the full release notes text for the
     release, including descriptions of migration instructions, deprecations,
     new features, etc.

5. Close the milestone associated with the release.

Patch Releases
~~~~~~~~~~~~~~

Patch releases consist of commits on top of an already released minor branch and
may only contain bug-fixes.

1. Add commits to the appropriate minor branch.
2. When ready, make the release as described above.
3. Merge the release tag into subsequent branches (see below).

Note: in the rare case of a critical bug-fix (e.g. a bug which may result in
memory corruption, wrong business logic, etc.) which breaks existing, semi-valid
code, these additional steps must be followed:

1. Mention the breaking change clearly in the release notes.
2. Append `+breaking` to the tag of the patch release.
3. Make a special announcement, informing users of the exceptional breaking
   change and the reason for including it in a patch release.

e.g. if you discover problems in the already released v1.10.0, after adding bug-
fix commits to v1.10.x, you should tag and release v1.10.1.

Minor Releases
~~~~~~~~~~~~~~

Minor releases consist of commits on top of an already released major branch and
may contain new features, deprecations, and minor internal refactorings that
don't affect the API. (Note that a minor release should not contain bug-fixes.
Those should be made in a patch release, separately, applied to all supported
minor branches.)

1. Add commits to the appropriate major branch.
2. When ready, make the release (see above).
3. You may also create a minor branch which will receive future bug-fixes.
4. Merge the release tag into subsequent branches (see below).
5. Make a new commit to the major branch clearing the release notes from the
   just-made release.

e.g. if you are developing v1.x.x and have previously released v1.10.0, after
adding more commits to v1.x.x, you should tag and release v1.11.0 and create
minor branch v1.11.x.

Major Releases
~~~~~~~~~~~~~~

Major releases consist of commits on top of an unreleased major branch and may
contain breaking changes to the API (including bug-fixes or new features which
require API changes), removal of deprecations, or larger refactorings. (Note
that a major release should not contain bug-fixes, deprecations, or new
features, unless they require an API change. Those should be made in a minor or
patch release, separately.)

1. Add commits to the appropriate unreleased major branch.
2. When ready, make the release (see above).
3. Create the next major branch which will receive future breaking changes.
4. Inform users of the now-limited support period of the previous major
   branch.
5. Make a new commit to the next major branch clearing the release notes from
   the just-made release.

e.g. if you have added commits to the unreleased v3.x.x and it's time to make a
major release, you should tag and release v3.0.0 and create the next major
branch v4.x.x.

Merging Releases
----------------

When changes are made in one branch, you naturally want those changes to
propagate to other maintained branches. The exact branches you need to merge
into depends on the type of the release that you just made. More details below.

General things to look out for when merging:

* If you're merging from a major branch into a future (i.e. as yet unreleased)
  major branch, you can remove any deprecations in the source branch.
* You'll get conflicts in the release notes. Make sure that you remove release
  notes from the source branch (they should only appear in that release).

Merging Patch Releases
~~~~~~~~~~~~~~~~~~~~~~

After making a patch release, you need to make sure that subsequent branches
also receive the bug-fixes.

1. Merge the patch release tag into any subsequent minor branches and make a
   patch release for each of them.
2. Merge the patch release on the latest minor branch into the corresponding
   major branch.
3. If the next major branch already has one or more releases, repeat 1 and 2 for
   the corresponding minor branches.

e.g. if maintained minor branches v1.20.x and v1.21.x and minor release tags
v1.20.1 and v1.21.2 exist, a bug-fix applied to v1.20.x and released as v1.20.2
should be merged into v1.21.x and released as v1.21.3. v1.21.3 would then be
merged into v1.x.x. If the newer major branch v2.x.x exists, along with minor
branch v2.0.x and release tag v2.0.0, then v1.21.3 would be merged into v2.0.x
and released as v2.0.1. v2.0.1 would then be merged into v2.x.x.

Merging Minor Releases
~~~~~~~~~~~~~~~~~~~~~~

After making a minor release, you need to make sure that subsequent branches
also receive the new features.

1. Merge the minor release tag into any subsequent major branches.
2. Optionally, make a minor release on the subsequent major branches.

e.g. if a minor release v1.2.0 is made (by tagging the head of v1.x.x) and the
newer major branch v2.x.x exists, then v1.2.0 would then be merged into
v2.x.x. The new head of v2.x.x may optionally be tagged and released.

Merging Non-Released Branches
-----------------------------

It's fine to merge from one major branch to another at any time, as required --
you don't need to make a release every time. It can be useful to make a habit of
making such merges so as to minimise the amount of changes that need to be
merged at once, thus easing maintenance.

e.g. if you've added new, unreleased features in v3.x.x, you can merge into
v4.x.x at any time, to bring the new features into the next major branch.

Example Branch Graph
--------------------

Putting all of the above together, an example of how part of the evolution of a
Neptune-versioned library might look follows.

Lines define branches and their relations:

- ``-``: commit history for a branch (left == older)
- ``/`` or ``\``: merging (always happens from lower version to higher one)
- ``|``: tagging or forking a branch

Letters within a dashed line highlight different types of commits:

- ``B``: commit with a bug-fix
- ``F``: commit with backwards-compatible feature
- ``D``: commit which deprecates symbols
- ``X``: commit with a breaking change
- ``M``: merge commit

.. code::

                                     .---X--X--X--M--F--X--F----F----M--> v4.x.x
                                    /            /       \          /
                                   /            /         +-B--M---B----> v4.0.x
                                  /       .----´          |   /    |
                                 /       /            v4.0.0 /  v4.0.1
                                /       /     .-------------´
                               /       /     /
     --F--F-----M--F--M--F-D--D--F-F--M-----M--------------------F------> v3.x.x
           \   /     /         \     /     /                     |\
            +-B--B--B--.        +---B--B--B--.                   | `----> v3.2.x
            | |     |   \       |   |     |   \               v3.2.0
       v3.0.0 |  v3.0.2  \   v3.1.0 |  v3.1.2  `------------------------> v3.1.x
           v3.0.1         \      v3.1.1
                           `--------------------------------------------> v3.0.x

Note that, for simplicity, this graph assumes that only the latest minor release
gets bug-fixes. In practice, this may not be true for more mature libraries and
bug-fixes will be based on v3.0.x even if v3.1.0 has been already released. In
this case, v3.0.3 would be first merged to v3.1.x and only later would v3.1.3 be
merged into v3.x.x.

