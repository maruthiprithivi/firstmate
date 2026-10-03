#!/usr/bin/env bash
# Live drive of bin/fm-coord.sh integration queue against real GitHub PRs in
# kunchenguid/firstmate (read-only gh-axi api calls). Throwaway DB under $TMPDIR.
# Usage: live-queue-github.sh <worktree>
set -u
ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-coord-live.XXXXXX")
trap 'kill $W1 $W2 2>/dev/null; rm -rf "$LAB"' EXIT
db=$LAB/coord.sqlite3
coord() { "$ROOT/bin/fm-coord.sh" --db "$db" "$@"; }
show() { printf '\n$ fm-coord.sh %s %s\n' "$1" "${2:-}"; out=$(coord "$@" 2>&1); rc=$?; printf '%s\n[exit %s]\n' "$out" "$rc"; }
f() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }
R=kunchenguid/firstmate
BASE=$(gh-axi api GET repos/$R/git/ref/heads/main --template '{{.object.sha}}' --full | sed -n 's/^  body: //p')
H_MERGED=f73bc9456dd90c59a09461fd56e3a294bde9a6bf   # PR 6443, merged
PRE_MERGE_BASE=87fa81b8b7f6912f84658d52d816bb9bcc2c5da6  # main just before 6443 landed (attempt-time base)
H_OPEN=b20ccf113cdf1730aa893a214ed8b8ff9e3717a8     # PR 6504, open
H_REMOTE=561854341b2b0c2ed1f32bea223d7a59705a8faa   # PR 6499, open
echo "live main base: $BASE"
echo "machine identity source: $(uname -s)"

FM_COORD_AUTHORITY_TOKEN=live-authority-token-0123456789abcdef coord init
coord enroll '{"request_id":"e-a","home_id":"a","repos":["'$R'"]}' >/dev/null
coord enroll '{"request_id":"e-b","home_id":"b","repos":["'$R'"]}' >/dev/null
coord enroll '{"request_id":"e-r","home_id":"remote","repos":["'$R'"],"host_id":"remote-box-1"}' >/dev/null
echo "participants host binding:"; coord inspect | python3 -c 'import json,sys; [print(" ",p["home_id"],p["host_id"]) for p in json.load(sys.stdin)["participants"]]'
ga=$(f "$(coord session '{"request_id":"s-a","home_id":"a"}')" generation)
gb=$(f "$(coord session '{"request_id":"s-b","home_id":"b"}')" generation)
gr=$(f "$(coord session '{"request_id":"s-r","home_id":"remote"}')" generation)
coord manifest-set '{"request_id":"m","repo":"'$R'","base":"main","checks":["CI"]}' >/dev/null

cand() { # id home gen head prnum
  coord submit '{"request_id":"sub-'$1'","intent_id":"'$1'","home_id":"'$2'","generation":'$3',"repo":"'$R'","base":"main","base_oid":"'$BASE'","branch":"b/'$1'","task_id":"'$1'","goal":"live","resources":[{"type":"file","name":"x/'$1'"}]}' >/dev/null
  g=$(coord claim '{"request_id":"cl-'$1'","intent_id":"'$1'","home_id":"'$2'","generation":'$3',"version":1}')
  C=$(f "$g" claim_id); F=$(f "$g" fence)
  coord attach-pr '{"request_id":"pr-'$1'","intent_id":"'$1'","home_id":"'$2'","generation":'$3',"claim_id":"'$C'","fence":'$F',"pr_url":"https://github.com/'$R'/pull/'$5'"}' >/dev/null
  coord publish-head '{"request_id":"hd-'$1'","intent_id":"'$1'","home_id":"'$2'","generation":'$3',"claim_id":"'$C'","fence":'$F',"head_oid":"'$4'","expected_previous_oid":null}' >/dev/null
  coord queue-ready '{"request_id":"rd-'$1'","intent_id":"'$1'","home_id":"'$2'","generation":'$3',"claim_id":"'$C'","fence":'$F',"head_oid":"'$4'","priority":0}' >/dev/null
}
prep() { # id home gen head slotgen
  w='"intent_id":"'$1'","home_id":"'$2'","generation":'$3',"claim_id":"'$C'","fence":'$F',"slot_generation":'$5',"current_head_oid":"'$4'","current_base_oid":"'${PREP_BASE:-$BASE}'"'
  show queue-synced '{"request_id":"sy-'$1'",'"$w"',"head_contains_base":true}'
  show queue-validated '{"request_id":"va-'$1'",'"$w"',"validation_passed":true,"validation_id":"live-'$1'"}'
  show queue-checks '{"request_id":"ck-'$1'",'"$w"',"protection_available":false,"checks":[{"name":"CI","head_oid":"'$4'","conclusion":"success"}]}'
}

echo; echo "=== Scenario 1: serial slot + live reconcile of a real merged PR (6443)"
cand a a "$ga" "$H_MERGED" 6443; Ca=$C Fa=$F
cand b b "$gb" "$H_OPEN" 6504; Cb=$C Fb=$F
n=$(coord queue-next '{"request_id":"n1","repo":"'$R'","base":"main"}'); echo "$n"; s1=$(f "$n" generation)
show queue-next '{"request_id":"n1-dup","repo":"'$R'","base":"main"}'
C=$Ca F=$Fa; PREP_BASE=$PRE_MERGE_BASE prep a a "$ga" "$H_MERGED" "$s1"
sleep 600 & W1=$!
show queue-attempt '{"request_id":"at-a","intent_id":"a","home_id":"a","generation":'$ga',"claim_id":"'$Ca'","fence":'$Fa',"slot_generation":'$s1',"current_head_oid":"'$H_MERGED'","current_base_oid":"'$PRE_MERGE_BASE'","head_contains_base":true,"captain_hold_released":true,"away_merge_allowed":true,"merge_authorized":true,"wrapper_pid":'$W1'}'
show queue-result '{"request_id":"rs-a","intent_id":"a","generation":'$s1',"outcome":"unknown"}'
show queue-next '{"request_id":"n-blocked","repo":"'$R'","base":"main"}'
show queue-reconcile '{"request_id":"rc-a","intent_id":"a","generation":'$s1',"pr_url":"https://github.com/'$R'/pull/6443","base":"main","head_oid":"'$H_MERGED'"}'
kill $W1

echo; echo "=== Scenario 2: real open PR (6504): reconcile refused while wrapper alive, released after wrapper gone"
n=$(coord queue-next '{"request_id":"n2","repo":"'$R'","base":"main"}'); echo "$n"; s2=$(f "$n" generation)
C=$Cb F=$Fb; prep b b "$gb" "$H_OPEN" "$s2"
sleep 600 & W2=$!
show queue-attempt '{"request_id":"at-b","intent_id":"b","home_id":"b","generation":'$gb',"claim_id":"'$Cb'","fence":'$Fb',"slot_generation":'$s2',"current_head_oid":"'$H_OPEN'","current_base_oid":"'$BASE'","head_contains_base":true,"captain_hold_released":true,"away_merge_allowed":true,"merge_authorized":true,"wrapper_pid":'$W2'}'
show queue-result '{"request_id":"rs-b","intent_id":"b","generation":'$s2',"outcome":"refused"}'
FM_COORD_QUIET_SECONDS=0 show queue-reconcile '{"request_id":"rc-b-alive","intent_id":"b","generation":'$s2',"pr_url":"https://github.com/'$R'/pull/6504","base":"main","head_oid":"'$H_OPEN'"}'
kill $W2; wait $W2 2>/dev/null
show queue-reconcile '{"request_id":"rc-b-noquiet","intent_id":"b","generation":'$s2',"pr_url":"https://github.com/'$R'/pull/6504","base":"main","head_oid":"'$H_OPEN'"}'
export FM_COORD_QUIET_SECONDS=0
show queue-reconcile '{"request_id":"rc-b","intent_id":"b","generation":'$s2',"pr_url":"https://github.com/'$R'/pull/6504","base":"main","head_oid":"'$H_OPEN'"}'
unset FM_COORD_QUIET_SECONDS

echo; echo "=== Scenario 3: remote wrapper; remote session restarts before exit attestation (R7-1)"
cand r remote "$gr" "$H_REMOTE" 6499; Cr=$C Fr=$F
n=$(coord queue-next '{"request_id":"n3","repo":"'$R'","base":"main"}'); echo "$n"; s3=$(f "$n" generation)
prep r remote "$gr" "$H_REMOTE" "$s3"
at=$(coord queue-attempt '{"request_id":"at-r","intent_id":"r","home_id":"remote","generation":'$gr',"claim_id":"'$Cr'","fence":'$Fr',"slot_generation":'$s3',"current_head_oid":"'$H_REMOTE'","current_base_oid":"'$BASE'","head_contains_base":true,"captain_hold_released":true,"away_merge_allowed":true,"merge_authorized":true,"wrapper_pid":4242,"wrapper_start":"remote-start-xyz"}'); echo "$at"
aid=$(f "$at" attempt_event_id)
show queue-result '{"request_id":"rs-r","intent_id":"r","generation":'$s3',"outcome":"unknown"}'
FM_COORD_QUIET_SECONDS=0 show queue-reconcile '{"request_id":"rc-r-noattest","intent_id":"r","generation":'$s3',"pr_url":"https://github.com/'$R'/pull/6499","base":"main","head_oid":"'$H_REMOTE'"}'
gr2=$(f "$(coord session '{"request_id":"s-r2","home_id":"remote"}')" generation); echo "remote session restarted: generation $gr -> $gr2"
show queue-wrapper-exited '{"request_id":"ex-wrongstart","intent_id":"r","home_id":"remote","generation":'$gr2',"slot_generation":'$s3',"attempt_event_id":"'$aid'","wrapper_host_id":"remote-box-1","wrapper_pid":4242,"wrapper_start":"forged"}'
show queue-wrapper-exited '{"request_id":"ex-r","intent_id":"r","home_id":"remote","generation":'$gr2',"slot_generation":'$s3',"attempt_event_id":"'$aid'","wrapper_host_id":"remote-box-1","wrapper_pid":4242,"wrapper_start":"remote-start-xyz"}'
FM_COORD_QUIET_SECONDS=0 show queue-reconcile '{"request_id":"rc-r","intent_id":"r","generation":'$s3',"pr_url":"https://github.com/'$R'/pull/6499","base":"main","head_oid":"'$H_REMOTE'"}'

echo; echo "=== Final state"
coord inspect | python3 -c 'import json,sys; s=json.load(sys.stdin); [print(" queue",q["intent_id"],q["state"]) for q in s["queue"]]; print(" slots",s.get("slots"))'
