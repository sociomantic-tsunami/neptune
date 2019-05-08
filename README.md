[![Build
Status](https://travis-ci.org/sociomantic-tsunami/neptune.svg?branch=v0.x.x)](https://travis-ci.org/sociomantic-tsunami/neptune)

Introduction
============

Neptune is a set of guidelines and tools to help developers and users to
implement a versioning scheme based on [SemVer](http://semver.org/).


Documentation
=============

The following documents are available:

* [Contributing to Neptune-Versioned
  Libraries](https://github.com/sociomantic-tsunami/neptune/blob/v0.x.x/doc/library-contributor.rst)
  is a guide to help library contributors to follow the Neptune versioning
  scheme.
* [Maintaining Neptune-Versioned
  Libraries](https://github.com/sociomantic-tsunami/neptune/blob/v0.x.x/doc/library-maintainer.rst)
  is a guideline to help library developers maintain a library following the
  Neptune versioning scheme.
* [Neptune Library Release
  Announcements](https://github.com/sociomantic-tsunami/neptune/blob/v0.x.x/doc/announcements.md)
  is a anex to the previous guideline on how to make release announcements.
* [Using Neptune-Versioned
  Libraries](https://github.com/sociomantic-tsunami/neptune/blob/v0.x.x/doc/library-user.rst)
  is a guideline for users of Neptune based libraries, to help them know how and
  when to upgrade.
* [Maintaining Neptune-Versioned
  Applications](https://github.com/sociomantic-tsunami/neptune/blob/v0.x.x/doc/application-maintainer.rst)
  is a guideline for application developers (and ultimately users too) to help
  them maintain applications using the Neptune versioning scheme.
* [Neptune Metadata File](https://github.com/sociomantic-tsunami/neptune/blob/v0.x.x/doc/neptune-metadata.rst)
  documents how different tools can use metadata attached to projects via a
  `.neptune.yml` file.

Tools
=====

The repository includes:

[Overview](https://github.com/sociomantic-tsunami/neptune/tree/v0.x.x/src/overview)
--------

Fetches repositories for a selected GitHub organization and builds an HTML
overview of applications and libraries that shows which version of each library
is used in each application.


[Release](https://github.com/sociomantic-tsunami/neptune/tree/v0.x.x/src/release)
-------

Automates all the tasks required to make a release abiding to the neptune
specification, including some sanity checks. Tasks include:

* Autodetection of what type of release is being done (major, minor, patch)
* Merging of features and bugfixes into higher versions
* Creation of releases, including their tags, release notes and github releases
