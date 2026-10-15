import os,pathlib,subprocess
root=pathlib.Path.cwd(); home=root/'.validation-tmp/timeout/home'; (home/'data').mkdir(parents=True)
(home/'.tasks.toml').write_text('backend = "markdown"\n[markdown]\npath = "data/backlog.md"\narchive = "data/done-archive.md"\n')
os.mkfifo(home/'data/backlog.md')
env={k:v for k,v in os.environ.items() if not k.startswith(('FM_', 'TASKS_AXI_'))}; env.update(FM_HOME=str(home),FM_BACKLOG_ROW_TIMEOUT_SECS='1')
print('Disposable backlog is a FIFO with no writer: real tasks-axi read blocks, no executable substitution.')
for action in ('done','close'):
 print('$ FM_BACKLOG_ROW_TIMEOUT_SECS=1 fm-tasks-axi.sh '+action+' obj',flush=True)
 p=subprocess.run([str(root/'bin/fm-tasks-axi.sh'),action,'obj'],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=8)
 print(p.stdout); print('exit:',p.returncode)
 assert p.returncode==2 and 'exceeded its 1s backlog read bound' in p.stdout
print('Both commands refused the real timed-out CLI read.')
