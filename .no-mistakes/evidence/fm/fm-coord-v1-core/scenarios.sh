#!/usr/bin/env bash
# Live CLI transcript of fm-coord scenarios beyond tests/fm-coord.test.sh.
set -u
C=/src/bin/fm-coord.sh; D=$(mktemp -d)/c.db
co(){ echo "\$ fm-coord $1 ${2:-}"; "$C" --db "$D" "$@"; echo "[exit $?]"; }
Z=0000000000000000000000000000000000000000; H1=1111111111111111111111111111111111111111; H2=2222222222222222222222222222222222222222
j(){ python3 -c 'import json,sys;print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }
echo "== setup"; co init; co enroll '{"request_id":"e-a","home_id":"a","repos":["o/r"]}'; co enroll '{"request_id":"e-b","home_id":"b","repos":["o/r"]}'
co session '{"request_id":"s-a","home_id":"a"}'; co session '{"request_id":"s-b","home_id":"b"}'
echo "== S1 scope expansion requires explicit amend; expanded scope then blocks others"
co submit '{"request_id":"sub-a","intent_id":"ia","home_id":"a","generation":1,"repo":"o/r","base":"main","base_oid":"'$Z'","branch":"t/a","task_id":"a","goal":"g","resources":[{"type":"file","name":"x.py"}]}'
R=$("$C" --db "$D" claim '{"request_id":"cl-a","intent_id":"ia","home_id":"a","generation":1,"version":1}'); echo "$R"; CID=$(j "$R" claim_id); F=$(j "$R" fence)
co submit '{"request_id":"sub-b","intent_id":"ib","home_id":"b","generation":1,"repo":"o/r","base":"main","base_oid":"'$Z'","branch":"t/b","task_id":"b","goal":"g","resources":[{"type":"file","name":"y.py"}]}'
co amend '{"request_id":"am-drop","intent_id":"ia","home_id":"a","generation":1,"claim_id":"'$CID'","fence":'$F',"version":1,"resources":[{"type":"file","name":"y.py"}]}'
co amend '{"request_id":"am-a","intent_id":"ia","home_id":"a","generation":1,"claim_id":"'$CID'","fence":'$F',"version":1,"resources":[{"type":"file","name":"x.py"},{"type":"file","name":"y.py"}]}'
co claim '{"request_id":"cl-b","intent_id":"ib","home_id":"b","generation":1,"version":1}'
echo "== S2 immutable head with expected-previous guard"
co publish-head '{"request_id":"ph1","intent_id":"ia","home_id":"a","generation":1,"claim_id":"'$CID'","fence":'$F',"head_oid":"'$H1'","expected_previous_oid":null}'
co publish-head '{"request_id":"ph-bad","intent_id":"ia","home_id":"a","generation":1,"claim_id":"'$CID'","fence":'$F',"head_oid":"'$H2'","expected_previous_oid":null}'
co publish-head '{"request_id":"ph2","intent_id":"ia","home_id":"a","generation":1,"claim_id":"'$CID'","fence":'$F',"head_oid":"'$H2'","expected_previous_oid":"'$H1'"}'
co publish-head '{"request_id":"ph-short","intent_id":"ia","home_id":"a","generation":1,"claim_id":"'$CID'","fence":'$F',"head_oid":"abc123","expected_previous_oid":"'$H2'"}'
echo "== S3 idempotency: replay identical, reject reuse with different payload"
co publish-head '{"request_id":"ph1","intent_id":"ia","home_id":"a","generation":1,"claim_id":"'$CID'","fence":'$F',"head_oid":"'$H1'","expected_previous_oid":null}'
co publish-head '{"request_id":"ph1","intent_id":"ia","home_id":"a","generation":1,"claim_id":"'$CID'","fence":'$F',"head_oid":"'$H2'","expected_previous_oid":null}'
echo "== S4 durable loser conflict event in outbox"
co outbox '{"limit":1000}' | python3 -c 'import sys,json;l=sys.stdin.readline;print(l().rstrip());d=json.loads(l());print("events:",[(e["seq"],e["type"],e["request_id"]) for e in d["events"]])' 
echo "== S5 path canonicalization refuses escapes"
co submit '{"request_id":"sub-esc","intent_id":"iesc","home_id":"b","generation":1,"repo":"o/r","base":"main","base_oid":"'$Z'","branch":"t/esc","task_id":"e","goal":"g","resources":[{"type":"file","name":"../etc/passwd"}]}'
co submit '{"request_id":"sub-abs","intent_id":"iabs","home_id":"b","generation":1,"repo":"o/r","base":"main","base_oid":"'$Z'","branch":"t/abs","task_id":"e","goal":"g","resources":[{"type":"file","name":"/etc/passwd"}]}'
co submit '{"request_id":"sub-scope","intent_id":"isc","home_id":"b","generation":1,"repo":"other/repo","base":"main","base_oid":"'$Z'","branch":"t/sc","task_id":"e","goal":"g","resources":[{"type":"file","name":"z"}]}'
echo "== S6 simulated reboot / copied DB on another boot: live claims revoked, old generation rejected, new session required"
sqlite3 "$D" "UPDATE meta SET value='other-boot' WHERE key='boot_id'"
co check '{"home_id":"a","generation":1,"claim_id":"'$CID'","fence":'$F'}'
co inspect
co session '{"request_id":"s-a2","home_id":"a"}'
co claim '{"request_id":"cl-b2","intent_id":"ib","home_id":"b","generation":1,"version":1}'
echo "== S7 refuses future schema"
sqlite3 "$D" "PRAGMA user_version=2"; co inspect
