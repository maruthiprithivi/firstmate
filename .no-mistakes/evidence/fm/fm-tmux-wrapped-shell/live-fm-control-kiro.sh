#!/usr/bin/env bash
# Live: fm-control.sh exit / relaunch gate against a real Kiro-wrapped zsh pane whose Codex agent is gone.
set -u
ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); "$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
TD=$("$ROOT/bin/fm-lab-home.sh" tmux-dir "$LAB"); REAL=$(command -v tmux)
mkdir -p "$LAB/shim"; printf '#!/usr/bin/env bash\nexec "%s" -L fm-lab "$@"\n' "$REAL" > "$LAB/shim/tmux"; chmod +x "$LAB/shim/tmux"
export PATH="$LAB/shim:$PATH" TMUX_TMPDIR="$TD"; unset TMUX
trap 'tmux kill-server 2>/dev/null; "$ROOT/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1; rm -rf "$LAB"' EXIT
P="$LAB/proj"; W="$LAB/wt"; git init -q "$P"; git -C "$P" commit -q --allow-empty -m init; git -C "$P" worktree add -q -b task-t1 "$W"
mkdir -p "$LAB/data/t1"; echo '# brief' > "$LAB/data/t1/brief.md"
printf 'window=fmses:fm-t1\nendpoint_task_id=t1\nworktree=%s\nproject=%s\nharness=codex\nkind=ship\nmode=no-mistakes\nyolo=off\nmodel=default\neffort=default\n' "$W" "$P" > "$LAB/state/t1.meta"
tmux new-session -d -s fmses -n fm-t1 -x 160 -y 40 -c "$W" -- /bin/zsh -il
sleep 4
tty=$(tmux display -p -t fmses:fm-t1 '#{pane_tty}')
echo "--- pane-tty foreground:"; ps -t "${tty#/dev/}" -o pid=,comm=
echo "--- simulate Codex dying at startup: codex launched then killed"
tmux send-keys -t fmses:fm-t1 "codex" Enter; sleep 6
wrap=$(ps -t "${tty#/dev/}" -o pid= | head -1 | tr -d ' '); inner=$(pgrep -P "$wrap" | head -1)
lab_codex=$(pgrep -P "$inner" codex); echo "lab codex pid(s) under wrapper $wrap -> zsh $inner: $lab_codex"
[ -n "$lab_codex" ] && kill -9 $lab_codex; sleep 2
echo "codex under lab wrapper after kill: $(pgrep -P "$inner" codex | wc -l | tr -d ' ')"
tmux capture-pane -p -t fmses:fm-t1 | grep -v '^$' | tail -3
echo "--- fm-control.sh t1 exit:"
env FM_HOME="$LAB" FM_CONTROL_EXIT_WAIT=5 "$ROOT/bin/fm-control.sh" t1 exit; echo "exit-code=$?"
