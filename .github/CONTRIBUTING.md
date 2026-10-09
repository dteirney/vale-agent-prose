# Contributing

Set up a checkout with:

```sh
mise trust && mise install
git config core.hooksPath githooks
```

`mise.toml` pins every tool the gate runs. Git never installs a hook from a checkout, so the `commit-msg` and `pre-push` hooks run only after you set `core.hooksPath`.

Run `tools/check` before you push. It's the same gate CI runs, and `tools/check --fix` applies the formatting first.

A commit message follows [Conventional Commits](https://www.conventionalcommits.org). release-please reads the type to pick the next version, so a `feat` bumps the minor version and a `fix` the patch.

[AGENTS.md](../AGENTS.md) covers the rest: how a command here behaves, how the shell is written, and what belongs in a comment.
