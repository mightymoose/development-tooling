#!/usr/bin/env bash
# Slice gate and human handoff for the implement playbook. Run from inside the target repo.
#
#   implement.sh begin <run> <slice>       refuse if a slice needs a human, else archive the
#                                          last attempt's files and record HEAD
#   implement.sh gate <run> <slice>        accept a slice, or write its handoff
#   implement.sh qa <run> <name>           accept a QA result, or write its handoff
#   implement.sh handoff <run> <name> <check> <expected> <observed> <repro> [evidence...]
#                                          write a handoff and mark <name> needs-human
#   implement.sh next <run>                print the next planned slice
#   implement.sh state <run> <name>        compare the checkout with the handoff record
#   implement.sh mark <run> <name> <status>  set a ledger row's status on the human's direction
#
# The ledger <run>/slices.tsv has the header "slice status commits note".
# A status is planned, done, dropped or needs-human.
# For each slice the planner writes <run>/slices/<slice>.md (the brief),
# <slice>.files (the allowed paths, one per line) and <slice>.cmd (the test command).
# A worker writes <run>/<name>.result with a "status: <STATUS>" line.
# gate and qa exit 0 on pass and 1 after they write a handoff.
# next exits 1 while any row is needs-human.
set -euo pipefail

HARDEN="$(cd "$(dirname "$0")" && pwd)/harden.sh"

die() { echo "implement.sh: $*" >&2; exit 64; }

# Set one ledger row by name, or append it.
set_row() {
  local ledger=$1 name=$2 status=$3 commits=$4 note=$5 tmp
  tmp=$(mktemp)
  awk -F '\t' -v OFS='\t' -v n="$name" -v s="$status" -v c="$commits" -v o="$note" '
    NR > 1 && $1 == n { print n, s, c, o; found = 1; next }
    { print }
    END { if (!found) print n, s, c, o }
  ' "$ledger" > "$tmp"
  mv "$tmp" "$ledger"
}

field() { awk -v k="$1:" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }' "$2"; }

# Hash the working tree, untracked files included, without touching the real index.
fingerprint() {
  local idx tree
  idx=$(mktemp)
  cp "$(git rev-parse --git-path index)" "$idx" 2> /dev/null || rm -f "$idx"
  GIT_INDEX_FILE=$idx git add -A
  tree=$(GIT_INDEX_FILE=$idx git write-tree)
  rm -f "$idx"
  echo "$tree"
}

needs_human() { awk -F '\t' 'NR > 1 && $2 == "needs-human" { print $1; exit }' "$1/slices.tsv"; }

decision_for() {
  case "$1" in
    result) echo "Answer the worker's blocker, or change the brief." ;;
    red) echo "Fix the red test in the brief, or confirm that the behavior already exists." ;;
    clean) echo "Commit, keep or discard the uncommitted changes." ;;
    commits) echo "Keep, squash or discard the commits." ;;
    scope) echo "Add the extra files to the brief, or remove those changes." ;;
    green) echo "Fix the code or the test in the brief." ;;
    checks) echo "Fix the new failures, or accept them." ;;
    qa) echo "Fix the QA environment, or accept the coverage gap." ;;
    *) echo "Decide how to continue." ;;
  esac
}

handoff() {
  local run=$1 name=$2 check=$3 expected=$4 observed=$5 repro=$6
  shift 6
  local out="$run/$name.handoff.md" pre=none commits=none attempted
  if [ -f "$run/$name.pre" ]; then
    pre=$(cat "$run/$name.pre")
    commits=$(git rev-list --reverse "$pre..HEAD" | paste -sd, -)
    commits=${commits:-none}
  fi
  attempted="no result file"
  if [ -f "$run/$name.result" ]; then
    attempted=$(cat "$run/$name.result")
  fi
  {
    echo "# Handoff: $name"
    echo
    echo "## Attempted"
    echo "$attempted"
    echo
    echo "## Failed check"
    echo "$check"
    echo
    echo "## Expected"
    echo "$expected"
    echo
    echo "## Observed"
    echo "$observed"
    echo
    echo "## Reproduce"
    echo "$repro"
    echo
    echo "## Evidence"
    for e in "$@"; do echo "- $e"; done
    echo
    echo "## Checkout state"
    echo "pre: $pre"
    echo "head: $(git rev-parse HEAD)"
    echo "worktree: $(fingerprint)"
    echo "commits: $commits"
    echo "uncommitted:"
    git status --porcelain
    echo
    echo "## Decision needed"
    decision_for "$check"
  } > "$out"
  set_row "$run/slices.tsv" "$name" needs-human "$commits" "$check: $out"
  echo "NEEDS_HUMAN $name $check $out"
}

cmd=${1:-}
[ -n "$cmd" ] || die "missing command"
shift

case "$cmd" in
  begin)
    [ $# -eq 2 ] || die "usage: begin <run> <slice>"
    run=$1 slice=$2
    held=$(needs_human "$run")
    if [ -n "$held" ]; then
      echo "NEEDS_HUMAN $held"
      exit 1
    fi
    [ -z "$(git status --porcelain)" ] || die "working tree is not clean"
    # Keep the last attempt's evidence, so this attempt is gated on its own files.
    old=$(find "$run" -maxdepth 1 -name "$slice.*" ! -name "$slice.attempt-*")
    if [ -n "$old" ]; then
      n=1
      while [ -e "$run/$slice.attempt-$n" ]; do n=$((n + 1)); done
      mkdir "$run/$slice.attempt-$n"
      echo "$old" | while read -r f; do mv "$f" "$run/$slice.attempt-$n/"; done
    fi
    git rev-parse HEAD > "$run/$slice.pre"
    ;;

  gate)
    [ $# -eq 2 ] || die "usage: gate <run> <slice>"
    run=$1 slice=$2
    brief="$run/slices/$slice.md"
    for f in "$brief" "$run/slices/$slice.files" "$run/slices/$slice.cmd" "$run/$slice.pre"; do
      [ -f "$f" ] || die "missing $f"
    done
    pre=$(cat "$run/$slice.pre")
    result="$run/$slice.result"

    status=missing
    [ -f "$result" ] && status=$(field status "$result")
    if [ "$status" != PASS ]; then
      blocker=-
      [ -f "$result" ] && blocker=$(field blocker "$result")
      handoff "$run" "$slice" result "status: PASS" "status: ${status:-missing}, blocker: ${blocker:--}" \
        "cat $result" "$result"
      exit 1
    fi

    if ! grep -q '^Kind: refactor' "$brief" && [ ! -s "$run/$slice.red.txt" ]; then
      handoff "$run" "$slice" red "a red run in $run/$slice.red.txt" "no red run" \
        "ls $run/$slice.red.txt" "$brief"
      exit 1
    fi

    dirty=$(git status --porcelain)
    if [ -n "$dirty" ]; then
      handoff "$run" "$slice" clean "a clean working tree" "uncommitted changes" \
        "git status --porcelain" "$result"
      exit 1
    fi

    count=$(git rev-list --count "$pre..HEAD")
    if [ "$count" != 1 ]; then
      handoff "$run" "$slice" commits "1 commit since $pre" "$count commits" \
        "git rev-list --count $pre..HEAD" "$result"
      exit 1
    fi

    extra=$(git diff --name-only "$pre" HEAD | grep -vxF -f "$run/slices/$slice.files" || true)
    if [ -n "$extra" ]; then
      handoff "$run" "$slice" scope "only the files in $run/slices/$slice.files" \
        "files outside the brief: $(echo "$extra" | tr '\n' ' ')" \
        "git diff --name-only $pre HEAD" "$run/slices/$slice.files"
      exit 1
    fi

    test_cmd=$(cat "$run/slices/$slice.cmd")
    if ! bash -c "$test_cmd" > "$run/$slice.green.txt" 2>&1; then
      handoff "$run" "$slice" green "the slice test command exits 0" "it exits non-zero" \
        "$test_cmd" "$run/$slice.green.txt" "$run/$slice.red.txt"
      exit 1
    fi

    bash "$run/checks.sh" > "$run/$slice.checks.txt" 2>&1 || true
    code=0
    "$HARDEN" new-failures "$run/checks.expected" "$run/baseline.txt" "$run/$slice.checks.txt" \
      > "$run/$slice.new-failures.txt" || code=$?
    if [ "$code" != 0 ] && [ "$code" != 2 ]; then
      handoff "$run" "$slice" checks "new-failures exits 0 or 2" \
        "exit $code: $(tr '\n' ' ' < "$run/$slice.new-failures.txt")" \
        "bash $run/checks.sh" "$run/$slice.checks.txt" "$run/$slice.new-failures.txt"
      exit 1
    fi

    set_row "$run/slices.tsv" "$slice" done "$(git rev-list --reverse "$pre..HEAD" | paste -sd, -)" -
    echo "PASS $slice"
    ;;

  qa)
    [ $# -eq 2 ] || die "usage: qa <run> <name>"
    run=$1 name=$2
    result="$run/$name.result"
    status=missing
    [ -f "$result" ] && status=$(field status "$result")
    case "$status" in
      PASS|NOT_APPLICABLE)
        set_row "$run/slices.tsv" "$name" done - "$status"
        echo "$status $name"
        ;;
      *)
        blocker=-
        [ -f "$result" ] && blocker=$(field blocker "$result")
        handoff "$run" "$name" qa "status: PASS or NOT_APPLICABLE" \
          "status: ${status:-missing}, blocker: ${blocker:--}" "cat $result" "$result" "$run/$name"
        exit 1
        ;;
    esac
    ;;

  handoff)
    [ $# -ge 6 ] || die "usage: handoff <run> <name> <check> <expected> <observed> <repro> [evidence...]"
    handoff "$@"
    ;;

  next)
    [ $# -eq 1 ] || die "usage: next <run>"
    run=$1
    held=$(needs_human "$run")
    if [ -n "$held" ]; then
      echo "NEEDS_HUMAN $held"
      exit 1
    fi
    awk -F '\t' 'NR > 1 && $2 == "planned" { print $1 }' "$run/slices.tsv" | sort | head -n 1
    ;;

  state)
    [ $# -eq 2 ] || die "usage: state <run> <name>"
    run=$1 name=$2
    out="$run/$name.handoff.md"
    [ -f "$out" ] || die "no handoff for $name"
    then_head=$(awk '$1 == "head:" { print $2; exit }' "$out")
    then_tree=$(awk '$1 == "worktree:" { print $2; exit }' "$out")
    now_head=$(git rev-parse HEAD)
    now_tree=$(fingerprint)
    if [ "$then_head" = "$now_head" ] && [ "$then_tree" = "$now_tree" ]; then
      echo "UNCHANGED $now_head"
    else
      echo "CHANGED head $then_head -> $now_head"
      [ "$then_head" = "$now_head" ] || git log --oneline "$then_head..$now_head"
      echo "files changed since the handoff:"
      git diff --stat "$then_tree" "$now_tree"
    fi
    ;;

  mark)
    [ $# -eq 3 ] || die "usage: mark <run> <name> <status>"
    run=$1 name=$2 status=$3
    case "$status" in planned|done|dropped) ;; *) die "status must be planned, done or dropped" ;; esac
    row=$(awk -F '\t' -v n="$name" 'NR > 1 && $1 == n' "$run/slices.tsv")
    [ -n "$row" ] || die "no ledger row for $name"
    set_row "$run/slices.tsv" "$name" "$status" "$(cut -f3 <<< "$row")" "marked $status by the human"
    ;;

  *)
    die "unknown command: $cmd"
    ;;
esac
