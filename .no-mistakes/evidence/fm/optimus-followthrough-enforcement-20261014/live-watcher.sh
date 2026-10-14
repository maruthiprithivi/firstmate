#!/usr/bin/env bash
set -eu
LAB=$(cat .test-tmp/live-lab-path)
export FM_HOME="$LAB"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
SOCKET_DIR=$(cat "$LAB/socket-dir")
export TMUX="$SOCKET_DIR/tmux-$(id -u)/fm-lab,0,0"
export FM_ACTION_START_SECS=0 FM_SEND_SETTLE=0
bin/fm-send.sh t1 --fire-and-forget abcdef0123456789 'drain the notifications'
mv "$LAB/state/t1.inbox/002.msg" "$LAB/state/t1.inbox/handled/"
printf '\nHandled nudge, incidents at +301 seconds:\n'
bin/fm-action.sh incidents t1 --now "$(( $(date +%s) + 301 ))"
bin/fm-send.sh t1 'prepare independent image'
sleep 1
printf '\nWatcher reports unstarted real steer:\n'
bash -c '. bin/fm-watch.sh; action_followthrough_check t1'
printf '\nPersisted durable wake queue:\n'
cat "$LAB/state/.wake-queue"
FIRST=$(wc -l < "$LAB/state/.wake-queue")
printf '\nSecond poll deduplicates:\n'
bash -c '. bin/fm-watch.sh; action_followthrough_check t1'
[ "$FIRST" = "$(wc -l < "$LAB/state/.wake-queue")" ]
mv "$LAB/state/t1.inbox/003.msg" "$LAB/state/t1.inbox/handled/"
printf '\nAcknowledgement still requires execution:\n'
bash -c '. bin/fm-watch.sh; action_followthrough_check t1'
bin/fm-action.sh start t1 steer-003
printf '\nNative start clears incident and keeps a long run quiet:\n'
bash -c '. bin/fm-watch.sh; action_followthrough_check t1'
bin/fm-action.sh show t1 --now "$(( $(date +%s) + 10000 ))"
