[![Build
Status](https://travis-ci.org/sociomantic-tsunami/neptune.svg?branch=master)](https://travis-ci.org/sociomantic-tsunami/neptune)

Introduction
============

Neptune is a set of guidelines and tools to help developers and users to
implement a versioning scheme based on [SemVer](http://semver.org/).


Documentation
=============

The following documents are available:

* [Maintaining Neptune-Versioned
  Libraries](https://github.com/sociomantic-tsunami/neptune/blob/master/doc/library-maintainer.rst)
  is a guideline to help library developers maintain a library following the
  Neptune versioning scheme.
* [Neptune Library Release
  Announcements](https://github.com/sociomantic-tsunami/neptune/blob/master/doc/announcements.md)
  is a anex to the previous guideline on how to make release announcements.
* [Using Neptune-Versioned
  Libraries](https://github.com/sociomantic-tsunami/neptune/blob/master/doc/library-user.rst)
  is a guideline for users of Neptune based libraries, to help them know how and
  when to upgrade.
* [Maintaining Neptune-Versioned
  Applications](https://github.com/sociomantic-tsunami/neptune/blob/master/doc/application-maintainer.rst)
  is a guideline for application developers (and ultimately users too) to help
  them maintain applications using the Neptune versioning scheme.

Tools
=====

For now the repository only includes one
[tool](https://github.com/sociomantic-tsunami/neptune/tree/master/src/overview)
that fetches repositories for a selected GitHub organization and builds an HTML
overview of applications and libraries that shows which version of each library
is used in each application.
