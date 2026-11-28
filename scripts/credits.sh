#!/usr/bin/env bash
# Checks that a version's CHANGELOG.md entries credit the people behind them, and
# prints each credit that is missing. For every pull request an entry links,
# GitHub says who wrote it, which issues it links and who opened them, and who
# co-wrote its commits. An entry is expected to say, unless the person is a
# maintainer in .github/MAINTAINERS or a bot (a login ending in [bot] or -bot):
#
#   the pull request's author       by @handle
#   the author of an issue it links reported by @handle in #N
#   a co-author of its commits      with @handle
#
# An issue counts as linked when the pull request closes it ("Fixes #N") or
# names it with "Refs #N" or "Part of #N"; other mentions don't. Credit for
# earlier work a change built on ("based on #N by @handle") is written by hand.
#
#   ./scripts/credits.sh <version> [changelog]
#
# Exits 1 when a credit is missing. The release workflow runs it before it
# publishes anything. It needs gh, signed in or given GH_TOKEN.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo 'Usage: credits.sh <version> [changelog]' >&2
  exit 2
fi
version=$1
changelog=${2:-$root/CHANGELOG.md}
repo=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
maintainers=$(grep -v '^#' "$root/.github/MAINTAINERS" | tr -d '[:space:]@' | tr '[:upper:]' '[:lower:]' | grep -v '^$' || true)

# The version's entries, each joined onto one line.
entries=$(awk -v heading="## [$version]" '
  index($0, heading) == 1 { take = 1; next }
  take && (/^## \[/ || /^\[[^]]+\]: /) { exit }
  !take { next }
  /^- / { if (entry != "") print entry; entry = $0; next }
  /^[[:space:]]+[^[:space:]]/ && entry != "" { sub(/^[[:space:]]+/, ""); entry = entry " " $0; next }
  { if (entry != "") print entry; entry = "" }
  END { if (entry != "") print entry }' "$changelog")
if [[ -z "$entries" ]]; then
  echo "credits.sh: CHANGELOG.md has no entries for $version" >&2
  exit 1
fi

# Maintainers and bots get no credit line.
uncredited() {
  local login
  login=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  [[ -z "$login" || "$login" == *"[bot]" || "$login" == *-bot || "$login" == app/* ]] && return 0
  grep -qxF -- "$login" <<<"$maintainers"
}

missing=0
expect() {
  local entry=$1 pr=$2 credit=$3
  if ! grep -qiF -- "$credit" <<<"$entry"; then
    echo "#$pr: missing \"$credit\""
    missing=1
  fi
}

while IFS= read -r entry; do
  while read -r pr; do
    author=$(gh pr view "$pr" --repo "$repo" --json author --jq .author.login)
    if ! uncredited "$author"; then expect "$entry" "$pr" "by @$author"; fi

    body=$(gh pr view "$pr" --repo "$repo" --json body --jq .body)
    issues=$({
      gh pr view "$pr" --repo "$repo" --json closingIssuesReferences --jq '.closingIssuesReferences[].number'
      grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?|refs?|references|part of)[[:space:]]+#[0-9]+' <<<"$body" |
        grep -oE '[0-9]+$' || true
    } | sort -un)
    for issue in $issues; do
      [[ "$issue" == "$pr" ]] && continue
      read -r reporter is_pr < <(gh api "repos/$repo/issues/$issue" --jq '[.user.login, (.pull_request != null)] | @tsv')
      [[ "$is_pr" == true || "$reporter" == "$author" ]] && continue
      if ! uncredited "$reporter"; then expect "$entry" "$pr" "reported by @$reporter"; fi
    done

    while read -r coauthor; do
      [[ -z "$coauthor" || "$coauthor" == "$author" ]] && continue
      if ! uncredited "$coauthor"; then expect "$entry" "$pr" "with @$coauthor"; fi
    done < <(gh pr view "$pr" --repo "$repo" --json commits --jq '[.commits[].authors[].login] | unique | .[]')
  done < <(grep -oE "github\.com/$repo/pull/[0-9]+" <<<"$entry" | grep -oE '[0-9]+$' | sort -un)
done <<<"$entries"

if [[ $missing -ne 0 ]]; then
  echo "credits.sh: add the missing credits to the $version entries in CHANGELOG.md." >&2
  exit 1
fi
echo "Every $version entry credits its authors and reporters."
