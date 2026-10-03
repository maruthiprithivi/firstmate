#!/usr/bin/env bash
# Drives fm-coord-adapter.py CLI by hand: remote enroll host_id binding, missing-intent checkpoints, no-machine-id remote home.
set -u
ROOT=/w; T=$(mktemp -d); db=$T/central/coord.sqlite3; mkdir -p $T/central $T/repo $T/sshbin
cd $T/repo && git init -q -b main && git -c user.name=f -c user.email=f@x commit -q --allow-empty -m base && git remote add origin git@github.com:owner/repo.git && git update-ref refs/remotes/origin/main HEAD
printf '#!/usr/bin/env bash\nwhile [ "$#" -gt 1 ]; do shift; done\nexec /bin/bash -c "$1"\n' > $T/sshbin/ssh; chmod +x $T/sshbin/ssh
coord() { $ROOT/bin/fm-coord.sh --db $db "$@"; }
coord init >/dev/null
home() { mkdir -p $T/$1/config $T/$1/state; printf '{"mode":"shadow","home_id":"%s","repos":["owner/repo"],"remote":{"host":"coord.example","command":"%s/bin/fm-coord.sh","db":"%s"}}\n' $1 $ROOT $db > $T/$1/config/coordination.json; }
printf '## Firstmate spec\nCoordination resources: [{"type":"file","name":"src/a.py"}]\nCoordination issue: owner/repo#7\n' > $T/b.brief
echo "== container machine-id: machine:$(cat /etc/machine-id)"
home rh
echo "== remote dispatch (ssh transport)"; FM_HOME=$T/rh PATH=$T/sshbin:$PATH python3 $ROOT/bin/fm-coord-adapter.py dispatch t1 $T/repo $T/repo $T/b.brief branch/t1 codex; echo "exit=$?"
echo "== central participant row"; coord inspect '{}' | python3 -c 'import json,sys; [print(p["home_id"],p["host_id"]) for p in json.load(sys.stdin)["participants"]]'
echo "== later heartbeat reuses journaled enroll"; FM_HOME=$T/rh PATH=$T/sshbin:$PATH python3 $ROOT/bin/fm-coord-adapter.py heartbeat t1; echo "exit=$?"
for c in "heartbeat ghost" "pre-ci ghost" "pre-ci ghost $T/repo" "pre-push ghost $T/repo" "replay"; do echo "== no-intent: $c"; FM_HOME=$T/rh PATH=$T/sshbin:$PATH python3 $ROOT/bin/fm-coord-adapter.py $c; echo "exit=$?"; done
echo "== adversarial: remote home on host with no machine identity"; mv /etc/machine-id /etc/machine-id.bak; home nomid
FM_HOME=$T/nomid PATH=$T/sshbin:$PATH python3 $ROOT/bin/fm-coord-adapter.py dispatch t2 $T/repo $T/repo $T/b.brief branch/t2 codex; echo "exit=$?"
FM_HOME=$T/nomid PATH=$T/sshbin:$PATH python3 $ROOT/bin/fm-coord-adapter.py heartbeat t2; echo "exit=$?"
echo "== existing enrolled home still works without machine-id (journaled payload reused)"; FM_HOME=$T/rh PATH=$T/sshbin:$PATH python3 $ROOT/bin/fm-coord-adapter.py heartbeat t1; echo "exit=$?"
mv /etc/machine-id.bak /etc/machine-id
