import os, pathlib, subprocess, json, shutil, time
root=pathlib.Path.cwd(); ev=pathlib.Path('/home/maruthiprithivi/.no-mistakes/evidence/01M4VZER7TSR95QQPA3ANRWA73'); lab=root/'.test-tmp/live-home'
env=os.environ.copy()
for k in ['FM_GATE_REFUSE_BYPASS','FM_ROOT_OVERRIDE','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_CONFIG_OVERRIDE','FM_PROJECTS_OVERRIDE']: env.pop(k,None)
env['FM_HOME']=str(lab)
log=[]
def cmd(args,ok=True,custom=None):
 p=subprocess.run(args,cwd=root,env=custom or env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
 log.append('$ '+' '.join(map(str,args))+'\n'+p.stdout+'[exit '+str(p.returncode)+']\n')
 if ok: assert p.returncode==0,p.stdout
 return p
A=lambda *a,**kw: cmd(['bash','bin/fm-action.sh',*map(str,a)],**kw)
def admit(i,**kw):
 args=['admit','proof','--id',i,'--class',kw.pop('cls','authorized'),'--owner','worker','--operation',kw.pop('op','prepare independent work'),'--at','100']
 if '--class' in args and args[args.index('--class')+1]=='authorized': args+=['--source',kw.pop('source','captain:one-runner:2026-10-14')]
 for k,v in kw.items(): args+=['--'+k.replace('_','-'),str(v)]
 return A(*args)
try:
 cmd(['bash','bin/fm-lab-home.sh','create',str(lab)])
 admit('queued'); assert 'unacked-unstarted' in A('incidents','proof','--now',401).stdout
 A('ack','proof','queued','--at',120); assert 'acked-unexecuted' in A('incidents','proof','--now',401).stdout
 A('hold','proof','queued','--kind','resource-wait','--until',500,'--reason','runner offline','--at',130)
 assert A('incidents','proof','--now',499).stdout==''
 assert 'acked-unexecuted' in A('incidents','proof','--now',501).stdout
 A('start','proof','queued','--at',502); assert A('incidents','proof','--now',90000).stdout==''
 admit('counted',units=1); A('start','proof','counted','--units',4,'--at',110)
 assert 'over-grant' in A('incidents','proof','--now',120).stdout
 assert A('admit','proof','--id','blanket','--class','authorized','--owner','worker','--operation','run','--source','yolo',ok=False).returncode!=0
 for cls in ['human-decision','external-gate']:
  admit(cls,cls=cls,op='approve export?',ready_with='independent',due=200)
  for outcome in ['failed','refused','ok']:
   A('result','proof',cls,outcome,'--reason','query unavailable','--at',150)
   assert cls+'\t'+cls+'\tgated\tgate-overdue' in A('show','proof','--now',401).stdout
  A('result','proof',cls,'answered','--at',402)
 admit('independent'); assert 'independent\tauthorized\tqueued\tunacked-unstarted' in A('incidents','proof','--now',401).stdout
 for op in ['respond','run']:
  admit(op,op='no-mistakes axi '+op+' --wait'); A('start','proof',op,'--at',101); A('result','proof',op,'ok','--at',200)
  assert op+'\tauthorized\tresulted\tresult-unconsumed' in A('incidents','proof','--now',501).stdout
  A('ack','proof',op,'--at',502); assert 'result-unconsumed' in A('show','proof','--now',503).stdout
  A('consume','proof',op,'--reason','read and reported the returned gate','--at',504)
  assert op+'\tauthorized\tresulted\tnone' in A('show','proof','--now',1000).stdout
 for path in ['receipt.json','missing/receipt.json']:
  assert A('probe',path).stdout.strip()=='absent'
  assert A('accept','proof','queued','--evidence',path,ok=False).returncode!=0
 locked=lab/'locked'; locked.mkdir(); (locked/'receipt').touch(); locked.chmod(0)
 try: assert 'unknown reason=permission-denied' in A('probe',locked/'receipt').stdout
 finally: locked.chmod(0o700)
 # Run actual inbox intake and watcher with an unavailable private lab endpoint.
 meta=lab/'state/steered.meta'; meta.write_text('window=fm-lab-proof:worker\nendpoint_task_id=steered\nkind=secondmate\nharness=codex\nbackend=tmux\nworktree='+str(root)+'\nspawn_gen=proof-run\n')
 env['TMUX']=str(lab/'unused-socket')+',1,0'
 cmd(['bash','bin/fm-send.sh','steered','--fire-and-forget','0123456789abcdef','drain notifications'])
 inbox=lab/'state/steered.inbox'; shutil.move(str(inbox/'001.msg'),str(inbox/'handled/001.msg'))
 assert not (lab/'state/steered.actions').exists()
 cmd(['bash','bin/fm-send.sh','steered','prepare independent work'])
 shutil.move(str(inbox/'002.msg'),str(inbox/'handled/002.msg'))
 watcher='source bin/fm-watch.sh; date() { printf "2000000000\\n"; }; action_followthrough_check steered'
 cmd(['bash','-c',watcher]); queue=(lab/'state/.wake-queue').read_text(); log.append('Persisted wake queue:\n'+queue)
 assert 'acked-unexecuted' in queue
 cmd(['bash','-c',watcher]); assert (lab/'state/.wake-queue').read_text()==queue
 A('show','steered','--now',2000000000)
 log.append('ALL LIVE CLI ASSERTIONS PASSED\n')
finally:
 (ev/'live-cli-transcript.log').write_text('\n'.join(log))
 shutil.rmtree(lab,ignore_errors=True)
