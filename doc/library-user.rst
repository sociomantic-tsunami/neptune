=================================
Using Neptune-Versioned Libraries
=================================

This is a guide for users of libraries which are using a strict, Neptune-based
versioning scheme. Maintainers of Neptune-versioned libraries should also read
`Maintaining Neptune Libraries <library-maintainer.rst>`_.

.. contents::

Goals
-----

1. To separate feature additions from bug-fixes. To separate feature additions
   and bug-fixes from breaking changes and major refactorings.
2. To allow a much longer adaptation time span for application projects to
   perform "risky" library upgrades.
3. To enable a more flexible, on-demand release model.

Release Version Numbers
-----------------------

All library releases have a version number with the pattern **X.Y.Z**, where:

- **X** (major release) is incremented for removal of deprecated symbols,
  refactorings that affect API, or any major semantical changes in general.
- **Y** (minor release) is incremented for new features, deprecations,
  and minor internal refactorings that don't affect the API.
- **Z** (patch release) is incremented only for non-intrusive bug fixes
  that are always 100% safe to upgrade to.

Version Branches and Tags
~~~~~~~~~~~~~~~~~~~~~~~~~

The library maintainers will create the following branches and tags:

* One branch per major version. e.g. v3.x.x, v4.x.x.
* One branch per minor version. e.g. v3.1.x, v3.2.x.
* One tag per released version. e.g. v3.1.0, v3.1.1.

Upgrade Guarantees
------------------

The Neptune versioning scheme makes it clear to users what kind of changes are
included in a library release and to provide guarantees about what is required
to update an application to the release:

* Upgrading to a new major version may require code changes, as the release may
  include breaking changes to the library's API.
* Users can upgrade to any new minor version without being ever forced to change
  anything in their code. Deprecation warnings may appear, but these do not
  require immediate action.
* Users can upgrade to any new patch release without being ever forced to change
  anything in their code and with the added safety of no new features
  potentially introducing accidental changes/bugs.

Exceptions
~~~~~~~~~~

(As with all good rules, there are exceptions...)

Normally, patch releases do not introduce breaking changes -- users can upgrade
without having to modify anything in their own code. However, sometimes a proper
bug-fix may cause existing semi-valid code to stop compiling. Such fixes are
handled as follows:

1. If the addressed bug is critical (i.e. may result in memory corruption, wrong
   business logic, etc.), it will be released as a patch release. The release
   notes will clearly indicate that a breaking change has been made and the
   tag of the patch release will have `+breaking` appended.

2. If the fixed issue is non-critical, it will be delayed until the next major
   release (following the normal Neptune guarantees).

Support Guarantees
------------------

The maintainers of the library must define the following, clearly stating both
in the library's ``README.rst``.

Major Version Support Period
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The support period of the previous major version. This defines how long the last
major version will be developed (i.e. receive new features by default), after a
new major version is released. This is usually 3 or 6 months.

Once a major version goes out of support, it will only receive critical
bug-fixes on demand.

e.g. if a library defines the major version support period as 3 months and
v4.0.0 is released on April 1st, v3.x.x should remain as the default developed
version -- and thus receive new features and bug fixes -- until July 1st.

Supported Minor Versions
~~~~~~~~~~~~~~~~~~~~~~~~

The number of previous minor releases which are supported. This defines how many
minor releases will automatically receive bug-fixes. A library must support at
least the last minor release of any developed major version and may opt to
guarantee support for more than just the last minor release.

e.g. if a library declares support for the last two minor versions and a bug is
discovered in v3.x.x with releases v3.1.0, v3.2.0, and v3.3.0, versions v3.2.0
and v3.3.0 (the two most recent minor releases) must be patched with the
bug-fix. Patch releases v3.2.1 and v3.3.1 must be made.

Once a minor version goes out of support, it will only receive critical
bug-fixes on demand.

When Releases are Made
----------------------

* Patch releases are made whenever bug-fixes are made. This ensures that an
  updated version of the library, including the fix, is availabel to users as
  soon as possible.
* Minor releases are made as necessary. If no pressing need for a release
  arises, a new feature release once a month is typical.
* Major releases are made only infrequently, as they generally require greater
  effort for library users to update their code to. A major release per
  specified support period of the library (see above) is typical.

Contributing to a Neptune-Versioned Library
-------------------------------------------

When you have commits to add to a library, you must think about the type of
changes made in order to determine which branch to base your commits on:

* Bug-fixes should be based on the oldest supported minor version branch.
* New features, deprecations, or minor internal refactorings shold be based on
  the current default major version branch. Note that some new features are only
  possible to implement based on top of large refactorings or breaking changes
  which occur in a newer major version. In this case, it is fine to apply the
  new feature only to the newer major branch, not on the current default.
* API changes should be based on the next unreleased major version branch.

Note that you should carefully separate the three types of changes into
individual pull requests, even if you have changes which build on top of each
other.

