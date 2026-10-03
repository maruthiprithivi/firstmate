#!/usr/bin/env bash
# Live probe: real Kiro CLI wrapper (~/.local/bin/zsh (kiro-cli-term)) in an isolated tmux server,
# classified by firstmate's tmux backend at the given checkout.
set -u
ROOT=$1; SOCK=fmlab-kiro-$$; LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-kiro.XXXXXX")
mkdir -p "$LAB/shim"; REAL=$(command -v tmux)
printf '#!/usr/bin/env bash\nexec "%s" -L "%s" "$@"\n' "$REAL" "$SOCK" > "$LAB/shim/tmux"; chmod +x "$LAB/shim/tmux"
export PATH="$LAB/shim:$PATH"; unset TMUX
trap 'tmux kill-server 2>/dev/null; rm -rf "$LAB"' EXIT
. "$ROOT/bin/fm-backend.sh"
tmux new-session -d -s k -n worker -x 160 -y 40 -c "$LAB" -- /bin/zsh -il
T=k:worker
probe() { for _ in $(seq 1 ${2:-60}); do s=$(fm_backend_agent_state tmux "$T"); [ "$s" = "$1" ] && break; sleep 0.5; done; echo "state=$s (want $1)"; }
sleep 4
tty=$(tmux display -p -t "$T" '#{pane_tty}'); echo "pane_tty=$tty"
echo "--- pane-tty processes:"; ps -t "${tty#/dev/}" -o pid=,pgid=,tpgid=,comm=
for p in $(ps -t "${tty#/dev/}" -o pid=); do echo "txt($p): $(lsof -a -p $p -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"; done
echo "--- idle wrapped shell:"; probe dead 20
tmux send-keys -t "$T" "codex" Enter
echo "--- after launching real codex:"; probe alive 60
echo "--- descendants:"; ps -axo pid=,ppid=,tty=,comm= | awk -v r="$(ps -t "${tty#/dev/}" -o pid= | head -1 | tr -d ' ')" '{p[$1]=$2;l[$1]=$0} END{s[r]=1;do{c=0;for(k in p) if(!s[k]&&s[p[k]]){s[k]=1;c=1;print l[k]}}while(c)}'
tmux send-keys -t "$T" C-c; sleep 1; tmux send-keys -t "$T" C-c
echo "--- after codex exits (dead codex, wrapper shell left):"; probe dead 40
tmux send-keys -t "$T" "sleep 900 &" Enter
echo "--- unrelated background child:"; probe ambiguous 20
tmux capture-pane -p -t "$T" | tail -8
