import os, pathlib, subprocess, json, shlex, re
root=pathlib.Path.cwd(); lab=root/'.test-memory-live'; ev=pathlib.Path('/home/maruthiprithivi/.no-mistakes/evidence/01M47AZXT77RPR1SQQVZ9GJ423')
base=os.environ.copy()
for k in ['FM_HOME','FM_CONFIG_OVERRIDE','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_ROOT_OVERRIDE','FM_MEM_BOX_CAP','TASKS_AXI_FILE','TASKS_AXI_BACKEND']:
 base.pop(k,None)
home=lab/'home'; home.mkdir(exist_ok=True)
log=[]
def run(args,env={},timeout=30):
 e=base|env
 try:
  p=subprocess.run(list(map(str,args)),env=e,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
  rc=p.returncode; out=p.stdout
 except subprocess.TimeoutExpired as x:
  rc=124; out=(x.stdout or b'').decode() if isinstance(x.stdout,bytes) else (x.stdout or '')
 log.append({'command':shlex.join(list(map(str,args))),'env':env,'exit':rc,'output':out}); print(json.dumps(log[-1]),flush=True)
 (ev/'live-memory-transcript.json').write_text(json.dumps(log,indent=2)+'\n')
 return rc,out
run(['bin/fm-lab-home.sh','create',home]) # marker requires empty directory
(home/'config').mkdir(exist_ok=True)
env={'FM_HOME':str(home)}
run(['bin/fm-mem-box.sh','check'],env)
probe='import pathlib,os,json; c=pathlib.Path("/sys/fs/cgroup"+pathlib.Path("/proc/self/cgroup").read_text().split(":",2)[2].strip()); print(json.dumps({"cgroup":str(c),"max":(c/"memory.max").read_text().strip(),"swap":(c/"memory.swap.max").read_text().strip(),"override":os.getenv("FM_MEM_BOX_CAP")}))'
rc,out=run(['bin/fm-mem-box.sh','exec','worker','--','python3','-c',probe],env)
assert rc==0 and json.loads(out)['max']=='8589934592' and json.loads(out)['swap']=='0'
(home/'config/memory-box').write_text('worker=128M\ntest=64M\n')
rc,out=run(['bin/fm-mem-box.sh','exec','worker','--','bin/fm-mem-box.sh','exec','test','--','python3','-c',probe],env|{'FM_MEM_BOX_CAP':'128M'})
assert rc==0 and json.loads(out)['max']=='67108864' and json.loads(out)['override'] is None
rc,out=run(['bin/fm-mem-box.sh','exec','test','--','python3','-u','-c','import pathlib; c=pathlib.Path("/sys/fs/cgroup"+pathlib.Path("/proc/self/cgroup").read_text().split(":",2)[2].strip()); print("effective cap="+(c/"memory.max").read_text().strip()+" swap="+(c/"memory.swap.max").read_text().strip(),flush=True); a=[]\nwhile True: a.append(bytearray(1024*1024))'],env)
assert rc!=0 and 'effective cap=67108864 swap=0' in out
run(['bin/fm-mem-box.sh','exec','test','--','printf','host responsive after bounded OOM\n'],env)
rc,out=run(['bin/fm-mem-box.sh','exec','worker','--','touch',lab/'unboxed'],env|{'DBUS_SESSION_BUS_ADDRESS':'unix:path='+str(lab/'missing-bus'),'XDG_RUNTIME_DIR':str(lab/'missing-runtime')})
assert rc!=0 and not (lab/'unboxed').exists() and 'refusing' in out
run(['bin/fm-mem-protection-install.sh','install-config','--home',home,'--runner','gcp-campaign-disposable'],env)
for flags in [['--token','acceptance'],['--path','.promotion/task-data/oct04-validation/acceptance/acceptance.cjs'],['--family','live-harness-optin'],['--selection','all']]:
 rc,out=run(['bin/fm-heavy-guard.sh','check']+flags,env); assert rc==3 and 'gcp-campaign-disposable' in out
rc,out=run(['bin/fm-mem-box.sh','exec','heavy','--','touch',lab/'heavy-ran'],env); assert rc==3 and not (lab/'heavy-ran').exists()
rc,out=run(['bin/fm-test-run.sh','tests/fm-codex-hook-layer-live-e2e.test.sh'],env); assert rc==3
rc,out=run(['bin/fm-test-run.sh','--all'],env); assert rc==3
rc,out=run(['bin/fm-heavy-guard.sh','check','--token','unit'],env); assert rc==0
# Real alert, real inbox persistence and wake; only telemetry is a disposable data set.
proc=lab/'proc'; (proc/'123').mkdir(parents=True,exist_ok=True); (proc/'123/status').write_text('Name: acceptance\nVmRSS: 500000 kB\n'); (proc/'123/comm').write_text('acceptance\n')
mem=lab/'meminfo'
for avail,now in [(10000,1001),(10000,1002),(20000,1003),(10000,1004)]:
 mem.write_text(f'MemTotal: 100000 kB\nMemAvailable: {avail} kB\n')
 rc,out=run(['bin/fm-mem-alert.sh','check','--meminfo',mem,'--procfs',proc,'--now',str(now)],env); assert rc==0
run(['bin/fm-inbox.sh','receipts'],env)
notes=list((home/'state/inbox').glob('*')) if (home/'state/inbox').exists() else []
run(['bin/fm-inbox.sh','list'],env)
# Consumer compatibility: never kill host processes (dryrun).
rc,out=run(['bin/fm-mem-protection-install.sh','print','--home',home],env)
match=re.search(r'^EARLYOOM_ARGS="(.*)"$',out,re.M); args=shlex.split(match.group(1))
rc,out=run(['earlyoom','--dryrun']+args,timeout=2)
assert rc!=0
rc,out=run(['earlyoom','--dryrun']+args[:args.index('--ignore')],timeout=2)
(ev/'live-memory-transcript.json').write_text(json.dumps(log,indent=2)+'\n')
