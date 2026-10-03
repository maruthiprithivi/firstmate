#!/usr/bin/env bash
# Live drive of the issue-6444 duplicate-claim repair against a disposable lab
# home, a real git origin/clone, a pool-shaped worktree slot, and a real tmux
# server on the lab's private socket whose live window runs a real `codex`.
set -u
WT_ROOT=${1:?worktree root}
cd "$WT_ROOT"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
bin/fm-lab-home.sh create "$LAB" >/dev/null
TD=$(bin/fm-lab-home.sh tmux-dir "$LAB")
cleanup() {
  TMUX_TMPDIR="$TD" tmux -L fm-lab kill-server 2>/dev/null
  bin/fm-lab-home.sh teardown "$LAB" >/dev/null 2>&1
  rm -rf "$LAB"
}
trap cleanup EXIT
G="git -c user.name=lab -c user.email=lab@example.invalid"
# origin + project clone
git init -q --bare "$LAB/origin.git"
git clone -q "$LAB/origin.git" "$LAB/project" 2>/dev/null
$G -C "$LAB/project" commit -q --allow-empty -m init
git -C "$LAB/project" push -q origin HEAD:main 2>/dev/null
git -C "$LAB/project" remote set-head origin main >/dev/null 2>&1 || true
# pool slot 1, checked out on the live task's branch
mkdir -p "$LAB/pool/1"
git -C "$LAB/project" worktree add -q -b fm/live-task "$LAB/pool/1/project"
printf '{"worktrees":[{"name":"1","path":"%s"}]}\n' "$LAB/pool/1/project" > "$LAB/pool/treehouse-state.json"
echo sentinel > "$LAB/pool/1/project/sentinel"
SLOT="$LAB/pool/1/project"
# stale task: finished, landed branch (pushed to origin)
git -C "$LAB/project" branch fm/stale-task
$G -C "$LAB/project" commit -q --allow-empty -m "stale work" 2>/dev/null
git -C "$LAB/project" push -q origin HEAD:fm/stale-task 2>/dev/null
git -C "$LAB/project" branch -f fm/stale-task HEAD
# unlanded stale task branch (local only, real content)
git -C "$LAB/project" checkout -q -b fm/stale-unlanded
echo x > "$LAB/project/unlanded.txt"; git -C "$LAB/project" add unlanded.txt
$G -C "$LAB/project" commit -q -m unlanded
git -C "$LAB/project" checkout -q main 2>/dev/null || git -C "$LAB/project" checkout -q -
write_meta() { # id branch window
  printf 'window=firstmate:%s\nendpoint_task_id=%s\nworktree=%s\nproject=%s\nkind=ship\nbranch=%s\nbackend=tmux\n' \
    "$3" "$1" "$SLOT" "$LAB/project" "$2" > "$LAB/state/$1.meta"
}
write_meta live-task fm/live-task fm-live-task
write_meta stale-task fm/stale-task fm-stale-task
# real tmux on the lab socket; live window runs real codex inside the slot
TMUX_TMPDIR="$TD" tmux -L fm-lab new-session -d -s firstmate -n fm-live-task -c "$SLOT" -x 200 -y 50 codex
sleep 4
SOCK=$(TMUX_TMPDIR="$TD" tmux -L fm-lab display-message -p '#{socket_path}')
echo "== lab tmux windows (pane command):"
TMUX_TMPDIR="$TD" tmux -L fm-lab list-windows -F '#{window_name} #{pane_current_command} #{pane_current_path}' -t firstmate
run() {
  echo; echo "\$ bin/fm-teardown.sh $*"
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
    FM_HOME="$LAB" TMUX="$SOCK,0,0" TMUX_TMPDIR="$TD" bin/fm-teardown.sh "$@" 2>&1
  echo "[exit=$?]"
}
echo; echo "== Scenario A: ordinary teardown of stale record on unclaimed duplicate slot"
run stale-task
echo; echo "== Scenario B: --force combined with --release-duplicate-claim"
run stale-task --release-duplicate-claim --force
echo; echo "== Scenario C: unlanded stale branch refused"
write_meta stale-unl fm/stale-unlanded fm-stale-unl
run stale-unl --release-duplicate-claim
ls "$LAB/state"
rm -f "$LAB/state/stale-unl.meta"
echo; echo "== Scenario D: stale endpoint still running an agent refused"
TMUX_TMPDIR="$TD" tmux -L fm-lab new-window -d -t firstmate -n fm-stale-task -c "$SLOT" codex
sleep 4
run stale-task --release-duplicate-claim
TMUX_TMPDIR="$TD" tmux -L fm-lab kill-window -t firstmate:fm-stale-task
echo; echo "== Scenario E: landed stale record released records-only (stale window gone)"
run stale-task --release-duplicate-claim
echo; echo "== After release:"
echo "state/: $(ls "$LAB/state")"
echo "archive: $(ls "$LAB/data/stale-task" 2>&1)"
echo "slot sentinel: $(cat "$SLOT/sentinel" 2>&1)"
echo "slot branch: $(git -C "$SLOT" rev-parse --abbrev-ref HEAD)"
echo "live window:"; TMUX_TMPDIR="$TD" tmux -L fm-lab list-windows -F '#{window_name} #{pane_current_command}' -t firstmate
