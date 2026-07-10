GitHub Issue Transfer
=====================

This script transfers GitHub labels, issues, Pull Requests (PRs), and their
comments from one repository to another. It preserves the sequential numbering
of issues and PRs by creating dummy issues in the target repository for any
PRs found in the source repository.

Use this when you don't have ownership of one of the two repositories, and
therefore can't do a proper [repository transfer][1].

Usage
-----

You must provide the `SOURCE_REPO` and `TARGET_REPO` environment variables in
the format `user-or-org/repo-name`.

For example:

```bash
SOURCE_REPO=source/repo TARGET_REPO=target/repo make transfer
```

To simulate the transfer without making any changes to the target repository,
set the `DRY_RUN` environment variable to any non-empty value:

```
DRY_RUN=1 SOURCE_REPO="..." TARGET_REPO="..." make transfer
```

Credits
-------

Assisted-by:  gemini/gemini-3.1-pro-preview<br>
License:      [Zero-clause BSD][0bsd]


[1]: https://docs.github.com/en/repositories/creating-and-managing-repositories/transferring-a-repository
[0bsd]: https://opensource.org/license/0bsd
