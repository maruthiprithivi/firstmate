import os, pathlib, subprocess, tempfile, time, json, shutil
root=pathlib.Path.cwd(); evidence=pathlib.Path('/home/maruthiprithivi/.no-mistakes/evidence/01M4X53Y2WBRAF5MX3S25PA6KS')
lab=pathlib.Path(tempfile.mkdtemp(prefix='lab-',dir=root/'.test-tmp'))
env={k:v for k,v in os.environ.items() if not (k.startswith('FM_') or k=='TMUX')}
env.update(FM_HOME=str(lab),TMPDIR=str(root/'.test-tmp'),TMUX_TMPDIR=str(lab/'tmux'),TMUX=str(lab/'tmux/socket')+',0,0',FM_ACTION_TRIAGE_SECS='1',FM_ACTION_ESCALATE_SECS='2',FM_CHECK_INTERVAL='999999',FM_HEARTBEAT='999999',FM_SECONDMATE_LIVENESS_SECS='99999999',FM_POLL='1')
log=[]; results=[]
def run(script,*args,timeout=15,extra=None):
 e=env.copy();e.update(extra or {});cmd=['bash',str(root/'bin'/script),*map(str,args)]
 try:
  p=subprocess.run(cmd,env=e,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout);rc=p.returncode;out=p.stdout
 except subprocess.TimeoutExpired as x: rc=124;out=(x.stdout or b'').decode() if isinstance(x.stdout,bytes) else (x.stdout or '')
 log.append('$ '+script+' '+' '.join(map(str,args))+'\n'+out+f'[exit={rc}]\n');return rc,out
def act(*args,**kw): return run('fm-action.sh',*args,**kw)
def poll():
 [f.unlink() for f in (lab/'state').glob('.*.checkpoint-checked')]
 return run('fm-watch.sh',timeout=3)
def check(name,fn):
 try:fn();results.append(dict(name=name,result='pass'))
 except Exception as e:results.append(dict(name=name,result='fail',reason=str(e)));log.append('ASSERTION FAILURE '+repr(e))
def contains(out,text): assert text in out,(text,out)
try:
 run('fm-lab-home.sh','create',lab);(lab/'tmux').mkdir()
 s=lab/'state';now=int(time.time());(s/'t1.meta').write_text('kind=ship\nharness=claude\nspawn_gen=run-1\n');(s/'t1.status').write_text(f'working [at={now}]: first image completed\n')
 def steer():
  assert act('admit','t1','--id','second-image','--class','authorized','--owner','worker','--source','captain:live-check','--operation','prepare second image','--at',now-400)[0]==0
  contains(poll()[1],'second-image unacked-unstarted')
  assert act('ack','t1','second-image')[0]==0
  contains(act('incidents','t1')[1],'acked-unexecuted')
  assert act('start','t1','second-image')[0]==0
  assert 'second-image' not in act('incidents','t1')[1]
  assert act('result','t1','second-image','ok')[0]==0
  assert act('accept','t1','second-image','--evidence',s/'missing')[0]!=0
 check('Unrelated work and acknowledgement do not certify a steer; explicit start clears its deadline',steer)
 def boundaries():
  assert act('admit','t1','--id','blanket','--class','authorized','--owner','worker','--source','yolo','--operation','work')[0]!=0
  assert act('admit','t1','--id','held','--class','authorized','--owner','worker','--source','captain:one-run','--operation','run','--at',now-400)[0]==0
  assert act('hold','t1','held','--kind','resource-wait','--until',now+20,'--reason','runner busy')[0]==0
  assert 'held' not in act('incidents','t1')[1]
  contains(act('incidents','t1','--now',now+21)[1],'unacked-unstarted')
  assert act('admit','t1','--id','gate','--class','human-decision','--owner','captain','--operation','choose runner','--ready-with','held','--due',now-1,'--at',now-400)[0]==0
  contains(act('incidents','t1')[1],'gate-overdue')
  act('result','t1','held','refused','--reason','runner unavailable');act('result','t1','gate','answered','--reason','captain chose runner')
 check('Finite holds expire, blanket grants refuse, and pending decisions stay visible',boundaries)
 def blockers():
  for resolve in (False,True):
   # Separate native generation and newly opened keys for each case.
   gen='run-2' if resolve else 'run-1';(s/'t1.meta').write_text(f'kind=ship\nharness=claude\nspawn_gen={gen}\n')
   t=int(time.time());(s/'t1.status').write_text(f'blocked [key=A] [at={t-20}]: A\nworking [at={t-10}]: continuing\n')
   contains(poll()[1],'key=A opened');time.sleep(1.1);contains(poll()[1],'action-followthrough-triage');time.sleep(1.1);contains(poll()[1],'action-followthrough-escalate')
   with (s/'t1.status').open('a') as f:
    f.write(f'blocked [key=B] [at={t-5}]: B\nworking [at={t}]: continuing\n')
    if resolve:f.write(f'resolved [key=A] [at={t+1}]: A cleared\n')
   contains(poll()[1],'key=B opened')
   # Keep each next stage beyond the duration of a no-notification poll.
   env['FM_ACTION_TRIAGE_SECS']='100';env['FM_ACTION_ESCALATE_SECS']='200'
   before=(s/'.wake-queue').read_text();rc,out=poll();assert 'key=B opened' not in out;assert (s/'.wake-queue').read_text()==before
   env['FM_ACTION_TRIAGE_SECS']='1';env['FM_ACTION_ESCALATE_SECS']='2'
   contains(act('register','t1')[1],'open-decision=blocked:B')
 check('Escalated A cannot suppress new B, with A open or resolved before polling; unchanged B deduplicates',blockers)
 def waits():
  (s/'t1.status').write_text(f'waiting [key=ci] [at={now-8000}]: CI running\nresolved [key=color] [at={now-7000}]: blue\n')
  contains(act('register','t1',extra={'FM_CLASSIFY_PAUSED_VERB':'waiting'})[1],'declared-wait');assert 'MISSED' not in act('register','t1',extra={'FM_CLASSIFY_PAUSED_VERB':'waiting'})[1]
 check('Configured persistent wait survives unrelated resolution without a missed checkpoint',waits)
 def checkpoint():
  task='acheckpoint';t=int(time.time());(s/(task+'.meta')).write_text('kind=ship\nharness=claude\nspawn_gen=cp-1\n');os.utime(s/(task+'.meta'),(t-5000,t-5000));(s/(task+'.status')).write_text(f'working [at={t-5000}]: implementing\n')
  contains(act('register',task)[1],'MISSED');out=poll()[1];contains(out,'checkpoint-missed');contains(out,'cp-1')
  act('progress',task,'--reason','inspected generated product output');assert 'MISSED' not in act('register',task)[1]
  poll();assert not list(s.glob('.acheckpoint.action-incident-*'))
  (s/(task+'.meta')).write_text('kind=ship\nharness=claude\nspawn_gen=cp-2\n');os.utime(s/(task+'.meta'),(t-5000,t-5000));(s/(task+'.checkpoint-progress')).write_text(f'{t-5000}\tsupervisor:earlier output\n')
  contains(poll()[1],'cp-2');(s/(task+'.status')).write_text(f'paused [at={t}]: external wait\n')
 check('Missed checkpoint reports current generation; inspected progress clears it and a new generation reports independently',checkpoint)
 def consumption():
  t=int(time.time());act('admit','t1','--id','validation-return','--class','authorized','--owner','worker','--source','owner:validation','--operation','no-mistakes axi respond','--at',t-500)
  act('start','t1','validation-return','--at',t-450);act('result','t1','validation-return','ok','--at',t-400)
  contains(act('incidents','t1')[1],'result-unconsumed');act('consume','t1','validation-return','--reason','read returned decision');assert 'validation-return' not in act('incidents','t1')[1]
 check('A returned validation result stays overdue until its owner consumes it',consumption)
 def observer():
  env['FM_ACTION_TRIAGE_SECS']='100';env['FM_ACTION_ESCALATE_SECS']='200'
  (s/'t1.status').write_text(f'done [at={int(time.time())}]: image done\n')
  for i in (1,2):
   assert act('admit','t1','--id',f'early-{i}','--class','authorized','--owner','worker','--source','captain:lab','--operation','image','--at',int(time.time())-400)[0]==0
  for i in (1,2):
   t=int(time.time());os.utime(s/'.last-watcher-beat',(t-30,t-30));(s/'.beat-gap-seen').write_text(str(t-30))
   contains(poll()[1],f'early-{i} unacked-unstarted')
   beat=int((s/'.last-watcher-beat').stat().st_mtime);assert beat>=t;assert int((s/'.beat-gap-seen').read_text())==beat
   contains(act('register')[1],'beat=ok')
 check('Successive notification exits refresh and record the watcher beacon',observer)
finally:
 log.append('RESULTS\n'+json.dumps(results,indent=2));(evidence/'live-followthrough.txt').write_text('\n'.join(log));(evidence/'live-results.json').write_text(json.dumps(results,indent=2));shutil.rmtree(lab)
print(json.dumps(results,indent=2))
