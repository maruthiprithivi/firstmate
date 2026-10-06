import os,pathlib,subprocess,shutil,json
root=pathlib.Path.cwd(); lab=root/'.test-memory-live'; repo=lab/'runner-repo'; ev=pathlib.Path('/home/maruthiprithivi/.no-mistakes/evidence/01M47AZXT77RPR1SQQVZ9GJ423')
(repo/'bin').mkdir(parents=True,exist_ok=True); (repo/'tests').mkdir(exist_ok=True)
for name in ['fm-test-run.sh','fm-mem-box.sh','fm-heavy-guard.sh','fm-timeout-lib.sh','fm-test-isolation-proof.sh']:
 shutil.copy2(root/'bin'/name,repo/'bin'/name)
shutil.copy2(root/'tests/git-config-helpers.sh',repo/'tests/git-config-helpers.sh')
probe='''#!/usr/bin/env bash
cg="/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)"
printf 'scope=%s max=%s swap=%s inherited-cap=%s\\n' "$cg" "$(cat "$cg/memory.max")" "$(cat "$cg/memory.swap.max")" "${FM_MEM_BOX_CAP-unset}"
[ "$(cat "$cg/memory.max")" = 268435456 ] && [ "$(cat "$cg/memory.swap.max")" = 0 ] && [ "${FM_MEM_BOX_CAP-unset}" = unset ]
'''
for name in ['fm-brief.test.sh','fm-composer-lib.test.sh']:
 (repo/'tests'/name).write_text(probe)
home=lab/'runner-home'; (home/'config').mkdir(parents=True,exist_ok=True); (home/'config/memory-box').write_text('worker=512M\ntest=256M\n')
env=os.environ.copy()
for k in ['FM_ROOT_OVERRIDE','FM_HOME','FM_CONFIG_OVERRIDE','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_MEM_BOX_CAP']: env.pop(k,None)
env.update(FM_HOME=str(home),TMPDIR=str(lab))
logs=[]
for jobs in [1,2]:
 for limit in [0,10]:
  args=[str(repo/'bin/fm-test-run.sh'),'--jobs',str(jobs),'--per-script-timeout-secs',str(limit),'tests/fm-brief.test.sh','tests/fm-composer-lib.test.sh']
  p=subprocess.run(args,cwd=repo,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=45)
  logs.append({'command':args,'exit':p.returncode,'output':p.stdout}); print(json.dumps(logs[-1]),flush=True)
  (ev/'live-runner-transcript.json').write_text(json.dumps(logs,indent=2)+'\n')
  assert p.returncode==0
