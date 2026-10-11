# Contributing

Set up a checkout with:

```sh
mise trust && mise install
git config core.hooksPath githooks
```

`mise.toml` pins every tool the gate runs, and CI installs from the same file. mise ignores a repository's `mise.toml` until you trust it. Git never installs a hook from a checkout, so the `commit-msg` and `pre-push` hooks run only after you set `core.hooksPath`.

Run `tools/check` before you push. It's the same gate CI runs, and `tools/check --fix` applies the formatting first.

A commit message follows [Conventional Commits](https://www.conventionalcommits.org), and commitlint checks it in the `commit-msg` hook and in CI. release-please reads the type on `main` to pick the next version and write the changelog, so a `feat` bumps the minor version and a `fix` the patch. It keeps a release pull request open. Merging it tags the release, and the release workflow attaches `AgentProse.zip` to it.

The [agent instructions](../AGENTS.md) cover the rest. The [commands' instructions](../tools/AGENTS.md) say how a command here behaves, and the [shell rule](../.claude/rules/shell.md) how the shell is written.
