Description
===========

Overview tool is used to gather submodule dependency information from GitHub and
build various reports to get quick overview of project status.

Configuration
=============

To be able to run the overview tool you must first create a configuration file
in the working directory you intend to run the tool from:

```yml
oauthtoken: GITHUB-TOKEN

organization: orgname
exclude:
    - repo1
    - repo2
include:
    - otherorg1/repo
    - otherorg2/repo
```

Mandatory fields are `oauthtoken` and `organization`. Optional `exclude` list
allows to filter some of repos belonging to the organization in case those are
not relevant. Optional `include` list allows to add repositories from arbitrary
organizations to the overview.
