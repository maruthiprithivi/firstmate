#!/usr/bin/env bash
# Live drive of the advisory integration slot: real bin/fm-coord.sh, real SQLite
# store in a throwaway lab FM_HOME, real wrapper processes, and real read-only
# GitHub forge reads (gh-axi) against kunchenguid/firstmate PRs.
set -u
WT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
export FM_HOME=$LAB
C="$WT/bin/fm-coord.sh"
run() { echo "\$ fm-coord.sh $1 ${2:-}"; "$C" "$1" "${2:-{\}}" 2>&1; echo "  [exit=$?]"; }
f() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }
REPO=kunchenguid/firstmate
OLD_BASE=d719ef3d9abdd11b0a8aea57c74de074feca99b9  # older real main commit (PR 6443 merge)
MAIN_NOW=$(gh-axi api GET repos/$REPO/git/ref/heads/main --template '{{.object.sha}}' --full | sed -n 's/^  body: //p')
echo "# lab FM_HOME=$LAB  live main=$MAIN_NOW"

echo; echo "## init without authority token (R6-1 sequence)"
run init
run enroll '{"request_id":"e-a","home_id":"a","repos":["'$REPO'"]}'
run enroll '{"request_id":"e-b","home_id":"b","repos":["'$REPO'"]}'
run enroll '{"request_id":"e-c","home_id":"c","repos":["'$REPO'"]}'
ga=$(f "$("$C" session '{"request_id":"s-a","home_id":"a"}')" generation)
gb=$(f "$("$C" session '{"request_id":"s-b","home_id":"b"}')" generation)
gc=$(f "$("$C" session '{"request_id":"s-c","home_id":"c"}')" generation)
run manifest-set '{"request_id":"m","repo":"'$REPO'","base":"main","checks":["CI"]}'

prep() { # id home gen pr head
  local id=$1 h=$2 g=$3 pr=$4 hd=$5
  "$C" submit '{"request_id":"sub-'$id'","intent_id":"'$id'","home_id":"'$h'","generation":'$g',"repo":"'$REPO'","base":"main","base_oid":"'$OLD_BASE'","branch":"br/'$id'","task_id":"t-'$id'","goal":"live","resources":[{"type":"file","name":"live/'$id'.txt"}]}' >/dev/null
  local gr; gr=$("$C" claim '{"request_id":"cl-'$id'","intent_id":"'$id'","home_id":"'$h'","generation":'$g',"version":1}')
  CL=$(f "$gr" claim_id); FE=$(f "$gr" fence)
  "$C" attach-pr '{"request_id":"pr-'$id'","intent_id":"'$id'","home_id":"'$h'","generation":'$g',"claim_id":"'$CL'","fence":'$FE',"pr_url":"https://github.com/'$REPO'/pull/'$pr'"}' >/dev/null
  "$C" publish-head '{"request_id":"hd-'$id'","intent_id":"'$id'","home_id":"'$h'","generation":'$g',"claim_id":"'$CL'","fence":'$FE',"head_oid":"'$hd'","expected_previous_oid":null}' >/dev/null
  run queue-ready '{"request_id":"rd-'$id'","intent_id":"'$id'","home_id":"'$h'","generation":'$g',"claim_id":"'$CL'","fence":'$FE',"head_oid":"'$hd'"}'
}
advance() { # id home gen head slotgen wrapperpid
  local id=$1 h=$2 g=$3 hd=$4 sg=$5 w=$6
  local common='"intent_id":"'$id'","home_id":"'$h'","generation":'$g',"claim_id":"'$CL'","fence":'$FE',"slot_generation":'$sg',"current_head_oid":"'$hd'","current_base_oid":"'$OLD_BASE'"'
  run queue-synced '{"request_id":"sy-'$id'",'"$common"',"head_contains_base":true}'
  run queue-validated '{"request_id":"va-'$id'",'"$common"',"validation_passed":true,"validation_id":"v-'$id'"}'
  run queue-checks '{"request_id":"ck-'$id'",'"$common"',"protection_available":false,"checks":[{"name":"CI","head_oid":"'$hd'","conclusion":"success"}]}'
  if [ "$id" = m ]; then
    echo "## m: attempt WITHOUT wrapper_pid -> refused"
    run queue-attempt '{"request_id":"at-nopid",'"$common"',"head_contains_base":true,"captain_hold_released":true,"away_merge_allowed":true,"merge_authorized":true}'
    echo "## m: attempt with dead wrapper_pid -> refused"
    sh -c 'exit 0' & dead=$!; wait $dead
    run queue-attempt '{"request_id":"at-deadpid",'"$common"',"head_contains_base":true,"captain_hold_released":true,"away_merge_allowed":true,"merge_authorized":true,"wrapper_pid":'$dead'}'
    echo "## m: attempt with live wrapper_pid -> attempting"
  fi
  run queue-attempt '{"request_id":"at-'$id'",'"$common"',"head_contains_base":true,"captain_hold_released":true,"away_merge_allowed":true,"merge_authorized":true,"wrapper_pid":'$w'}'
}

# Scenario 1: PR 6443 really merged; reconcile straight from attempting via live forge.
HM=f73bc9456dd90c59a09461fd56e3a294bde9a6bf
# Scenario 2: PR 6493 closed unmerged on the forge.
HR=a9bcf7c023a73c0f0a706604bc56ea108a0260e1
echo; echo "## queue three candidates: m (PR 6443 merged), r (PR 6493 closed-unmerged), w (waiter)"
prep m a "$ga" 6443 "$HM"; CLm=$CL FEm=$FE
prep r b "$gb" 6493 "$HR"; CLr=$CL FEr=$FE
prep w c "$gc" 6498 c9b2bb010a4eedebf61cf8cc76cbfa19fedbc333

echo; echo "## serial slot: first queue-next takes slot, second refused"
o=$("$C" queue-next '{"request_id":"n1","repo":"'$REPO'","base":"main"}'); echo "$o"
first=$(f "$o" intent_id); sg=$(f "$o" generation)
run queue-next '{"request_id":"n1b","repo":"'$REPO'","base":"main"}'

echo; echo "## attempt without wrapper_pid is refused (R6-1)"
CL=$([ "$first" = m ] && echo "$CLm" || echo "$CLr"); FE=$([ "$first" = m ] && echo "$FEm" || echo "$FEr")
echo "(slot holder: $first)"
NOPID='"intent_id":"m","home_id":"a","generation":'$ga',"claim_id":"'$CL'","fence":'$FE',"slot_generation":'$sg',"current_head_oid":"'$HM'","current_base_oid":"'$OLD_BASE'","head_contains_base":true,"captain_hold_released":true,"away_merge_allowed":true,"merge_authorized":true'
echo "(note: slot is in syncing state here; attempt-without-pid is retried after checks below)"

if [ "$first" != m ]; then echo "unexpected order"; fi
echo; echo "## m: full prepare + attempt with live wrapper process"
sleep 600 & WM=$!
advance m a "$ga" "$HM" "$sg" "$WM"
echo; echo "## m: reconcile directly from attempting against LIVE GitHub (PR 6443 merged)"
run queue-reconcile '{"request_id":"rc-m","intent_id":"m","generation":'$sg',"pr_url":"https://github.com/'$REPO'/pull/6443","base":"main"}'
echo "## m: replay same request (lost reply) returns stored receipt"
run queue-reconcile '{"request_id":"rc-m","intent_id":"m","generation":'$sg',"pr_url":"https://github.com/'$REPO'/pull/6443","base":"main"}'
kill $WM 2>/dev/null

echo; echo "## r: next candidate admitted after merged landing"
o=$("$C" queue-next '{"request_id":"n2","repo":"'$REPO'","base":"main"}'); echo "$o"
sg=$(f "$o" generation); CL=$CLr; FE=$FEr
sleep 600 & WR=$!
advance r b "$gb" "$HR" "$sg" "$WR"
echo "## r: wrapper reports refusal -> outcome-unknown (not released)"
run queue-result '{"request_id":"res-r","intent_id":"r","generation":'$sg',"outcome":"refused"}'
run queue-next '{"request_id":"n3-early","repo":"'$REPO'","base":"main"}'
echo "## r: reconcile while wrapper alive (live forge says closed/unmerged) -> must stay unknown"
FM_COORD_QUIET_SECONDS=0 run queue-reconcile '{"request_id":"rc-r-alive","intent_id":"r","generation":'$sg',"pr_url":"https://github.com/'$REPO'/pull/6493","base":"main","head_oid":"'$HR'"}'
echo "## r: operator abort without enrolled token refused"
FM_COORD_AUTHORITY_TOKEN=live-lab-authority-credential-0123456789 run queue-operator-abort '{"request_id":"ab-r","intent_id":"r","generation":'$sg',"reason":"stuck"}'
echo "## r: wrapper exits; quiet period 0; reconcile with live forge -> refused, slot released"
kill $WR; wait $WR 2>/dev/null
FM_COORD_QUIET_SECONDS=0 run queue-reconcile '{"request_id":"rc-r","intent_id":"r","generation":'$sg',"pr_url":"https://github.com/'$REPO'/pull/6493","base":"main","head_oid":"'$HR'"}'
echo; echo "## w: slot released after not-landed reconcile; waiter admitted"
run queue-next '{"request_id":"n3","repo":"'$REPO'","base":"main"}'

echo; echo "## one-time authority enrollment on existing v3 db"
FM_COORD_AUTHORITY_TOKEN=live-lab-authority-credential-0123456789 run init
FM_COORD_AUTHORITY_TOKEN=different-authority-credential-9876543210 run init

echo; echo "## persisted state"
sqlite3 -header "$LAB/state/fm-coord.sqlite3" "SELECT intent_id,state,head_oid,base_oid FROM queue_items ORDER BY intent_id; SELECT intent_id,outcome,merge_oid,observed_base_oid FROM merge_outcomes; SELECT * FROM integration_slots; SELECT key, length(value) AS len FROM meta WHERE key LIKE 'authority%';"
sqlite3 "$LAB/state/fm-coord.sqlite3" "SELECT event_type FROM events ORDER BY seq" | tr '\n' ' '; echo
rm -rf "$LAB"; echo "# lab removed"
