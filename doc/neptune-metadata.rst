===========================
Neptune Metadata Definition
===========================

This file specifies what fields are in the ``.neptune.yml`` file, what they mean
and by which tools they are used. The file itself is expected to be in a
repository's root directory.

.. contents::

library
-------

Type
  boolean
Meaning
  If set to true, the repository is marked as a library used by other repositories
Tools
  - neptune-overview
  - neptune-autopr
Default
  false
Example
  .. code:: yml

    library: true

d2ready
-------

Type
  String
Meaning
  Can have one of the following values:

  - ``false``: No D2 support whatsoever (default)
  - ``true``: synonym for ``convertable``
  - ``convertable``: repository can automatically be converted to D2
  - ``only``: only D2 is supported
Tools
  - neptune-overview
  - neptune-autopr
Default
  false
Example
  .. code:: yml

    d2ready: true

support-guarantees
------------------

Type
  Mapping
Meaning
  Sets the support window and period users can expect for this repository
Tools
  - neptune-overview
  - neptune-autopr
Example
  .. code:: yml

    support-guarantees:
      major-months: 6
      minor-versions: 2

major-months
~~~~~~~~~~~~

Type
  Integer
Meaning
  Amount of months a major version is supported, starting from the time the next
  major version is released
Default
  6

minor-versions
~~~~~~~~~~~~~~

Type
  Integer
Meaning
  Amount of minor versions that are supported, starting from the latest one
Default
  2
  
automatic-update-prs
--------------------

Type
    Mapping
Meaning
  Defines which types of auto-pull-requests the repository desires.
  Values can be specified for ``default`` and ``override``.
  Possible values are ``none``, ``patch``, ``minor``, ``major``
Tools
  - neptune-autopr
Default
  If the repository is a library (``library: true``)
  the default is ``patch``. Otherwise it will be ``minor``.

  The motivation for this is that libraries need to ensure that they remain
  compatible with older dependency versions. If a dependency is updated to a new
  minor release this is not breaking in itself, but it makes it possible to
  accidentally introduce changes dependent on new features, without this being
  caught by CI. This _would_ be breaking change, that would impact on any
  downstream project still using an earlier version of the dependency.
  Restricting library submodule updates to only patch releases should prevent
  this.
Example
  .. code:: yml

    automatic-update-prs:
        default: patch
        override:
            makd: major
            ocean: minor
            swarm: patch
            krill: major

