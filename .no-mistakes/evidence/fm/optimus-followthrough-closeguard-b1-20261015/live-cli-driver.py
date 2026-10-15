import os, pathlib, subprocess, shlex
root=pathlib.Path.cwd(); home=root/'.validation-tmp/manual/home'; backlog=home/'data/backlog.md'
env={k:v for k,v in os.environ.items() if not k.startswith(('FM_', 'TASKS_AXI_'))}; env['FM_HOME']=str(home)
wrapper=str(root/'bin/fm-tasks-axi.sh')
def run(args, code=0):
 print('$ '+shlex.join(args),flush=True)
 p=subprocess.run(args,cwd=root,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 print(p.stdout,end=''); print('exit:',p.returncode,flush=True)
 assert p.returncode==code,(p.returncode,code)
 return p.stdout
def w(*args,code=0): return run([wrapper,*args],code)
print('SCENARIO: both closure aliases reject an open implementation and preserve state')
for action in ('done','close'):
 before=backlog.read_bytes(); out=w(action,'obj',code=2); assert 'impl' in out; assert backlog.read_bytes()==before
print('SCENARIO: missing parent fails verification and retains real CLI diagnostic')
for action in ('done','close'):
 out=w(action,'missing-objective',code=2); assert 'NOT_FOUND' in out and 'verification failed' in out
print('SCENARIO: explicit unblock permits closure while child is still open')
w('unblock','obj','--by','impl'); w('close','obj'); assert 'state: queued' in w('show','impl')
print('SCENARIO: Done objective accepts repeated link backfill despite an open edge')
w('block','obj','--by','impl')
for n in range(2):
 w('done','obj','--pr','https://github.com/example/project/pull/42')
out=w('show','obj'); assert 'state: done' in out and 'https://github.com/example/project/pull/42' in out
print('SCENARIO: lifecycle completion primitive closes landed work despite ordering blocker')
w('add','landed','landed work'); w('block','landed','--by','impl')
run(['bash','-c','. "$1/bin/fm-tasks-axi-lib.sh"; . "$1/bin/fm-backlog-transition-lib.sh"; fm_backlog_done "$2/data" landed --note "landed lifecycle completion"','_',str(root),str(home)])
out=w('show','landed'); assert 'state: done' in out; assert 'state: queued' in w('show','impl')
print('Persisted backlog:\n'+backlog.read_text())
print('All direct CLI scenarios passed.')
