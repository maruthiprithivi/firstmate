#!/usr/bin/env bash
# Live drive of bin/fm-coord.sh against a throwaway DB, with real read-only GitHub forge reads via gh-axi.
set -u
W=/Users/maruthi/.no-mistakes/worktrees/404f304dbf13/01M40V40J1M9BNKDJ0XV21GXR7
T=$(mktemp -d "${TMPDIR:-/tmp}/fm-coord-live.XXXXXX"); db=$T/coord.sqlite3
trap 'rm -rf "$T"' EXIT
c() { echo "\$ fm-coord.sh $1 ${2:-}"; out=$("$W/bin/fm-coord.sh" --db "$db" "$@" 2>&1); rc=$?; echo "$out"; echo "  [exit $rc]"; }
f() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$out" "$1"; }
R=kunchenguid/firstmate
BASE=$(gh api repos/$R/git/ref/heads/main --jq .object.sha)
MERGED_PR=6443; MERGED_HEAD=f73bc9456dd90c59a09461fd56e3a294bde9a6bf
OPEN_PR=6478;  OPEN_HEAD=$(gh api repos/$R/pulls/$OPEN_PR --jq .head.sha)
BASE_A=$(gh api repos/$R/commits/d719ef3d9abdd11b0a8aea57c74de074feca99b9 --jq ".parents[0].sha")
echo "pre-merge main for #6443=$BASE_A"
echo "real main=$BASE merged PR #$MERGED_PR head=$MERGED_HEAD open PR #$OPEN_PR head=$OPEN_HEAD"
c init
c enroll '{"request_id":"e-a","home_id":"home-a","repos":["'$R'"]}'
c enroll '{"request_id":"e-b","home_id":"home-b","repos":["'$R'"]}'
c session '{"request_id":"s-a","home_id":"home-a"}'; GA=$(f generation)
c session '{"request_id":"s-b","home_id":"home-b"}'; GB=$(f generation)
c manifest-set '{"request_id":"m","repo":"'$R'","base":"main","checks":["Lint","Tests"]}'
prep() { # id home gen pr head
  c submit '{"request_id":"sub-'$1'","intent_id":"'$1'","home_id":"'$2'","generation":'$3',"repo":"'$R'","base":"main","base_oid":"'$6'","branch":"br/'$1'","task_id":"'$1'","goal":"live","resources":[{"type":"file","name":"src/'$1'.py"}]}'
  c claim '{"request_id":"cl-'$1'","intent_id":"'$1'","home_id":"'$2'","generation":'$3',"version":1}'; CL=$(f claim_id); FE=$(f fence)
  c attach-pr '{"request_id":"pr-'$1'","intent_id":"'$1'","home_id":"'$2'","generation":'$3',"claim_id":"'$CL'","fence":'$FE',"pr_url":"https://github.com/'$R'/pull/'$4'"}'
  c publish-head '{"request_id":"h-'$1'","intent_id":"'$1'","home_id":"'$2'","generation":'$3',"claim_id":"'$CL'","fence":'$FE',"head_oid":"'$5'","expected_previous_oid":null}'
  c queue-ready '{"request_id":"r-'$1'","intent_id":"'$1'","home_id":"'$2'","generation":'$3',"claim_id":"'$CL'","fence":'$FE',"head_oid":"'$5'","priority":0}'
  eval "CL_$1=$CL FE_$1=$FE"
}
echo; echo "=== S1 serial slot ==="
prep a home-a $GA $MERGED_PR $MERGED_HEAD $BASE_A
prep b home-b $GB $OPEN_PR $OPEN_HEAD $BASE
c queue-next '{"request_id":"n1","repo":"'$R'","base":"main"}'; SG=$(f generation)
c queue-next '{"request_id":"n1b","repo":"'$R'","base":"main"}'
C='"intent_id":"a","home_id":"home-a","generation":'$GA',"claim_id":"'$CL_a'","fence":'$FE_a',"slot_generation":'$SG',"current_head_oid":"'$MERGED_HEAD'","current_base_oid":"'$BASE_A'"'
echo; echo "=== S2 sync/validate/checks fail-closed ==="
c queue-synced "{\"request_id\":\"sy\",$C,\"head_contains_base\":true}"
c queue-validated "{\"request_id\":\"va\",$C,\"validation_passed\":true,\"validation_id\":\"v1\"}"
c queue-checks "{\"request_id\":\"ck0\",$C,\"protection_available\":false,\"checks\":[]}"
c queue-checks "{\"request_id\":\"ck1\",$C,\"protection_available\":false,\"checks\":[{\"name\":\"Lint\",\"head_oid\":\"$MERGED_HEAD\",\"conclusion\":\"success\"}]}"
c queue-checks "{\"request_id\":\"ck2\",$C,\"protection_available\":false,\"checks\":[{\"name\":\"Lint\",\"head_oid\":\"$MERGED_HEAD\",\"conclusion\":\"success\"},{\"name\":\"Tests\",\"head_oid\":\"$MERGED_HEAD\",\"conclusion\":\"success\"}]}"
echo; echo "=== S3 captain hold / away restriction refuse attempt; attempt returns guarded wrapper ==="
c queue-attempt "{\"request_id\":\"at-h\",$C,\"head_contains_base\":true,\"captain_hold_released\":false,\"away_merge_allowed\":true,\"merge_authorized\":true}"
c queue-attempt "{\"request_id\":\"at-w\",$C,\"head_contains_base\":true,\"captain_hold_released\":true,\"away_merge_allowed\":false,\"merge_authorized\":true}"
c queue-attempt "{\"request_id\":\"at\",$C,\"head_contains_base\":true,\"captain_hold_released\":true,\"away_merge_allowed\":true,\"merge_authorized\":true}"
echo; echo "=== S4 unknown outcome holds slot; live forge reconcile proves merged ==="
c queue-result '{"request_id":"u-a","intent_id":"a","generation":'$SG',"outcome":"unknown"}'
c queue-next '{"request_id":"n2","repo":"'$R'","base":"main"}'
c queue-reconcile '{"request_id":"rc-a","intent_id":"a","generation":'$SG',"pr_url":"https://github.com/'$R'/pull/'$MERGED_PR'","base":"main","head_oid":"'$MERGED_HEAD'"}'
echo "--- replay with gh-axi removed from PATH (no forge read) ---"
out=$(PATH=/usr/bin:/bin:/usr/sbin:/sbin "$W/bin/fm-coord.sh" --db "$db" queue-reconcile '{"request_id":"rc-a","intent_id":"a","generation":'$SG',"pr_url":"https://github.com/'$R'/pull/'$MERGED_PR'","base":"main","head_oid":"'$MERGED_HEAD'"}' 2>&1); rc=$?; echo "$out"; echo "  [exit $rc]"; command -v gh-axi >/dev/null; PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v gh-axi || echo "(gh-axi not on that PATH)"
echo; echo "=== S5 not-landed reconcile gated on wrapper exit + quiet period (real open PR) ==="
c queue-next '{"request_id":"n3","repo":"'$R'","base":"main"}'; SG=$(f generation)
C='"intent_id":"b","home_id":"home-b","generation":'$GB',"claim_id":"'$CL_b'","fence":'$FE_b',"slot_generation":'$SG',"current_head_oid":"'$OPEN_HEAD'","current_base_oid":"'$BASE'"'
c queue-synced "{\"request_id\":\"sy-b\",$C,\"head_contains_base\":true}"
c queue-validated "{\"request_id\":\"va-b\",$C,\"validation_passed\":true,\"validation_id\":\"v2\"}"
c queue-checks "{\"request_id\":\"ck-b\",$C,\"protection_available\":false,\"checks\":[{\"name\":\"Lint\",\"head_oid\":\"$OPEN_HEAD\",\"conclusion\":\"success\"},{\"name\":\"Tests\",\"head_oid\":\"$OPEN_HEAD\",\"conclusion\":\"success\"}]}"
sleep 600 & WP=$!
echo "stand-in wrapper process pid=$WP"
c queue-attempt "{\"request_id\":\"at-b\",$C,\"head_contains_base\":true,\"captain_hold_released\":true,\"away_merge_allowed\":true,\"merge_authorized\":true,\"wrapper_pid\":$WP}"
c queue-result '{"request_id":"u-b","intent_id":"b","generation":'$SG',"outcome":"unknown"}'
RB='"intent_id":"b","generation":'$SG',"pr_url":"https://github.com/'$R'/pull/'$OPEN_PR'","base":"main","head_oid":"'$OPEN_HEAD'"'
echo "--- wrapper alive, quiet 0 ---"
FM_COORD_QUIET_SECONDS=0 c queue-reconcile "{\"request_id\":\"rc-b1\",$RB}"
kill $WP; wait $WP 2>/dev/null
echo "--- wrapper exited, default 10-minute quiet period ---"
c queue-reconcile "{\"request_id\":\"rc-b2\",$RB}"
c queue-next '{"request_id":"n4","repo":"'$R'","base":"main"}'
echo "--- wrapper exited, quiet 0 (live forge: open, not queued/armed, compare main...head) ---"
echo "forge compare status: $(gh api repos/$R/compare/$BASE...$OPEN_HEAD --jq .status)"
FM_COORD_QUIET_SECONDS=0 c queue-reconcile "{\"request_id\":\"rc-b3\",$RB}"
c inspect '{}'
