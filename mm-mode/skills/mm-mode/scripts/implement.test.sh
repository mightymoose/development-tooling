#!/usr/bin/env bash
# Tests for implement.sh. Each test runs in a throwaway repo.
set -euo pipefail

IMPLEMENT="$(cd "$(dirname "$0")" && pwd)/implement.sh"
failures=0

fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
start=0
pass() { [ "$failures" -eq "$start" ] && echo "ok: $*" || true; }

# A repo with one planned slice, s01-greet. Its test passes when greet.txt says hello.
new_run() {
  local repo run
  repo=$(mktemp -d)
  git -C "$repo" init --quiet
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  echo one > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit --quiet -m init
  run="$repo/.git/mm-mode/implement/t"
  mkdir -p "$run/slices"
  printf 'name\tphase\tstatus\tcommits\tnote\ns01-greet\tslice\tplanned\t-\t-\ns02-shout\tslice\tplanned\t-\t-\n' \
    > "$run/ledger.tsv"
  printf '# s01-greet\n\nKind: behavior\n' > "$run/slices/s01-greet.md"
  echo greet.txt > "$run/slices/s01-greet.files"
  echo 'grep -qx hello greet.txt' > "$run/slices/s01-greet.cmd"
  echo unit > "$run/checks.expected"
  printf 'echo "DONE unit 0"\n' > "$run/checks.sh"
  bash "$run/checks.sh" > "$run/baseline.txt"
  echo "$repo $run"
}

# Act as a slice worker that ran red, then green, and reported PASS.
work() {
  local run=$1 text=$2
  echo "FAIL greet.txt missing" > "$run/s01-greet.red.txt"
  echo "$text" > greet.txt
  git add greet.txt
  git commit --quiet -m "s01-greet"
  printf 'status: PASS\nsha: x\nartifacts: -\nfindings: 0\nblocker: -\n' > "$run/s01-greet.result"
}

status_of() { awk -F '\t' -v n="$2" '$1 == n { print $3 }' "$1/ledger.tsv"; }

assert_stopped() {
  local run=$1 name=$2 check=$3
  [ "$(status_of "$run" "$name")" = needs-human ] || fail "$name is not needs-human"
  "$IMPLEMENT" next "$run" > /dev/null && fail "next did not refuse"
  "$IMPLEMENT" begin "$run" s02-shout > /dev/null 2>&1 && fail "begin did not refuse"
  local h="$run/$name.handoff.md"
  [ -f "$h" ] || { fail "no handoff file"; return; }
  for s in Phase Attempted "Failed check" Expected Observed Reproduce Evidence "Checkout state" "Decision needed"; do
    grep -q "^## $s" "$h" || fail "handoff has no $s section"
  done
  grep -qx "$check" "$h" || fail "handoff does not name the $check check"
}

test_gate_accepts_a_good_slice() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  "$IMPLEMENT" begin "$run" s01-greet
  work "$run" hello
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null || fail "gate rejected a good slice"
  [ "$(status_of "$run" s01-greet)" = done ] || fail "slice not marked done"
  awk -F '\t' '$1 == "s01-greet" { print $4 }' "$run/ledger.tsv" | grep -q "$(git rev-parse HEAD)" \
    || fail "ledger lacks the commit"
  [ "$("$IMPLEMENT" next "$run")" = s02-shout ] || fail "next is not s02-shout"
  pass "gate accepts a good slice"
}

test_blocked_worker_hands_off() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  "$IMPLEMENT" begin "$run" s01-greet
  echo draft > greet.txt
  printf 'status: BLOCKED\nsha: x\nartifacts: -\nfindings: 0\nblocker: needs decision: which greeting?\n' \
    > "$run/s01-greet.result"
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null && fail "gate passed a blocked worker"
  assert_stopped "$run" s01-greet result
  grep -q "which greeting" "$run/s01-greet.handoff.md" || fail "handoff lost the blocker"
  [ "$(cat greet.txt)" = draft ] || fail "the failed attempt was not preserved"
  grep -q "greet.txt" "$run/s01-greet.handoff.md" || fail "handoff does not list uncommitted work"
  pass "blocked worker hands off"
}

test_failed_green_hands_off() {
  start=$failures
  local repo run head
  read -r repo run < <(new_run)
  cd "$repo"
  "$IMPLEMENT" begin "$run" s01-greet
  work "$run" goodbye
  head=$(git rev-parse HEAD)
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null && fail "gate passed a failing test"
  assert_stopped "$run" s01-greet green
  [ "$(git rev-parse HEAD)" = "$head" ] || fail "the failed commit was reverted"
  grep -q 'grep -qx hello greet.txt' "$run/s01-greet.handoff.md" || fail "handoff lacks the repro command"
  grep -q "$head" "$run/s01-greet.handoff.md" || fail "handoff lacks the commit"
  pass "failed green hands off"
}

test_unexpected_file_hands_off() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  "$IMPLEMENT" begin "$run" s01-greet
  echo changed > a.txt
  git add a.txt
  work "$run" hello
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null && fail "gate passed a file outside the brief"
  assert_stopped "$run" s01-greet scope
  grep -q "a.txt" "$run/s01-greet.handoff.md" || fail "handoff does not name the extra file"
  [ "$(cat a.txt)" = changed ] || fail "the failed attempt was not preserved"
  pass "unexpected file hands off"
}

test_new_check_failure_hands_off() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  printf 'echo "FAIL unit::adds"\necho "DONE unit 1"\n' > "$run/checks.sh"
  "$IMPLEMENT" begin "$run" s01-greet
  work "$run" hello
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null && fail "gate passed a new check failure"
  assert_stopped "$run" s01-greet checks
  grep -q "NEW unit::adds" "$run/s01-greet.handoff.md" || fail "handoff lacks the new failure"
  pass "new check failure hands off"
}

test_incomplete_qa_hands_off() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  printf 'status: BLOCKED\nsha: x\nartifacts: -\nfindings: 0\nblocker: no admin login\n' > "$run/qa.result"
  "$IMPLEMENT" accept "$run" qa > /dev/null && fail "accept passed an incomplete QA run"
  assert_stopped "$run" qa result
  grep -qx qa "$run/qa.handoff.md" || fail "handoff does not name the qa phase"
  grep -q "no admin login" "$run/qa.handoff.md" || fail "handoff lost the QA blocker"
  pass "incomplete QA hands off"
}

test_state_sees_human_changes() {
  start=$failures
  local repo run out
  read -r repo run < <(new_run)
  cd "$repo"
  "$IMPLEMENT" begin "$run" s01-greet
  work "$run" goodbye
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null || true
  out=$("$IMPLEMENT" state "$run" s01-greet)
  [[ $out == UNCHANGED* ]] || fail "state saw a change that did not happen"
  echo hello > greet.txt && git commit --quiet -am "human fix"
  out=$("$IMPLEMENT" state "$run" s01-greet)
  [[ $out == CHANGED* ]] || fail "state missed the human's commit"
  grep -q "human fix" <<< "$out" || fail "state does not list the new commit"
  pass "state sees human changes"
}

test_state_sees_edits_to_dirty_files() {
  start=$failures
  local repo run out
  read -r repo run < <(new_run)
  cd "$repo"
  "$IMPLEMENT" begin "$run" s01-greet
  echo draft > greet.txt
  printf 'status: BLOCKED\nblocker: needs decision: tone\n' > "$run/s01-greet.result"
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null || true
  [[ $("$IMPLEMENT" state "$run" s01-greet) == UNCHANGED* ]] || fail "state saw a change that did not happen"
  echo edited > greet.txt
  out=$("$IMPLEMENT" state "$run" s01-greet)
  [[ $out == CHANGED* ]] || fail "state missed an edit to an untracked file"
  grep -q greet.txt <<< "$out" || fail "state does not name the edited file"
  [ -z "$(git diff --cached --name-only)" ] || fail "state touched the real index"
  pass "state sees edits to dirty files"
}

test_retry_is_gated_on_its_own_files() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  "$IMPLEMENT" begin "$run" s01-greet
  work "$run" goodbye
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null || true
  "$IMPLEMENT" mark "$run" s01-greet planned
  [ "$(status_of "$run" s01-greet)" = planned ] || fail "mark did not set planned"
  "$IMPLEMENT" begin "$run" s01-greet || fail "begin refused after the human marked the row"
  [ -f "$run/s01-greet.attempt-1/s01-greet.handoff.md" ] || fail "the first handoff was not kept"
  [ ! -e "$run/s01-greet.result" ] || fail "the old result is still in place"
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null && fail "gate passed on old files"
  grep -q "status: missing" "$run/s01-greet.handoff.md" || fail "the retry was gated on the old result"
  pass "retry is gated on its own files"
}

# Run every slice to done, and record the feature list.
finish_slices() {
  local run=$1
  "$IMPLEMENT" begin "$run" s01-greet
  work "$run" hello
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null
  "$IMPLEMENT" mark "$run" s02-shout dropped
  printf 'status: PASS\n' > "$run/features.result"
  "$IMPLEMENT" accept "$run" features > /dev/null
}

test_blocked_qa_resumes_at_qa() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  finish_slices "$run"
  [ "$("$IMPLEMENT" phase "$run")" = qa ] || fail "phase is not qa"
  "$IMPLEMENT" begin "$run" qa
  printf 'status: BLOCKED\nblocker: port 3000 in use\n' > "$run/qa.result"
  "$IMPLEMENT" accept "$run" qa > /dev/null || true
  "$IMPLEMENT" phase "$run" > /dev/null && fail "phase did not refuse while QA needs a human"
  "$IMPLEMENT" mark "$run" qa planned
  [ "$("$IMPLEMENT" phase "$run")" = qa ] || fail "resume did not return to qa"
  [ -z "$("$IMPLEMENT" next "$run")" ] || fail "next offered a build for QA"
  "$IMPLEMENT" begin "$run" qa
  [ -f "$run/qa.attempt-1/qa.handoff.md" ] || fail "the QA handoff was not kept"
  [ ! -e "$run/qa.result" ] || fail "the old QA result is still in place"
  printf 'status: PASS\n' > "$run/qa.result"
  "$IMPLEMENT" accept "$run" qa > /dev/null || fail "QA rerun was not accepted"
  [ "$("$IMPLEMENT" phase "$run")" = final ] || fail "phase after QA is not final"
  pass "blocked QA resumes at QA"
}

test_failed_final_resumes_at_final() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  finish_slices "$run"
  "$IMPLEMENT" mark "$run" qa done
  printf 'echo "FAIL unit::adds"\necho "DONE unit 1"\n' > "$run/checks.sh"
  "$IMPLEMENT" final "$run" > /dev/null && fail "final passed a new failure"
  [ "$(status_of "$run" final)" = needs-human ] || fail "final is not needs-human"
  grep -qx final "$run/final.handoff.md" || fail "handoff does not name the final phase"
  printf 'echo "DONE unit 0"\n' > "$run/checks.sh"
  "$IMPLEMENT" mark "$run" final planned
  [ "$("$IMPLEMENT" phase "$run")" = final ] || fail "resume did not return to final"
  "$IMPLEMENT" final "$run" > /dev/null || fail "final did not pass after the fix"
  [ -f "$run/final.attempt-1/final.handoff.md" ] || fail "the final handoff was not kept"
  [ "$("$IMPLEMENT" phase "$run")" = complete ] || fail "run is not complete"
  pass "failed final resumes at final"
}

test_resolved_handoff_does_not_block_final() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  "$IMPLEMENT" begin "$run" s01-greet
  work "$run" goodbye
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null || true
  echo hello > greet.txt && git commit --quiet -am "human fix"
  "$IMPLEMENT" mark "$run" s01-greet done
  "$IMPLEMENT" mark "$run" s02-shout dropped
  "$IMPLEMENT" mark "$run" features done
  "$IMPLEMENT" mark "$run" qa done
  [ -f "$run/s01-greet.handoff.md" ] || fail "the resolved handoff is gone"
  [ "$("$IMPLEMENT" phase "$run")" = final ] || fail "phase is not final"
  "$IMPLEMENT" final "$run" > /dev/null || fail "final did not run"
  [ -f "$run/final.txt" ] || fail "final checks did not execute"
  pass "resolved handoff does not block final"
}

test_done_and_dropped_slices_start_qa() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  "$IMPLEMENT" begin "$run" s01-greet
  work "$run" hello
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null
  [ "$("$IMPLEMENT" phase "$run")" = "slice s02-shout" ] || fail "phase skipped a planned slice"
  "$IMPLEMENT" mark "$run" s02-shout dropped
  [ "$("$IMPLEMENT" phase "$run")" = features ] || fail "QA prep did not start"
  printf 'status: PASS\n' > "$run/features.result"
  "$IMPLEMENT" accept "$run" features > /dev/null
  [ "$("$IMPLEMENT" phase "$run")" = qa ] || fail "QA did not start"
  pass "done and dropped slices start QA"
}

test_one_open_handoff_blocks_work() {
  start=$failures
  local repo run
  read -r repo run < <(new_run)
  cd "$repo"
  printf 's03-wave\tslice\tplanned\t-\t-\n' >> "$run/ledger.tsv"
  printf '# s02-shout\n\nKind: behavior\n' > "$run/slices/s02-shout.md"
  echo shout.txt > "$run/slices/s02-shout.files"
  echo 'test -f shout.txt' > "$run/slices/s02-shout.cmd"
  "$IMPLEMENT" begin "$run" s01-greet
  work "$run" goodbye
  "$IMPLEMENT" gate "$run" s01-greet > /dev/null || true
  git reset --quiet --hard HEAD~1
  "$IMPLEMENT" mark "$run" s01-greet dropped
  "$IMPLEMENT" begin "$run" s02-shout
  printf 'status: BLOCKED\nblocker: needs decision: volume\n' > "$run/s02-shout.result"
  "$IMPLEMENT" gate "$run" s02-shout > /dev/null || true
  [ -f "$run/s01-greet.handoff.md" ] || fail "the resolved handoff is gone"
  "$IMPLEMENT" next "$run" > /dev/null && fail "next did not refuse"
  "$IMPLEMENT" begin "$run" s03-wave > /dev/null 2>&1 && fail "begin did not refuse"
  "$IMPLEMENT" final "$run" > /dev/null && fail "final did not refuse"
  [[ $("$IMPLEMENT" phase "$run") == "NEEDS_HUMAN s02-shout slice" ]] || fail "phase does not name the open handoff"
  pass "one open handoff blocks work"
}

test_gate_accepts_a_good_slice
test_blocked_worker_hands_off
test_failed_green_hands_off
test_unexpected_file_hands_off
test_new_check_failure_hands_off
test_incomplete_qa_hands_off
test_state_sees_human_changes
test_state_sees_edits_to_dirty_files
test_retry_is_gated_on_its_own_files
test_blocked_qa_resumes_at_qa
test_failed_final_resumes_at_final
test_resolved_handoff_does_not_block_final
test_done_and_dropped_slices_start_qa
test_one_open_handoff_blocks_work

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
