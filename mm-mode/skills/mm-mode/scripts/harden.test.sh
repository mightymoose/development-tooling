#!/usr/bin/env bash
# Tests for harden.sh. Each test runs in a throwaway repo.
set -euo pipefail

HARDEN="$(cd "$(dirname "$0")" && pwd)/harden.sh"
failures=0

fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
start=0
pass() { [ "$failures" -eq "$start" ] && echo "ok: $*" || true; }

new_repo() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init --quiet
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  echo one > "$dir/a.txt"
  git -C "$dir" add a.txt
  git -C "$dir" commit --quiet -m init
  echo "$dir"
}

test_capture_keeps_new_and_staged_files() {
  start=$failures
  local repo run wt patch
  repo=$(new_repo)
  run="$repo/.git/mm-mode/harden/t"
  mkdir -p "$run"
  cd "$repo"
  wt=$("$HARDEN" worktree-add "$run" p1-simplify-produce)
  echo two > "$wt/a.txt"
  git -C "$wt" add a.txt
  echo three >> "$wt/a.txt"
  echo new > "$wt/new.txt"
  patch=$("$HARDEN" capture "$run" p1-simplify-produce)
  [ -f "$patch" ] || { fail "capture wrote no patch"; return; }
  grep -q '^+three' "$patch" || fail "patch lost an unstaged edit"
  grep -q '^+two' "$patch" || fail "patch lost a staged edit"
  grep -q 'new.txt' "$patch" || fail "patch lost an untracked file"
  [ -z "$(git status --porcelain)" ] || fail "main checkout changed"
  [ ! -d "$wt" ] || fail "worktree not removed"
  git apply --check "$patch" || fail "patch does not apply to HEAD"
  pass "capture keeps new and staged files"
}

test_capture_without_edits_writes_nothing() {
  start=$failures
  local repo run out
  repo=$(new_repo)
  run="$repo/.git/mm-mode/harden/t"
  mkdir -p "$run"
  cd "$repo"
  "$HARDEN" worktree-add "$run" p1-qa-produce > /dev/null
  out=$("$HARDEN" capture "$run" p1-qa-produce)
  [ -z "$out" ] || fail "capture printed a patch for no edits"
  [ ! -f "$run/p1-qa-produce.producer.patch" ] || fail "empty patch left behind"
  pass "capture without edits writes nothing"
}

test_rollback_reverts_stage_and_repair_commits() {
  start=$failures
  local repo run
  repo=$(new_repo)
  run="$repo/.git/mm-mode/harden/t"
  mkdir -p "$run"
  cd "$repo"
  "$HARDEN" begin "$run" p1-simplify
  echo stage > a.txt && git commit --quiet -am "stage commit"
  echo repair > a.txt && echo extra > b.txt && git add b.txt && git commit --quiet -am "repair commit"
  "$HARDEN" rollback "$run" p1-simplify > /dev/null
  [ "$(cat a.txt)" = one ] || fail "a.txt not restored"
  [ ! -e b.txt ] || fail "repair commit file still present"
  [ "$(wc -l < "$run/p1-simplify.commits" | tr -d ' ')" = 2 ] || fail "commit list does not hold both commits"
  pass "rollback reverts stage and repair commits"
}

test_begin_refuses_dirty_tree() {
  start=$failures
  local repo run
  repo=$(new_repo)
  run="$repo/.git/mm-mode/harden/t"
  mkdir -p "$run"
  cd "$repo"
  echo dirty > a.txt
  if "$HARDEN" begin "$run" p1-simplify 2> /dev/null; then
    fail "begin accepted a dirty tree"
  else
    pass "begin refuses a dirty tree"
  fi
}

test_new_failures() {
  start=$failures
  local dir out status
  dir=$(mktemp -d)
  printf 'unit\nlint\ntypes\n' > "$dir/expected"
  printf 'FAIL unit::checkout totals\nDONE unit 1\nFAIL lint::*\nDONE lint 1\nDONE types 0\n' > "$dir/base"

  printf 'FAIL unit::checkout totals\nFAIL unit::refund rounding\nDONE unit 1\nFAIL lint::*\nDONE lint 1\nDONE types 0\n' > "$dir/cur"
  set +e; out=$("$HARDEN" new-failures "$dir/expected" "$dir/base" "$dir/cur"); status=$?; set -e
  [ $status -eq 1 ] || fail "new test failure not reported (status $status)"
  grep -qxF 'NEW unit::refund rounding' <<< "$out" || fail "new failure id missing"

  printf 'FAIL unit::checkout totals\nDONE unit 1\nFAIL lint::*\nDONE lint 1\nDONE types 0\n' > "$dir/cur"
  set +e; out=$("$HARDEN" new-failures "$dir/expected" "$dir/base" "$dir/cur"); status=$?; set -e
  [ $status -eq 2 ] || fail "still-failing opaque check not unresolved (status $status)"
  grep -qxF 'UNRESOLVED lint::*' <<< "$out" || fail "unresolved line missing"

  printf 'DONE unit 0\nDONE lint 0\nFAIL types::*\nDONE types 1\n' > "$dir/cur"
  set +e; "$HARDEN" new-failures "$dir/expected" "$dir/base" "$dir/cur" > /dev/null; status=$?; set -e
  [ $status -eq 1 ] || fail "newly failing opaque check not new (status $status)"

  printf 'DONE unit 0\nDONE lint 0\nDONE types 0\n' > "$dir/cur"
  set +e; "$HARDEN" new-failures "$dir/expected" "$dir/base" "$dir/cur" > /dev/null; status=$?; set -e
  [ $status -eq 0 ] || fail "clean run not clean (status $status)"
  pass "new-failures compares by test id"
}

test_capture_keeps_committed_edits() {
  start=$failures
  local repo run wt patch
  repo=$(new_repo)
  run="$repo/.git/mm-mode/harden/t"
  mkdir -p "$run"
  cd "$repo"
  wt=$("$HARDEN" worktree-add "$run" p1-review)
  echo committed > "$wt/a.txt"
  git -C "$wt" commit --quiet -am "worker commit"
  patch=$("$HARDEN" capture "$run" p1-review)
  [ -n "$patch" ] && [ -f "$patch" ] || { fail "committed edit not captured"; return; }
  grep -q '^+committed' "$patch" || fail "patch lost a committed edit"
  pass "capture keeps committed edits"
}

test_new_failures_requires_complete_runs() {
  start=$failures
  local dir status
  dir=$(mktemp -d)
  printf 'unit\nlint\n' > "$dir/expected"
  printf 'DONE unit 0\nDONE lint 0\n' > "$dir/base"

  set +e; "$HARDEN" new-failures "$dir/expected" "$dir/base" "$dir/missing" > /dev/null 2>&1; status=$?; set -e
  [ $status -eq 3 ] || fail "missing results file not incomplete (status $status)"

  echo 'runner: command not found' > "$dir/cur"
  set +e; "$HARDEN" new-failures "$dir/expected" "$dir/base" "$dir/cur" > /dev/null; status=$?; set -e
  [ $status -eq 3 ] || fail "results with no completion records not incomplete (status $status)"

: > "$dir/empty"
  set +e; "$HARDEN" new-failures "$dir/empty" "$dir/base" "$dir/base" > /dev/null; status=$?; set -e
  [ $status -eq 3 ] || fail "empty expected list not incomplete (status $status)"

  printf 'DONE unit 0\n' > "$dir/cur"
  set +e; "$HARDEN" new-failures "$dir/expected" "$dir/base" "$dir/cur" > /dev/null; status=$?; set -e
  [ $status -eq 3 ] || fail "missing check record not incomplete (status $status)"

  printf 'DONE unit 0\nDONE lint 1\n' > "$dir/cur"
  set +e; out=$("$HARDEN" new-failures "$dir/expected" "$dir/base" "$dir/cur"); status=$?; set -e
  [ $status -eq 1 ] || fail "non-zero exit with no FAIL lines not a failure (status $status)"
  grep -qxF 'NEW lint::*' <<< "$out" || fail "non-zero exit not reported as lint::*"
  pass "new-failures requires complete runs"
}

test_recover_stashes_edits_then_rolls_back() {
  start=$failures
  local repo run out
  repo=$(new_repo)
  run="$repo/.git/mm-mode/harden/t"
  mkdir -p "$run"
  cd "$repo"
  "$HARDEN" begin "$run" p1-qa
  echo stage > a.txt && git commit --quiet -am "stage commit"
  echo unfinished > a.txt
  echo new > untracked.txt
  if ! out=$("$HARDEN" recover "$run" p1-qa 2>&1); then
    fail "recover failed: $out"; return
  fi
  [ "$(cat a.txt)" = one ] || fail "stage commit not reverted"
  [ ! -e untracked.txt ] || fail "untracked edit left in the tree"
  [ -z "$(git status --porcelain)" ] || fail "tree not clean after recover"
  git stash list | grep -q 'harden-p1-qa' || fail "no named stash"
  grep -q '^stash: stash@' <<< "$out" || fail "stash not reported"
  grep -q '^reverted: ' <<< "$out" || fail "reverted commits not reported"
  git stash show --include-untracked --name-only stash@{0} | grep -qx untracked.txt || fail "stash lost the untracked file"
  pass "recover stashes edits then rolls back"
}

test_recover_with_clean_tree_makes_no_stash() {
  start=$failures
  local repo run out
  repo=$(new_repo)
  run="$repo/.git/mm-mode/harden/t"
  mkdir -p "$run"
  cd "$repo"
  "$HARDEN" begin "$run" p1-qa
  echo stage > a.txt && git commit --quiet -am "stage commit"
  out=$("$HARDEN" recover "$run" p1-qa)
  [ -z "$(git stash list)" ] || fail "stash made for a clean tree"
  grep -qx 'stash: none' <<< "$out" || fail "missing 'stash: none'"
  [ "$(cat a.txt)" = one ] || fail "stage commit not reverted"
  pass "recover with a clean tree makes no stash"
}

test_coverage_gaps_uses_git_file_list() {
  start=$failures
  local repo run base out status
  repo=$(new_repo)
  run="$repo/.git/mm-mode/harden/t"
  mkdir -p "$run"
  cd "$repo"
  base=$(git rev-parse HEAD)
  echo limit > rules.txt && echo page > page.txt && echo note > README.md
  git add . && git commit --quiet -m change
  printf 'page.txt -> checkout page shows the limit\nREADME.md -> none: docs only\n' > "$run/cov"
  set +e; out=$("$HARDEN" coverage-gaps "$base" "$run/cov"); status=$?; set -e
  [ $status -eq 1 ] || fail "omitted file not reported (status $status)"
  grep -qxF 'MISSING rules.txt' <<< "$out" || fail "missing file not named"

  printf 'page.txt -> checkout page shows the limit\nREADME.md -> none: docs only\nrules.txt ->\n' > "$run/cov"
  set +e; out=$("$HARDEN" coverage-gaps "$base" "$run/cov"); status=$?; set -e
  [ $status -eq 1 ] || fail "empty mapping accepted (status $status)"

  printf 'page.txt -> checkout page shows the limit\nREADME.md -> none: docs only\nrules.txt -> payment over the limit is refused\n' > "$run/cov"
  set +e; "$HARDEN" coverage-gaps "$base" "$run/cov" > /dev/null; status=$?; set -e
  [ $status -eq 0 ] || fail "complete coverage not accepted (status $status)"

  set +e; "$HARDEN" coverage-gaps "$base" "$run/nope" > /dev/null 2>&1; status=$?; set -e
  [ $status -ne 0 ] && [ $status -ne 1 ] || fail "missing coverage file not an error (status $status)"
  pass "coverage-gaps uses the git file list"
}

test_coverage_gaps_uses_git_file_list
test_recover_stashes_edits_then_rolls_back
test_recover_with_clean_tree_makes_no_stash
test_capture_keeps_new_and_staged_files
test_capture_keeps_committed_edits
test_new_failures_requires_complete_runs
test_capture_without_edits_writes_nothing
test_rollback_reverts_stage_and_repair_commits
test_begin_refuses_dirty_tree
test_new_failures

if [ $failures -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
