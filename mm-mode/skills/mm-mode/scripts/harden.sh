#!/usr/bin/env bash
# Git helpers for the harden playbook. Run from inside the target repo.
#
#   harden.sh worktree-add <run> <name>          make a detached worktree at HEAD, print its path
#   harden.sh capture <run> <name>               save every worker edit as a patch, remove the worktree
#   harden.sh begin <run> <stage>                record HEAD before a stage applies commits
#   harden.sh rollback <run> <stage>             revert every commit made since begin
#   harden.sh new-failures <expected> <baseline> <current>
#                                                compare two checks.sh runs
#
# <expected> lists one check name per line.
# A checks.sh run prints one "FAIL <check>::<test id>" line per failure,
# and one "DONE <check> <exit code>" line after each check finishes.
# "FAIL <check>::*" means the check failed and could not name its tests.
# new-failures exits 0 clean, 1 new failure, 2 only unresolved, 3 incomplete run.
set -euo pipefail

die() { echo "harden.sh: $*" >&2; exit 64; }

require_clean() {
  if [ -n "$(git status --porcelain)" ]; then
    die "working tree is not clean"
  fi
}

# Print the failure IDs of one checks.sh run, one per line.
# Fail with INCOMPLETE lines if an expected check has no DONE record.
# A check that exited non-zero without naming a failure counts as <check>::*.
normalize() {
  local expected=$1 results=$2 check code incomplete=0
  while read -r check; do
    [ -n "$check" ] || continue
    code=$(awk -v c="$check" '$1 == "DONE" && $2 == c { print $3 }' "$results" | tail -n 1)
    if [ -z "$code" ]; then
      echo "INCOMPLETE $check"
      incomplete=1
      continue
    fi
    if grep -q "^FAIL $check::" "$results"; then
      grep "^FAIL $check::" "$results" | sed 's/^FAIL //'
    elif [ "$code" != 0 ]; then
      echo "$check::*"
    fi
  done < "$expected"
  return $incomplete
}

cmd=${1:-}
[ -n "$cmd" ] || die "missing command"
shift

case "$cmd" in
  worktree-add)
    [ $# -eq 2 ] || die "usage: worktree-add <run> <name>"
    run=$1 name=$2
    path="$run/wt/$name"
    mkdir -p "$run/wt"
    git rev-parse HEAD > "$run/wt/$name.base"
    git worktree add --quiet --detach "$path" HEAD
    echo "$path"
    ;;

  capture)
    [ $# -eq 2 ] || die "usage: capture <run> <name>"
    run=$1 name=$2
    path="$run/wt/$name"
    patch="$run/$name.producer.patch"
    [ -d "$path" ] || die "no worktree at $path"
    [ -f "$run/wt/$name.base" ] || die "no start record for $name"
    base=$(cat "$run/wt/$name.base")
    # Stage everything inside the disposable worktree, then diff against the
    # start SHA, so new, staged and committed edits are all kept.
    git -C "$path" add -A
    git -C "$path" diff --cached --binary "$base" > "$patch"
    git worktree remove --force "$path"
    if [ -s "$patch" ]; then
      echo "$patch"
    else
      rm -f "$patch"
    fi
    ;;

  begin)
    [ $# -eq 2 ] || die "usage: begin <run> <stage>"
    run=$1 stage=$2
    require_clean
    git rev-parse HEAD > "$run/$stage.pre"
    ;;

  rollback)
    [ $# -eq 2 ] || die "usage: rollback <run> <stage>"
    run=$1 stage=$2
    [ -f "$run/$stage.pre" ] || die "no begin record for $stage"
    require_clean
    pre=$(cat "$run/$stage.pre")
    git rev-list "$pre..HEAD" > "$run/$stage.commits"
    if [ -s "$run/$stage.commits" ]; then
      # rev-list prints newest first, which is the order to revert in.
      while read -r sha; do
        git revert --no-edit "$sha" > /dev/null
      done < "$run/$stage.commits"
    fi
    cat "$run/$stage.commits"
    ;;

  new-failures)
    [ $# -eq 3 ] || die "usage: new-failures <expected> <baseline> <current>"
    expected=$1 baseline=$2 current=$3
    for f in "$expected" "$baseline" "$current"; do
      if [ ! -r "$f" ]; then
        echo "INCOMPLETE cannot read $f"
        exit 3
      fi
    done
    if ! grep -q '[^[:space:]]' "$expected"; then
      echo "INCOMPLETE no expected checks in $expected"
      exit 3
    fi
    base_fails=$(normalize "$expected" "$baseline") || { echo "INCOMPLETE baseline"; echo "$base_fails"; exit 3; }
    cur_fails=$(normalize "$expected" "$current") || { echo "$cur_fails"; exit 3; }
    status=0
    while read -r id; do
      [ -n "$id" ] || continue
      if grep -qxF "$id" <<< "$base_fails"; then
        case "$id" in
          *::\*) echo "UNRESOLVED $id"; [ $status -eq 1 ] || status=2 ;;
        esac
      else
        echo "NEW $id"
        status=1
      fi
    done <<< "$cur_fails"
    exit $status
    ;;

  *)
    die "unknown command: $cmd"
    ;;
esac
