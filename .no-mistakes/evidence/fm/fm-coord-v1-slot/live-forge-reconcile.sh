#!/usr/bin/env bash
# Live scenario driver: fm-coord.sh queue lifecycle reconciled against REAL GitHub PRs
# in kunchenguid/firstmate via read-only gh-axi api calls. Temp DB only.
set -u
ROOT=$1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-coord-live.XXXXXX")
db=$tmp/coord.sqlite3
coord() { echo "\$ fm-coord.sh $1 $(printf '%s' "${2:-}" | cut -c1-160)" >&2; "$ROOT/bin/fm-coord.sh" --db "$db" "$@"; }
field() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }
R=kunchenguid/firstmate
base_old=0000000000000000000000000000000000000001
live_base=$(gh-axi api GET repos/$R/git/ref/heads/main --template '{{.object.sha}}' --full | sed -n 's/^  body: //p')
echo "live main = $live_base"
coord init >/dev/null
coord enroll "{\"request_id\":\"e\",\"home_id\":\"a\",\"repos\":[\"$R\"]}" >/dev/null
g=$(field "$(coord session '{"request_id":"s","home_id":"a"}')" generation)
coord manifest-set "{\"request_id\":\"m\",\"repo\":\"$R\",\"base\":\"main\",\"checks\":[\"CI\"]}" >/dev/null
# run_candidate id pr head base_at_attempt wrapper_pid
run_candidate() {
  id=$1 pr=$2 head=$3 b=$4 wp=${5:-}
  coord submit "{\"request_id\":\"sub-$id\",\"intent_id\":\"$id\",\"home_id\":\"a\",\"generation\":$g,\"repo\":\"$R\",\"base\":\"main\",\"base_oid\":\"$b\",\"branch\":\"br/$id\",\"task_id\":\"$id\",\"goal\":\"live\",\"resources\":[{\"type\":\"file\",\"name\":\"f/$id\"}]}" >/dev/null
  gr=$(coord claim "{\"request_id\":\"cl-$id\",\"intent_id\":\"$id\",\"home_id\":\"a\",\"generation\":$g,\"version\":1}")
  c=$(field "$gr" claim_id); f=$(field "$gr" fence)
  w="\"intent_id\":\"$id\",\"home_id\":\"a\",\"generation\":$g,\"claim_id\":\"$c\",\"fence\":$f"
  coord attach-pr "{\"request_id\":\"pr-$id\",$w,\"pr_url\":\"https://github.com/$R/pull/$pr\"}" >/dev/null
  coord publish-head "{\"request_id\":\"h-$id\",$w,\"head_oid\":\"$head\",\"expected_previous_oid\":null}" >/dev/null
  coord queue-ready "{\"request_id\":\"r-$id\",$w,\"head_oid\":\"$head\"}" >/dev/null
  pick=$(coord queue-next "{\"request_id\":\"n-$id\",\"repo\":\"$R\",\"base\":\"main\"}"); echo "queue-next -> $pick"
  slot=$(field "$pick" generation)
  cm="$w,\"slot_generation\":$slot,\"current_head_oid\":\"$head\",\"current_base_oid\":\"$b\""
  coord queue-synced "{\"request_id\":\"sy-$id\",$cm,\"head_contains_base\":true}"; echo
  coord queue-validated "{\"request_id\":\"v-$id\",$cm,\"validation_passed\":true,\"validation_id\":\"val-$id\"}"; echo
  coord queue-checks "{\"request_id\":\"ck-$id\",$cm,\"protection_available\":false,\"checks\":[{\"name\":\"CI\",\"head_oid\":\"$head\",\"conclusion\":\"success\"}]}"; echo
  coord queue-attempt "{\"request_id\":\"at-$id\",$cm,\"head_contains_base\":true,\"captain_hold_released\":true,\"away_merge_allowed\":true,\"merge_authorized\":true${wp:+,\"wrapper_pid\":$wp}}"; echo
  coord queue-result "{\"request_id\":\"res-$id\",\"intent_id\":\"$id\",\"generation\":$slot,\"outcome\":\"unknown\"}"; echo
}
reconcile() { coord queue-reconcile "{\"request_id\":\"$1\",\"intent_id\":\"$2\",\"generation\":$slot,\"pr_url\":\"https://github.com/$R/pull/$3\",\"base\":\"main\",\"head_oid\":\"$4\"}"; echo " [exit=$?]"; }
slots() { coord inspect '{}' | python3 -c 'import json,sys; d=json.load(sys.stdin); print("slots:",[(s["intent_id"],s["state"]) for s in d["slots"]]); print("queue:",[(q["intent_id"],q["state"]) for q in d["queue"]])'; }

echo; echo "=== L1 adversarial: merged PR 6443 recorded with WRONG head must not settle ==="
run_candidate wronghead 6443 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa $base_old
reconcile rc-wrong wronghead 6443 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 2>&1 | tail -2
slots
coord queue-operator-abort "{\"request_id\":\"oa-wrong\",\"intent_id\":\"wronghead\",\"generation\":$slot,\"operator\":\"live-test\",\"reason\":\"wrong head fixture\"}"; echo
slots

echo; echo "=== L2: merged PR 6443 at exact head: live forge read settles merged and frees slot ==="
run_candidate landed 6443 f73bc9456dd90c59a09461fd56e3a294bde9a6bf $base_old
reconcile rc-landed landed 6443 f73bc9456dd90c59a09461fd56e3a294bde9a6bf
slots

echo; echo "=== L3: open PR 6490, wrapper still alive: must stay outcome-unknown ==="
sleep 600 & wp=$!
run_candidate open 6490 d0d608fb2d0a75908458822d442516d72e18de36 $live_base $wp
FM_COORD_QUIET_SECONDS=0 reconcile rc-live-wrapper open 6490 d0d608fb2d0a75908458822d442516d72e18de36 2>&1 | tail -2
slots
echo; echo "=== L4: wrapper exited but default 10-minute quiet period not elapsed: stays unknown ==="
kill $wp; wait $wp 2>/dev/null
reconcile rc-quiet open 6490 d0d608fb2d0a75908458822d442516d72e18de36 2>&1 | tail -2
slots
echo; echo "=== L5: wrapper gone + quiet period (seam=0): live read proves not landed -> refused, slot freed ==="
FM_COORD_QUIET_SECONDS=0 reconcile rc-unlanded open 6490 d0d608fb2d0a75908458822d442516d72e18de36
slots
echo; echo "=== L6: replay (gh-axi shim always fails = forge unreachable); of rc-unlanded with forge unreachable returns stored receipt ==="
mkdir -p "$tmp/nofor"; printf '#!/bin/sh\necho forge-unreachable >&2; exit 1\n' > "$tmp/nofor/gh-axi"; chmod +x "$tmp/nofor/gh-axi"
PATH="$tmp/nofor:$PATH" "$ROOT/bin/fm-coord.sh" --db "$db" queue-reconcile "{\"request_id\":\"rc-unlanded\",\"intent_id\":\"open\",\"generation\":$slot,\"pr_url\":\"https://github.com/$R/pull/6490\",\"base\":\"main\",\"head_oid\":\"d0d608fb2d0a75908458822d442516d72e18de36\"}"; echo " [exit=$?]"
echo; echo "=== outbox event types ==="
coord outbox '{"limit":1000}' | python3 -c 'import json,sys; print([e["type"] for e in json.load(sys.stdin)["events"]])'
rm -rf "$tmp"
