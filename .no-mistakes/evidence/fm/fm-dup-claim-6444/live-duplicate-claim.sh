#!/usr/bin/env bash
# Live drive of bin/fm-teardown.sh against a disposable lab home, a real git
# Treehouse-shaped pool slot, and a real tmux server on the private fm-lab socket.
# Run from the gate worktree. Prints a transcript; removes the lab at the end.
set -u
WT=$(pwd -P)
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
LAB=$(cd "$LAB" && pwd -P)
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux" "$LAB/bin"
export TMUX_TMPDIR="$LAB/tmux"
unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE \
  FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE TMUX
export FM_HOME="$LAB"
T() { tmux -L fm-lab "$@"; }
cleanup() { T kill-server 2>/dev/null; rm -rf "$LAB"; }
trap cleanup EXIT

say() { printf '\n### %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; "$@"; printf '[exit %s]\n' "$?"; }

# "Agent" for the live owner: a pane process whose argv0 is codex.
printf '#!/usr/bin/env bash\nexec -a codex sleep 3600\n' > "$LAB/bin/agent"
chmod +x "$LAB/bin/agent"

T new-session -d -s firstmate -n fm-live-task -c "$LAB" "$LAB/bin/agent"
SOCK=$(T display-message -p '#{socket_path}')
export TMUX="$SOCK,$$,0"
sleep 1

stage() {  # <name> [mode]
  local name=$1 mode=${2:-}
  P="$LAB/projects/$name"; POOL="$LAB/pool-$name"
  rm -rf "$P" "$POOL"
  mkdir -p "$P" "$POOL/1"
  git -C "$P" init -q -b main
  git -C "$P" -c user.name=lab -c user.email=lab@example.invalid commit --allow-empty -qm init
  git -C "$P" worktree add -q --detach "$POOL/1/project"
  printf '{"worktrees":[{"name":"1","path":"%s"}]}\n' "$POOL/1/project" > "$POOL/treehouse-state.json"
  SLOT="$POOL/1/project"
  : > "$SLOT/sentinel"
  git -C "$P" branch fm/live-task
  git -C "$P" branch fm/stale-task
  rm -f "$LAB/state/"*.meta
  rm -rf "$LAB/data/stale-task"
  printf '%s\n' window=firstmate:fm-stale-task endpoint_task_id=stale-task "worktree=$SLOT" \
    "project=$P" kind=ship branch=fm/stale-task spawn_gen=spawn-stale ${mode:+"mode=$mode"} \
    > "$LAB/state/stale-task.meta"
  printf '%s\n' window=firstmate:fm-live-task endpoint_task_id=live-task "worktree=$SLOT" \
    "project=$P" kind=ship branch=fm/live-task spawn_gen=spawn-live ${mode:+"mode=$mode"} \
    > "$LAB/state/live-task.meta"
}
unique_commit() {  # adds a real content change on fm/stale-task
  local blob tree c
  blob=$(printf 'stale work\n' | git -C "$P" hash-object -w --stdin)
  tree=$(printf '100644 blob %s\tstale.txt\n' "$blob" | git -C "$P" mktree)
  c=$(printf 'stale work\n' | git -C "$P" -c user.name=lab -c user.email=lab@example.invalid commit-tree "$tree" -p main)
  git -C "$P" update-ref refs/heads/fm/stale-task "$c"
  printf '%s\n' "$c"
}
state() {
  printf -- '- records: %s\n' "$(cd "$LAB/state" && ls *.meta 2>/dev/null | tr '\n' ' ')"
  printf -- '- archived: %s\n' "$(ls "$LAB/data/stale-task/" 2>/dev/null | tr '\n' ' ')"
  printf -- '- slot sentinel: %s\n' "$([ -e "$SLOT/sentinel" ] && echo present || echo GONE)"
  printf -- '- live window: %s\n' "$(T list-windows -t firstmate -F '#{window_name}' | tr '\n' ' ')"
  printf -- '- live pane cmd: %s\n' "$(T display-message -p -t firstmate:fm-live-task '#{pane_current_command}')"
}
TD="$WT/bin/fm-teardown.sh"

say "S1 issue-6444 collision: ordinary teardown of stale record on unclaimed shared slot"
stage s1
run "$TD" stale-task; state

say "S2 --force with --release-duplicate-claim is rejected"
run "$TD" stale-task --release-duplicate-claim --force; state

say "S3 release refused: stale endpoint has a live agent"
T new-window -d -t firstmate -n fm-stale-task -c "$LAB" "$LAB/bin/agent"; sleep 1
run "$TD" stale-task --release-duplicate-claim; state
T kill-window -t firstmate:fm-stale-task

say "S4 release refused: stale branch has unlanded local-only work"
stage s4 local-only
unique_commit >/dev/null
run "$TD" stale-task --release-duplicate-claim; state

say "S5 release succeeds once local-only work is on local main (stale endpoint missing)"
git -C "$P" update-ref refs/heads/main "$(git -C "$P" rev-parse fm/stale-task)"
run "$TD" stale-task --release-duplicate-claim; state
[ -f "$LAB/data/stale-task/retired-duplicate-claim.meta" ] && { echo '--- archived record:'; cat "$LAB/data/stale-task/retired-duplicate-claim.meta"; }

say "S6 base path unchanged: slot claim names live-task, ordinary teardown retires stale records-only"
stage s6
printf 'task=live-task\nhome=%s\n' "$LAB" > "$POOL/1/.fm-slot-owner"
run "$TD" stale-task; state
printf -- '- slot claim: %s\n' "$(tr '\n' ' ' < "$POOL/1/.fm-slot-owner")"

say "S7 release refused when the claim already names another task (ordinary teardown owns that case)"
printf '%s\n' window=firstmate:fm-stale-task endpoint_task_id=stale-task "worktree=$SLOT" \
  "project=$P" kind=ship branch=fm/stale-task spawn_gen=spawn-stale > "$LAB/state/stale-task.meta"
run "$TD" stale-task --release-duplicate-claim; state
