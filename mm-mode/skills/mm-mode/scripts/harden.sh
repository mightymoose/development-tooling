#!/usr/bin/env bash
# Git helpers for the harden playbook. Run from inside the target repo.
#
#   harden.sh worktree-add <run> <name>          make a detached worktree at HEAD, print its path
#   harden.sh capture <run> <name>               save every worker edit as a patch, remove the worktree
#   harden.sh begin <run> <stage>                record HEAD before a stage applies commits
#   harden.sh rollback <run> <stage>             revert every commit made since begin
#   harden.sh new-failures <baseline> <current>  compare failure lists from checks.sh
#
# Failure lists hold one "FAIL <check>::<test id>" line per failure.
# "FAIL <check>::*" means the check failed and could not name its tests.
set -euo pipefail

die() { echo "harden.sh: $*" >&2; exit 64; }

require_clean() {
  if [ -n "$(git status --porcelain)" ]; then
    die "working tree is not clean"
  fi
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
    git worktree add --quiet --detach "$path" HEAD
    echo "$path"
    ;;

  capture)
    [ $# -eq 2 ] || die "usage: capture <run> <name>"
    run=$1 name=$2
    path="$run/wt/$name"
    patch="$run/$name.producer.patch"
    [ -d "$path" ] || die "no worktree at $path"
    # Stage everything inside the disposable worktree, so new and staged files are kept.
    git -C "$path" add -A
    git -C "$path" diff --cached --binary HEAD > "$patch"
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
    [ $# -eq 2 ] || die "usage: new-failures <baseline> <current>"
    baseline=$1 current=$2
    status=0
    while read -r _ id; do
      [ -n "${id:-}" ] || continue
      if grep -qxF "FAIL $id" "$baseline"; then
        case "$id" in
          *::\*) echo "UNRESOLVED $id"; [ $status -eq 1 ] || status=2 ;;
        esac
      else
        echo "NEW $id"
        status=1
      fi
    done < <(grep '^FAIL ' "$current" || true)
    exit $status
    ;;

  *)
    die "unknown command: $cmd"
    ;;
esac
