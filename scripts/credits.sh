#!/usr/bin/env bash
# Checks that a version's CHANGELOG.md entries credit the people who did real
# work on them, and prints each credit that is missing. For every pull request
# an entry links, GitHub says who wrote it, which issues and earlier pull
# requests it links and who opened them, and who wrote its commits.
#
#   Who                                          Credit the entry needs
#   the pull request's author                    by @handle
#   the author of an issue it links              reported by @handle in #N
#   the author of an earlier pull request it is  based on #N by @handle
#     based on ("Based on #N", "Supersedes #N",
#     "Replaces #N", "Builds on #N")
#   anyone else who did real work in its         with @handle
#     commits: 10 or more changed lines in
#     non-merge commits (CREDITS_MIN_LINES), or
#     a Co-authored-by line on such a commit
#
# Nobody in .github/MAINTAINERS and no bot (a login ending in [bot] or -bot) is
# ever credited. An issue counts as linked when the pull request closes it
# ("Fixes #N") or names it with "Refs #N" or "Part of #N"; a plain mention
# doesn't. When the rules misjudge, an entry can say so in a comment GitHub
# doesn't show: <!-- credits: skip @handle -->.
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
min_lines=${CREDITS_MIN_LINES:-10}
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

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Maintainers and bots get no credit line.
uncredited() {
  local login
  login=$(lower "$1")
  [[ -z "$login" || "$login" == *"[bot]" || "$login" == *-bot || "$login" == app/* ]] && return 0
  grep -qxF -- "$login" <<<"$maintainers"
}

missing=0
expect() {
  local entry=$1 pr=$2 login=$3 credit=$4
  uncredited "$login" && return 0
  grep -qiF -- "credits: skip @$login" <<<"$entry" && return 0
  if ! grep -qiF -- "$credit" <<<"$entry"; then
    echo "#$pr: missing \"$credit\""
    missing=1
  fi
}

# Numbers that follow one of the words in $2 in the text $1.
linked() {
  grep -oiE "($2)[[:space:]]+#[0-9]+" <<<"$1" | grep -oE '[0-9]+$' || true
}

while IFS= read -r entry; do
  while read -r pr; do
    author=$(gh api "repos/$repo/pulls/$pr" --jq .user.login)
    expect "$entry" "$pr" "$author" "by @$author"
    body=$(gh api "repos/$repo/pulls/$pr" --jq '.body // ""')

    # Issues it fixes or refers to: credit whoever opened them.
    while read -r issue; do
      [[ -z "$issue" || "$issue" == "$pr" ]] && continue
      read -r reporter is_pr < <(gh api "repos/$repo/issues/$issue" --jq '[.user.login, (.pull_request != null)] | @tsv')
      [[ "$is_pr" == true || "$(lower "$reporter")" == "$(lower "$author")" ]] && continue
      expect "$entry" "$pr" "$reporter" "reported by @$reporter"
    done < <({
      # shellcheck disable=SC2016 # $owner and the rest are GraphQL variables
      gh api graphql -F owner="${repo%/*}" -F name="${repo#*/}" -F number="$pr" -f query='
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) { closingIssuesReferences(first: 50) { nodes { number } } }
          }
        }' --jq '.data.repository.pullRequest.closingIssuesReferences.nodes[].number'
      linked "$body" 'close[sd]?|fix(e[sd])?|resolve[sd]?|refs?|references|part of'
    } | sort -un)

    # Earlier pull requests it builds on: credit whoever wrote them.
    while read -r earlier; do
      [[ -z "$earlier" || "$earlier" == "$pr" ]] && continue
      read -r original is_pr < <(gh api "repos/$repo/issues/$earlier" --jq '[.user.login, (.pull_request != null)] | @tsv')
      [[ "$is_pr" != true || "$(lower "$original")" == "$(lower "$author")" ]] && continue
      expect "$entry" "$pr" "$original" "based on #$earlier by @$original"
    done < <(linked "$body" 'based on|supersedes|replaces|builds on' | sort -un)

    # Everyone else who did real work in its commits. Merge commits, which
    # only bring in another branch, don't count.
    contributions=$(
      while IFS=$'\t' read -r sha login parents; do
        [[ "$parents" -gt 1 ]] && continue
        commit=$(gh api "repos/$repo/commits/$sha" --jq '[.stats.total, .commit.message] | @tsv')
        printf '%s\t%s\n' "$login" "${commit%%$'\t'*}"
        # Named in a Co-authored-by line: the author chose to share the commit.
        grep -oiE 'co-authored-by:[^<]*<[0-9]+\+[^@>]+@users\.noreply\.github\.com>' <<<"${commit#*$'\t'}" |
          sed -E 's/.*<[0-9]+\+([^@>]+)@.*/\1/' |
          while read -r person; do printf '%s\t%s\n' "$person" "$min_lines"; done || true
      done < <(gh api --paginate "repos/$repo/pulls/$pr/commits" --jq '.[] | [.sha, (.author.login // ""), (.parents | length)] | @tsv')
    )
    while IFS=$'\t' read -r person total; do
      [[ -z "$person" || "$(lower "$person")" == "$(lower "$author")" ]] && continue
      [[ "$total" -lt "$min_lines" ]] && continue
      expect "$entry" "$pr" "$person" "with @$person"
    done < <(awk -F'\t' 'NF == 2 { total[$1] += $2 } END { for (p in total) print p "\t" total[p] }' <<<"$contributions")
  done < <(grep -oE "github\.com/$repo/pull/[0-9]+" <<<"$entry" | grep -oE '[0-9]+$' | sort -un)
done <<<"$entries"

if [[ $missing -ne 0 ]]; then
  echo "credits.sh: add the missing credits to the $version entries in CHANGELOG.md." >&2
  exit 1
fi
echo "Every $version entry credits the people who did the work."
