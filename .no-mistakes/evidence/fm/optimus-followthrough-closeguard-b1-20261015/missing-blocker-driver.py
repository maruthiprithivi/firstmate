import os,pathlib,subprocess,shlex
root=pathlib.Path.cwd(); home=root/'.validation-tmp/manual/home'; file=home/'data/backlog.md'
env={k:v for k,v in os.environ.items() if not k.startswith(('FM_', 'TASKS_AXI_'))}; env['FM_HOME']=str(home)
w=str(root/'bin/fm-tasks-axi.sh')
def run(*args):
 p=subprocess.run([w,*args],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 print('$ fm-tasks-axi.sh '+shlex.join(args)); print(p.stdout,end=''); print('exit:',p.returncode); return p
for action in ('done','close'):
 file.write_text('## In flight\n\n## Queued\n\n## Done\n')
 for args in [('add','parent','objective'),('add','child','implementation'),('block','parent','--by','child')]:
  assert run(*args).returncode==0
 print('Simulate a missing/unreadable child by deleting only its persisted row; retain the parent dependency verbatim.')
 file.write_text(''.join(line for line in file.read_text().splitlines(True) if not line.startswith('- [ ] child - ')))
 print('Persisted backlog before closure:\n'+file.read_text())
 assert run('show','child').returncode!=0
 run('show','parent')
 p=run(action,'parent')
 print('EXPECTED: exit 2 and unchanged open parent. ACTUAL: exit '+str(p.returncode))
 run('show','parent')
 assert p.returncode==0, 'Unexpected result; review transcript'
