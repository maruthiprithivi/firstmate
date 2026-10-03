#!/usr/bin/env bash
# Live drive of bin/fm-coord.sh integration queue against real GitHub (read-only forge calls).
set -u
cd /Users/maruthi/.no-mistakes/worktrees/404f304dbf13/01M416J75F5TFZK6GYC131Z4VH
T=$(mktemp -d "${TMPDIR:-/tmp}/fm-coord-live.XXXXXX"); DB=$T/coord.sqlite3
c() { echo "\$ fm-coord.sh $1 ${2:-}"; bin/fm-coord.sh --db "$DB" "$@"; echo "[exit $?]"; }
j() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }
q() { bin/fm-coord.sh --db "$DB" "$@"; }
R=kunchenguid/firstmate; Z=0000000000000000000000000000000000000000
HM=f73bc9456dd90c59a09461fd56e3a294bde9a6bf; PM=6443   # real merged PR
HO=561854341b2b0c2ed1f32bea223d7a59705a8faa; PO=6499   # real open PR
BASE=$(gh api repos/$R/git/ref/heads/main --jq .object.sha)
PRE_M=87fa81b8b7f6912f84658d52d816bb9bcc2c5da6  # real base just before PR #6443 merged
FM_COORD_AUTHORITY_TOKEN=live-authority-token-0123456789abcdefXYZ c init
c enroll '{"request_id":"e-m","home_id":"home-m","repos":["'$R'"]}'
c enroll '{"request_id":"e-o","home_id":"home-o","repos":["'$R'"]}'
gm=$(j "$(q session '{"request_id":"s-m","home_id":"home-m"}')" generation)
go=$(j "$(q session '{"request_id":"s-o","home_id":"home-o"}')" generation)
c manifest-set '{"request_id":"man","repo":"'$R'","base":"main","checks":["CI"]}'
prep() { id=$1 home=$2 g=$3 head=$4 pr=$5 pri=$6
  q submit '{"request_id":"sub-'$id'","intent_id":"'$id'","home_id":"'$home'","generation":'$g',"repo":"'$R'","base":"main","base_oid":"'$Z'","branch":"b/'$id'","task_id":"'$id'","goal":"live","resources":[{"type":"file","name":"src/'$id'.py"}]}' >/dev/null
  gr=$(q claim '{"request_id":"cl-'$id'","intent_id":"'$id'","home_id":"'$home'","generation":'$g',"version":1}'); cid=$(j "$gr" claim_id); f=$(j "$gr" fence)
  q attach-pr '{"request_id":"pr-'$id'","intent_id":"'$id'","home_id":"'$home'","generation":'$g',"claim_id":"'$cid'","fence":'$f',"pr_url":"https://github.com/'$R'/pull/'$pr'"}' >/dev/null
  q publish-head '{"request_id":"hd-'$id'","intent_id":"'$id'","home_id":"'$home'","generation":'$g',"claim_id":"'$cid'","fence":'$f',"head_oid":"'$head'","expected_previous_oid":null}' >/dev/null
  c queue-ready '{"request_id":"rd-'$id'","intent_id":"'$id'","home_id":"'$home'","generation":'$g',"claim_id":"'$cid'","fence":'$f',"head_oid":"'$head'","priority":'$pri'}'; eval "CID_$id=$cid F_$id=$f"; }
advance() { id=$1 home=$2 g=$3 head=$4 sg=$5 wpid=$6; eval "cid=\$CID_$id f=\$F_$id"
  c queue-synced '{"request_id":"sy-'$id'","intent_id":"'$id'","home_id":"'$home'","generation":'$g',"claim_id":"'$cid'","fence":'$f',"slot_generation":'$sg',"current_head_oid":"'$head'","current_base_oid":"'$BASE'","head_contains_base":true}'
  c queue-validated '{"request_id":"va-'$id'","intent_id":"'$id'","home_id":"'$home'","generation":'$g',"claim_id":"'$cid'","fence":'$f',"slot_generation":'$sg',"current_head_oid":"'$head'","current_base_oid":"'$BASE'","validation_passed":true,"validation_id":"v-'$id'"}'
  echo "--- adversarial: manifest check CI missing (forge protection unavailable) must fail closed"
  c queue-checks '{"request_id":"ckx-'$id'","intent_id":"'$id'","home_id":"'$home'","generation":'$g',"claim_id":"'$cid'","fence":'$f',"slot_generation":'$sg',"current_head_oid":"'$head'","current_base_oid":"'$BASE'","protection_available":false,"checks":[{"name":"Other","head_oid":"'$head'","conclusion":"success"}]}'
  c queue-checks '{"request_id":"ck-'$id'","intent_id":"'$id'","home_id":"'$home'","generation":'$g',"claim_id":"'$cid'","fence":'$f',"slot_generation":'$sg',"current_head_oid":"'$head'","current_base_oid":"'$BASE'","protection_available":false,"checks":[{"name":"CI","head_oid":"'$head'","conclusion":"success"}]}'
  c queue-attempt '{"request_id":"at-'$id'","intent_id":"'$id'","home_id":"'$home'","generation":'$g',"claim_id":"'$cid'","fence":'$f',"slot_generation":'$sg',"current_head_oid":"'$head'","current_base_oid":"'$BASE'","head_contains_base":true,"captain_hold_released":true,"away_merge_allowed":true,"merge_authorized":true,"wrapper_pid":'$wpid'}'; }
echo "=== Scenario: two candidates, open PR #$PO priority 9, merged PR #$PM priority 0"
prep o home-o "$go" "$HO" "$PO" 9
prep m home-m "$gm" "$HM" "$PM" 0
c queue-next '{"request_id":"n1","repo":"'$R'","base":"main"}'
echo "--- adversarial: second queue-next while slot occupied"
c queue-next '{"request_id":"n1b","repo":"'$R'","base":"main"}'
sleep 600 & W=$!
advance o home-o "$go" "$HO" 1 "$W"
c queue-result '{"request_id":"res-o","intent_id":"o","generation":1,"outcome":"unknown"}'
echo "=== Scenario: wrapper alive -> live reconcile must NOT release (real forge PR #$PO open)"
FM_COORD_QUIET_SECONDS=0 c queue-reconcile '{"request_id":"rc-o1","intent_id":"o","generation":1,"pr_url":"https://github.com/'$R'/pull/'$PO'","base":"main","head_oid":"'$HO'"}'
c inspect
c queue-next '{"request_id":"n2x","repo":"'$R'","base":"main"}'
kill $W; wait $W 2>/dev/null
echo "=== Scenario: wrapper gone, quiet default 600s not elapsed -> still unknown"
c queue-reconcile '{"request_id":"rc-o2","intent_id":"o","generation":1,"pr_url":"https://github.com/'$R'/pull/'$PO'","base":"main","head_oid":"'$HO'"}'
echo "=== Scenario: wrapper gone + quiet elapsed -> live forge proves not landed -> refused, slot released"
FM_COORD_QUIET_SECONDS=0 c queue-reconcile '{"request_id":"rc-o3","intent_id":"o","generation":1,"pr_url":"https://github.com/'$R'/pull/'$PO'","base":"main","head_oid":"'$HO'"}'
c queue-next '{"request_id":"n2","repo":"'$R'","base":"main"}'
sleep 600 & W=$!
echo "--- merged candidate synced against its real pre-merge base"; BASE=$PRE_M advance m home-m "$gm" "$HM" 2 "$W"
echo "--- adversarial: queue-result claiming merged must be refused"
c queue-result '{"request_id":"res-mx","intent_id":"m","generation":2,"outcome":"merged"}'
echo "=== Scenario: live forge proves merged PR #$PM landed -> settles directly from attempting"
c queue-reconcile '{"request_id":"rc-m","intent_id":"m","generation":2,"pr_url":"https://github.com/'$R'/pull/'$PM'","base":"main"}'
echo "--- replay same request: stored receipt (forge disabled via empty PATH for gh-axi)"
PATH=/usr/bin:/bin:/usr/sbin:/sbin c queue-reconcile '{"request_id":"rc-m","intent_id":"m","generation":2,"pr_url":"https://github.com/'$R'/pull/'$PM'","base":"main"}'
kill $W 2>/dev/null; wait $W 2>/dev/null
echo "=== Scenario: slot free after merged; queue empty"
c queue-next '{"request_id":"n3","repo":"'$R'","base":"main"}'
c inspect
echo "--- terminal outcomes table"
sqlite3 "$DB" 'SELECT * FROM merge_outcomes;'
rm -rf "$T"
