#!/usr/bin/env bash
# Live driver: real fm-coord.sh CLI + real sqlite DB + real read-only GitHub reads via gh-axi.
# Usage: live-forge-reconcile.sh <worktree>
set -u
W=$1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-coord-live.XXXXXX")
db=$tmp/coord.sqlite3
repo=kunchenguid/firstmate
coord() { "$W/bin/fm-coord.sh" --db "$db" "$@"; }
say() { printf '\n$ fm-coord.sh %s\n' "$1"; }
run() { say "$1 ${2:-}"; out=$(coord "$1" "${2:-{\}}" 2>&1); rc=$?; printf '%s\n[exit %s]\n' "$out" "$rc"; }
f() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }
state_of() { coord inspect '{}' | python3 -c 'import json,sys; d=json.load(sys.stdin); print("queue:", {q["intent_id"]:q["state"] for q in d["queue"]}, "slots:", [(s["repo"],s["base_ref"],s["state"]) for s in d["slots"]])'; }

main_oid=$(gh-axi api GET "repos/$repo/git/ref/heads/main" --template '{{.object.sha}}' --full | sed -n 's/^  body: //p')
echo "live main OID: $main_oid"
coord init > /dev/null
coord enroll "{\"request_id\":\"e\",\"home_id\":\"h\",\"repos\":[\"$repo\"]}" > /dev/null
g=$(f "$(coord session '{"request_id":"s","home_id":"h"}')" generation)
coord manifest-set "{\"request_id\":\"m\",\"repo\":\"$repo\",\"base\":\"main\",\"checks\":[\"CI\"]}" > /dev/null

# candidate <id> <pr number> <real PR head sha>
candidate() {
  id=$1 pr=$2 head=$3 bo=${4:-$main_oid}
  coord submit "{\"request_id\":\"sub-$id\",\"intent_id\":\"$id\",\"home_id\":\"h\",\"generation\":$g,\"repo\":\"$repo\",\"base\":\"main\",\"base_oid\":\"$bo\",\"branch\":\"b/$id\",\"task_id\":\"t-$id\",\"goal\":\"live\",\"resources\":[{\"type\":\"file\",\"name\":\"x/$id\"}]}" > /dev/null
  gr=$(coord claim "{\"request_id\":\"cl-$id\",\"intent_id\":\"$id\",\"home_id\":\"h\",\"generation\":$g,\"version\":1}")
  eval "claim_$id=$(f "$gr" claim_id) fence_$id=$(f "$gr" fence)"
  c=$(eval echo "\$claim_$id"); fe=$(eval echo "\$fence_$id")
  coord attach-pr "{\"request_id\":\"pr-$id\",\"intent_id\":\"$id\",\"home_id\":\"h\",\"generation\":$g,\"claim_id\":\"$c\",\"fence\":$fe,\"pr_url\":\"https://github.com/$repo/pull/$pr\"}" > /dev/null
  coord publish-head "{\"request_id\":\"hd-$id\",\"intent_id\":\"$id\",\"home_id\":\"h\",\"generation\":$g,\"claim_id\":\"$c\",\"fence\":$fe,\"head_oid\":\"$head\",\"expected_previous_oid\":null}" > /dev/null
  coord queue-ready "{\"request_id\":\"rd-$id\",\"intent_id\":\"$id\",\"home_id\":\"h\",\"generation\":$g,\"claim_id\":\"$c\",\"fence\":$fe,\"head_oid\":\"$head\"}" > /dev/null
}
# to_unknown <id> <head> [wrapper_pid]
to_unknown() {
  id=$1 head=$2 wpid=${3:-} bo=${4:-$main_oid}
  c=$(eval echo "\$claim_$id"); fe=$(eval echo "\$fence_$id")
  run queue-next "{\"request_id\":\"nx-$id\",\"repo\":\"$repo\",\"base\":\"main\"}"
  sg=$(f "$out" generation)
  common="\"intent_id\":\"$id\",\"home_id\":\"h\",\"generation\":$g,\"claim_id\":\"$c\",\"fence\":$fe,\"slot_generation\":$sg,\"current_head_oid\":\"$head\",\"current_base_oid\":\"$bo\""
  coord queue-synced "{\"request_id\":\"sy-$id\",$common,\"head_contains_base\":true}" > /dev/null
  coord queue-validated "{\"request_id\":\"va-$id\",$common,\"validation_passed\":true,\"validation_id\":\"v-$id\"}" > /dev/null
  coord queue-checks "{\"request_id\":\"ck-$id\",$common,\"protection_available\":false,\"checks\":[{\"name\":\"CI\",\"head_oid\":\"$head\",\"conclusion\":\"success\"}]}" > /dev/null
  run queue-attempt "{\"request_id\":\"at-$id\",$common,\"head_contains_base\":true,\"captain_hold_released\":true,\"away_merge_allowed\":true,\"merge_authorized\":true${wpid:+,\"wrapper_pid\":$wpid}}"
  run queue-result "{\"request_id\":\"rs-$id\",\"intent_id\":\"$id\",\"generation\":$sg,\"outcome\":\"unknown\"}"
}
reconcile() { run queue-reconcile "{\"request_id\":\"$1\",\"intent_id\":\"$2\",\"generation\":$sg,\"pr_url\":\"https://github.com/$repo/pull/$3\",\"base\":\"main\",\"head_oid\":\"$4\"}"; }

echo; echo '=== S0 (adversarial): merged PR whose recorded base equals live base is not accepted as landing ==='
merged_head=f73bc9456dd90c59a09461fd56e3a294bde9a6bf
candidate z 6443 "$merged_head"
to_unknown z "$merged_head"
reconcile rc-z z 6443 "$merged_head"
state_of
run queue-operator-abort "{\"request_id\":\"oa-z\",\"intent_id\":\"z\",\"generation\":$sg,\"operator\":\"tester\",\"reason\":\"S0 cleanup\"}"

echo; echo '=== S1: real merged PR #6443 (attempt recorded at pre-merge base 87fa81b) reconciles to merged and frees the slot ==='
pre_merge_base=87fa81b8b7f6912f84658d52d816bb9bcc2c5da6
candidate m 6443 "$merged_head" "$pre_merge_base"
open_head=$(gh-axi api GET "repos/$repo/pulls/6484" --template '{{.head.sha}}' --full | sed -n 's/^  body: //p')
candidate o 6484 "$open_head"
to_unknown m "$merged_head" "" "$pre_merge_base"
run queue-next "{\"request_id\":\"nx-blocked\",\"repo\":\"$repo\",\"base\":\"main\"}"
state_of
reconcile rc-m m 6443 "$merged_head"
state_of

echo; echo '=== S2: real open PR #6484, live wrapper process: slot stays outcome-unknown ==='
sleep 600 & wrapper=$!
to_unknown o "$open_head" "$wrapper"
FM_COORD_QUIET_SECONDS=0 reconcile rc-o-live o 6484 "$open_head"
state_of
echo; echo '=== S3: wrapper killed but default 10-minute quiet period not elapsed: still unknown ==='
kill "$wrapper"; wait "$wrapper" 2> /dev/null
reconcile rc-o-quiet o 6484 "$open_head"
state_of
echo; echo '=== S4: wrapper gone + quiet period elapsed: live compare proves not landed -> refused, slot freed ==='
echo "live compare status: $(gh-axi api GET "repos/$repo/compare/$main_oid...$open_head" --template '{{.status}}' --full | sed -n 's/^  body: //p')"
FM_COORD_QUIET_SECONDS=0 reconcile rc-o-done o 6484 "$open_head"
state_of
echo; echo '=== S5: replay of lost reconcile reply returns stored receipt with gh-axi unavailable ==='
say "queue-reconcile (replay rc-o-done, PATH without gh-axi)"
PATH=/usr/bin:/bin:/usr/sbin:/sbin FM_COORD_QUIET_SECONDS=0 coord queue-reconcile "{\"request_id\":\"rc-o-done\",\"intent_id\":\"o\",\"generation\":$sg,\"pr_url\":\"https://github.com/$repo/pull/6484\",\"base\":\"main\",\"head_oid\":\"$open_head\"}"; echo "[exit $?]"

echo; echo '=== S6: real closed-unmerged PR #6470 with no wrapper identity never auto-releases; operator abort does ==='
closed_head=86ee74146f17f4a0dd9429f9b47e81e3d632563c
candidate u 6470 "$closed_head"
to_unknown u "$closed_head"
FM_COORD_QUIET_SECONDS=0 reconcile rc-u u 6470 "$closed_head"
state_of
run queue-operator-abort "{\"request_id\":\"oa-u\",\"intent_id\":\"u\",\"generation\":$sg,\"operator\":\"captain\",\"reason\":\"wrapper identity lost\"}"
state_of
coord outbox '{"limit":1000}' | python3 -c 'import json,sys; [print(e["seq"], e["type"], json.dumps(e["payload"])) for e in json.load(sys.stdin)["events"] if e["type"].startswith(("slot","merge","landing","outcome","terminal")) or "abort" in e["type"]]'
rm -rf "$tmp"
