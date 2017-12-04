==========================================
Maintaining Neptune-Versioned Applications
==========================================

This guide is intended to help having a common ground when versioning
applications, in particular applications that are deployed to provide services,
but it could probably be extended to other type of applications. The goal is to
let users and people affected by changes in applications quickly know what to
expect on new releases.

Since applications have very different impact and some are more critical than
others, it is very hard to have a strict guideline like with `libraries
<library-maintainer.rst>`_, so this is just a guideline and each project must
adapt it to what works best for it.

.. contents::


Version Numbers
===============

Numbering versions of releases should follow `SemVer 2.0 <http://semver.org/>`_.
This only means, a version number should have the form::

  X.Y.Z[-P][+M]

Where:

X
  is the **Major** version
Y
  is the **Minor** version
Z
  is the **Patch** version
P
  is a pre-release identifier (optional)
M
  is build metadata (optional)

For more details on which kind of characters can be used on each, please
consult the SemVer guide. The meaning of these numbers, though, does not
strictly match the SemVer guide because SemVer is defined for libraries and
around APIs, while applications have other types of interfaces, like network
protocols, end users, etc.).


General Guideline
=================

These are the most general guidelines presented, and ideally all applications
should follow these principles.

Since for applications the most important thing to know on new releases is how
risky it is to deploy the new release, version numbers should indicate that:
how likely it is that something breaks after a release.

Patch Releases
--------------
Patch releases should include only minimal changes, and be close to zero risk to
deploy.

People interacting with or affected by the application should be able to ignore
any patch releases. No other applications should need to be updated to be able
to deploy a new patch release.

Minor Releases
--------------
Minor releases should be comparatively low risk. People interacting with or
affected by the application should be notified and should care about the
update, but it should be safe to assume that it is very unlikely that something
could break because of the upgrade.

Major Releases
--------------
Major releases should be made only when major breaking changes, refactoring or
rewrites occur. Major versions come with a higher risk of breakage, and since
they normally carry breaking changes affecting other applications, they
usually can't be rolled back without also rolling back other applications.
Because of this, they should be closely monitored and not only by the
maintainers but also by people interacting with or affected by the application.

The special major version 0 (v0.x.x series) should only be used for new
applications being deployed for testing, when they don't affect the live system
yet (for example, a new application that reads data and generates results, but
the results are not used by any other applications yet). Once an application is
fully integrated into the live system, a major version > 0 should be used.


Stricter Guideline
==================

It is recommended, when possible, to adhere also to this stricter guideline,
providing a few stricter rules on what each type of release can do. This is
just a more specialized and stricter version of what was already said in this
document.

Patch Releases
--------------
When an application is running stably on the live system and an isolated bug is
found, the fix should be applied to the exact running version and a new patch
release should be made. For example, if v2.3.1 is running and a bug is found
and fixed, the commit should be applied on top of v2.3.1 and the new release
should be called v2.3.2.

Any other changes that are not purely bug fixes should be done as part of
a minor or major release.

Minor Releases
--------------
When new features are released, or minor code refactoring is performed on the
application, but such changes don't affect other applications interacting with
this one, a minor release should be made. These releases have higher risk of
introducing new bugs than patch releases, but the risk should be still
relatively small.

Any updates that require changes to other applications should be done as part
of a major release.

Major Releases
--------------
Major releases should be performed when the application is updated in a way that
requires changes in other applications for the whole system to be able to keep
running (for example breaking changes in the protocol, or serialized data).

Also when the application has gone through major surgery and the risk of
breakage is very high, a major release could be performed to indicate the high
risk of the update.

Pre-Releases
------------

Pre-release strings (as in ``v2.1.1-<string>``) should be used when deploying
a test binary that will be run in one server or instance only for example.
Anything that is a temporary test deploy should have a ``-<string>`` indicator
in the version string. It is recommended to use common identifiers, like
``-alpha1``, ``-beta1``, ``-rc.1`` (depending on the level of trust there is
that it will be the final version), and increment the number each time a bug is
fixed in that version and is re-deployed for testing.

When doing the final deploy, a new final tag (without the ``-<string>``) should
be created and used for the deploy, even if no issues were found in the testing
and both tags point to the same commit.

