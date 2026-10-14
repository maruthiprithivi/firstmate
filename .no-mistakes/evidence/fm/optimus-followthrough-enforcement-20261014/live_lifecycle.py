import os,pathlib,subprocess,shutil
r=pathlib.Path.cwd(); lab=r/'.test-tmp/c'; sock=r/'.test-tmp/s'; ev=pathlib.Path('/home/maruthiprithivi/.no-mistakes/evidence/01M4VZER7TSR95QQPA3ANRWA73'); log=[]
e=os.environ.copy()
for k in ['FM_GATE_REFUSE_BYPASS','FM_ROOT_OVERRIDE','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_CONFIG_OVERRIDE','FM_PROJECTS_OVERRIDE','TMUX']: e.pop(k,None)
e['FM_HOME']=str(lab)
def run(a,ok=True,env=None):
 p=subprocess.run(a,env=env or e,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
 log.append('$ '+' '.join(map(str,a))+'\n'+p.stdout+'[exit '+str(p.returncode)+']\n')
 if ok: assert p.returncode==0,p.stdout
 return p
try:
 run(['bash','bin/fm-lab-home.sh','create',str(lab)])
 run(['tmux','-S',str(sock),'new-session','-d','-s','fm-lab-actions','-n','fm-t1','bash'])
 e['TMUX']=str(sock)+',1,0'
 wt=lab/'project'; wt.mkdir(); run(['git','init','-q',str(wt)]); run(['git','-C',str(wt),'-c','user.name=lab','-c','user.email=lab@example.invalid','commit','--allow-empty','-qm','initial'])
 meta=lab/'state/t1.meta'; meta.write_text('window=fm-lab-actions:fm-t1\nendpoint_task_id=t1\nkind=ship\nharness=claude\nbackend=tmux\nworktree='+str(wt)+'\nproject='+str(wt)+'\nspawn_gen=live-1\n')
 run(['bash','bin/fm-send.sh','t1','exit'])
 # Stop the doorbell text at a shell prompt before lifecycle inspection.
 run(['tmux','-S',str(sock),'send-keys','-t','fm-lab-actions:fm-t1','C-c'])
 x=e.copy(); x.update(FM_ACTION_ID='steer-001',FM_ACTION_ATTEMPT='001.msg')
 run(['bash','bin/fm-control.sh','t1','exit'],env=x)
 receipt=lab/'state/t1.action-receipts/steer-001'; log.append('Native receipt:\n'+receipt.read_text())
 run(['bash','bin/fm-action.sh','accept','t1','steer-001','--evidence',str(receipt)])
 run(['bash','bin/fm-action.sh','show','t1'])
 meta.write_text(meta.read_text().replace('spawn_gen=live-1','spawn_gen=live-2'))
 assert run(['bash','bin/fm-action.sh','accept','t1','steer-001','--evidence',str(receipt)],False).returncode!=0
 # A secondmate's ordinary steer must retain a bindable operation.
 meta.write_text(meta.read_text().replace('kind=ship','kind=secondmate'))
 run(['bash','bin/fm-send.sh','t1','exit'])
 run(['tmux','-S',str(sock),'send-keys','-t','fm-lab-actions:fm-t1','C-c'])
 x.update(FM_ACTION_ID='steer-002',FM_ACTION_ATTEMPT='002.msg')
 result=run(['bash','bin/fm-control.sh','t1','exit'],False,env=x)
 run(['bash','bin/fm-action.sh','show','t1'])
 log.append('SECOND MATE LIFECYCLE CONTROL EXIT='+str(result.returncode)+'\n')
 # Counterfactual: change only the generated operation field to the actual verb.
 ledger=lab/'state/t1.actions'
 lines=ledger.read_text().splitlines()
 for i,line in enumerate(lines):
  fields=line.split('\t')
  if fields[2:4]==['steer-002','admit']:
   fields=['operation=exit' if f.startswith('operation=') else f for f in fields]
   lines[i]='\t'.join(fields)
 ledger.write_text('\n'.join(lines)+'\n')
 run(['bash','bin/fm-control.sh','t1','exit'],env=x)
 run(['bash','bin/fm-action.sh','show','t1'])
 log.append('Changing only the generated operation field restores native control execution.\n')

finally:
 run(['tmux','-S',str(sock),'kill-server'],False)
 (ev/'live-lifecycle-transcript.log').write_text('\n'.join(log)); shutil.rmtree(lab,ignore_errors=True); shutil.rmtree(r/'.test-tmp/retire-home',ignore_errors=True)
 if sock.exists(): sock.unlink()
