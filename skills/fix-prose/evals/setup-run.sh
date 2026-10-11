#!/usr/bin/env bash
# Make a fresh git repository for one run of one test case.
#   setup-run.sh <fixture-dir> <repo-dir>
# The repository has to sit outside any Vale configuration, because Vale
# searches parent folders and a found one stops the default from applying.
# The unsynced-package fixture gets a Vale configuration naming the package,
# and an empty styles folder, so Vale loads it and names no styles.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fixture="$1"
repo="$2"
mkdir -p "${repo%/*}"
cp -R "${fixture}" "${repo}"
if [[ "${fixture##*/}" == unsynced-package ]]; then
  printf 'StylesPath = styles\nPackages = %s/package\n' "${repo_root}" >"${repo}/.vale.ini"
  mkdir -p "${repo}/styles"
  touch "${repo}/styles/.keep"
fi
git -C "${repo}" init -q
git -C "${repo}" add -A
git -C "${repo}" -c user.name=eval -c user.email=eval@example.com commit -qm base
