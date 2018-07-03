# Neptune Library Release Announcements

Neptune-versioned libraries can have a lot of releases. Multiple minor releases
(one per maintained major branch) may come once a month. Patch releases, merged
into several minor branches, may come once a week or even more frequently. In
order to help users understand what this stream of releases means and what
action they should take, this document provides guidelines for what information
to include in release announcement emails.

# Email Format

## Subject

1. One of:

  * [PatchRelease]
  * [MinorRelease]
  * [MajorRelease]

2. The name of the repo.
3. The tags of the releases.

## Content

### Patch Releases

1. The following introductory paragraph which explains what users can expect from a
patch release and what they should do (where `<LIB>` is the name of your library
and `<BRANCH>` the name of the minor release branch(es) the patch is applied to):

  >If your application is using a previous `<LIB>` `<BRANCH>` release, it should be
  updated to use this new patch release as soon as possible. As this is a *patch
  release*, it contains only bugfixes; it is guaranteed not to contain new
  features or API changes and will not require you to change your code.

  >Issues fixed in this release:

2. The collated release notes of the release:

   - Detailed release notes for issues that have detailed description
   - A bullet list of issues fixed with links to the corresponding PRs or issues
     in github.

3. A link to the github release for the new patch release.

### Minor Releases

1. The following introductory paragraph which explains what users can expect from a
minor release and what they should do (where `<LIB>` is the name of your library
and `<BRANCH>` the name of the major branch(es) the minor release is based on):

  >If your application is using a previous `<LIB>` `<BRANCH>` release, it is
  recommended to update it to use this new minor release. As this is a *minor
  release*, it may contain new features, deprecations, or minor internal
  refactorings; it is guaranteed to not contain API changes and will not require
  you to change your code.

  >Release notes:

2. The collated release notes of the release.
3. A link to the github release for the new minor release.

### Major Releases

1. The following introductory paragraph which explains what users can expect from a
major release and what they should do (where `<LIB>` is the name of your library
and `<BRANCH>` the name of the previous maintained major branch(es)):

  >If your application is using a `<LIB>` `<BRANCH>` release, it is recommended to plan
  to update to this new major release in the next 2-3 months. As this is a
  *major release*, it may contain API changes, removal of deprecated code, and
  other semantic changes; it is possible that you will need to change your code.

  >Release notes:

2. The collated release notes of the release.
3. A link to the github release for the new major release.

# Examples

This section gives full examples of library release announcements, following the
scheme described above. Note that the links are imaginary (they don't link to
anything).

## Patch Release

>**[PatchRelease] triton v1.33.5, v1.34.5, v2.2.6, v2.3.6**

>If your application is using a previous triton v1.33.x, v1.34.x, v2.2.x, or
v2.3.x release, it should be updated to use this new patch release as soon as
possible. As this is a *patch release*, it will contain only bugfixes; it is
guaranteed not to contain new features or API changes and will not require you
to change your code.

>Issues fixed in this release:

>* Fix memory leak [#1234](https://github.com/sociomantic-tsunami/triton/issues/1234)
* Fix broken test [#4321](https://github.com/sociomantic-tsunami/triton/issues/4321)

>https://github.com/sociomantic-tsunami/triton/releases/tag/v1.33.5

>https://github.com/sociomantic-tsunami/triton/releases/tag/v1.34.5

>https://github.com/sociomantic-tsunami/triton/releases/tag/v2.2.6

>https://github.com/sociomantic-tsunami/triton/releases/tag/v2.3.6

## Minor Release

>**[MinorRelease] nereid v1.25.0, v2.2.0**

>If your application is using a previous nereid v1.x.x or v2.x.x release, it is
recommended to update it to use this new minor release. As this is a *minor
release*, it may contain new features, deprecations, or minor internal
refactorings; it is guaranteed to not contain API changes and will not require
you to change your code.

>Release notes:

> (Full release notes not included in this example, for brevity.)

>https://github.com/sociomantic-tsunami/nereid/releases/tag/v1.25.0

>https://github.com/sociomantic-tsunami/nereid/releases/tag/v2.2.0

## Major Release

>**[MajorRelease] proteus v2.0.0**

>If your application is using a proteus v1.x.x release, it is recommended to
plan to update to this new major release in the next 2-3 months. As this is a
*major release*, it may contain API changes, removal of deprecated code, and
other semantic changes; it is possible that you will need to change your code.

>Release notes:

> (Full release notes not included in this example, for brevity.)

>https://github.com/sociomantic-tsunami/proteus/releases/tag/v2.0.0

