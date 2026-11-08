#!/usr/bin/env bash
# Prepares a Nikaos release: tools/release.sh 2.5.1
#  1. CHANGELOG.md must already have a "## 2.5.1 — <date>" section with the
#     notes, written for users;
#  2. this script writes version.txt, commits, and tags v2.5.1;
#  3. then push: git push origin master --tags
#     GitHub creates the release from the tag (.github/workflows/release.yml)
#     and Nikaos' update button offers it to everyone.
set -euo pipefail
cd "$(dirname "$(realpath "$0")")/.."

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: tools/release.sh X.Y.Z" >&2; exit 2; }
git rev-parse -q --verify "refs/tags/v$version" >/dev/null && { echo "v$version already exists" >&2; exit 1; }
grep -qE "^## $version([^0-9.]|\$)" CHANGELOG.md || { echo "Add a '## $version — date' section to CHANGELOG.md first" >&2; exit 1; }
[ -z "$(git status --porcelain -- . ':!CHANGELOG.md' ':!version.txt')" ] || { echo "Commit your other changes first" >&2; exit 1; }

echo "$version" > version.txt
git add version.txt CHANGELOG.md
git commit -m "Nikaos $version"
git tag -a "v$version" -m "Nikaos $version"
echo "Ready. Publish with: git push origin master --tags"
