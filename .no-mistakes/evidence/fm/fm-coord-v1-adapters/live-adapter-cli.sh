#!/usr/bin/env bash
# Live drive of bin/fm-coord-adapter.py against a real fm-coord SQLite authority.
set -u
ROOT=$1
T=$(mktemp -d "${TMPDIR:-/tmp}/fm-coord-live.XXXXXX")
DB=$T/central/coord.sqlite3
mkdir -p "$T/central"
step() { printf '\n===== %s =====\n' "$*"; }
run() { printf '$ %s\n' "$*"; "$@" 2>&1; printf '[exit=%s]\n' "$?"; }
A() { FM_HOME=$T/homeA python3 "$ROOT/bin/fm-coord-adapter.py" "$@"; }
B() { FM_HOME=$T/homeB python3 "$ROOT/bin/fm-coord-adapter.py" "$@"; }
C() { "$ROOT/bin/fm-coord.sh" --db "$DB" "$@"; }
js() { python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(eval(sys.argv[1]), sort_keys=True))" "$1"; }

# upstream + clone with origin/main
git init -q --bare "$T/up.git"
git clone -q "$T/up.git" "$T/proj" 2>/dev/null
cd "$T/proj"; git config user.email f@x.invalid; git config user.name F
mkdir src; echo a > src/a.py; echo b > src/b.py; git add .; git commit -qm base; git branch -M main; git push -q origin main
git remote set-url origin git@github.com:owner/repo.git
git update-ref refs/remotes/origin/main HEAD
for h in homeA homeB; do mkdir -p "$T/$h/config"; printf '{"mode":"advisory","home_id":"%s","repos":["owner/repo"],"db":"%s"}\n' "$h" "$DB" > "$T/$h/config/coordination.json"; done
printf 'Goal\nCoordination resources: [{"type":"file","name":"src/a.py"}]\nCoordination issue: owner/repo#1\n' > "$T/x.brief"
printf 'Goal\nCoordination resources: [{"type":"file","name":"src/a.py"}]\n' > "$T/y.brief"
git worktree add -q -b fm/x "$T/wtx" origin/main

step "S5a offline: central authority not initialized; home A dispatches task x (claude)"
run A dispatch x "$T/proj" "$T/x.brief" fm/x claude
A view 2>/dev/null | js '{"central":d["central"],"local_pending":d["local_pending"]}'

step "S5b authority comes up; replay obtains a real claim"
C init >/dev/null
run A replay
A view | js '{"claims":d["central"]["claims"],"local_pending":d["local_pending"],"x_claim_ok":d["local_tasks"]["x"]["claim"]["ok"]}'

step "S2 home B dispatches conflicting task y (codex): conflict named, no grant, exit 0"
run B dispatch y "$T/proj" "$T/y.brief" fm/y codex
B view | js '{"y_has_claim":"claim" in d["local_tasks"]["y"],"conflicts":d["central"].get("conflicts")}'

step "S8 unsupported harness (cursor): visible warning, no claim"
run B dispatch z "$T/proj" "$T/y.brief" fm/z cursor

step "S3 pre-push with undeclared path: amendment + head publish"
cd "$T/wtx"; echo x >> src/a.py; echo new > src/new.py; git add .; git commit -qm work
run A pre-push x "$T/wtx"
A view | js '{"x_resources":d["local_tasks"]["x"]["resources"],"published_head":d["local_tasks"]["x"]["published_head"],"local_pending":d["local_pending"]}'
echo "worktree HEAD: $(git -C "$T/wtx" rev-parse HEAD)"

step "S4a pre-ci with live fence: silent pass; heartbeat renews"
run A pre-ci x
run A heartbeat x
A view | js '{"local_pending":d["local_pending"]}'

step "S7 refused task y runs pre-push/pre-ci then replay must NOT reclaim after x released"
git worktree add -q -b fm/y "$T/wty" origin/main
run B pre-push y "$T/wty"
run B pre-ci y
CL=$(python3 -c "import json;s=json.load(open('$T/homeA/state/fm-coord-adapter.json'));t=s['tasks']['x'];print(json.dumps({'request_id':'rel-x','home_id':'homeA','generation':s['requests']['session']['reply']['generation'],'claim_id':t['claim']['claim_id'],'fence':t['claim']['fence']}))")
C release "$CL" | js '{"ok":d.get("ok")}'
run B replay
B view | js '{"y_has_claim":"claim" in d["local_tasks"]["y"],"active_claims":d["central"]["claims"]}'
step "S7b y's own live checkpoint (heartbeat) retries and now obtains the claim"
run B heartbeat y
B view | js '{"y_has_claim":"claim" in d["local_tasks"]["y"]}'

step "S4b stale writer: A's released fence -> pre-ci warns no grant"
run A pre-ci x

step "S9 empty declaration then filled brief re-dispatch"
printf 'Goal\nCoordination resources: []\n' > "$T/e.brief"
run A dispatch e "$T/proj" "$T/e.brief" fm/e omp
printf 'Goal\nCoordination resources: [{"type":"file","name":"src/b.py"}]\n' > "$T/e.brief"
run A dispatch e "$T/proj" "$T/e.brief" fm/e omp
A view | js '{"e_claim_ok":d["local_tasks"]["e"].get("claim",{}).get("ok")}'

step "S6 coordinator reboot simulated: expired generation -> fresh session, resubmit"
sqlite3 "$DB" "UPDATE meta SET value='other-boot' WHERE key='boot_id';" 2>&1 || sqlite3 "$DB" ".schema meta"
run A pre-ci e
A view | js '{"e_claim_ok":d["local_tasks"]["e"].get("claim",{}).get("ok"),"e_intent":d["local_tasks"]["e"]["intent_id"]}'

step "S10 opencode dispatch on disjoint file"
printf 'Goal\nCoordination resources: [{"type":"directory","name":"docs"}]\n' > "$T/o.brief"
run B dispatch o "$T/proj" "$T/o.brief" fm/o opencode
B view | js '{"o_claim_ok":d["local_tasks"]["o"].get("claim",{}).get("ok")}'
cd /; rm -rf "$T"
