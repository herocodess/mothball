# Security

Mothball moves folders on people's computers, so a bug that could put away the wrong thing is treated as a security issue.

Please report it privately through [GitHub's private vulnerability reporting](https://github.com/herocodess/mothball/security/advisories/new) rather than a public issue. You will get a reply within a few days.

When a release fixes such a bug, it ships an `update.json` that makes older versions stop moving files until they update (see [docs/release.md](docs/release.md)).
