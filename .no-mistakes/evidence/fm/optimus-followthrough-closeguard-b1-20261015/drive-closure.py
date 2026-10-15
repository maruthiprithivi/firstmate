import os, pathlib, tempfile, subprocess, json, shutil
root=pathlib.Path.cwd()
evidence=pathlib.Path('/sloth/firstmate-home/data/optimus-followthrough-enforcement-20261014/b1-run/nm-home/evidence/01M501HHM6S884A15792R70FS3')
base=pathlib.Path(tempfile.mkdtemp(prefix='.closure-live-',dir=root))
log=open(evidence/'live-closure.log','w')
results=[]
env=os.environ.copy()
for key in ['FM_HOME','FM_ROOT_OVERRIDE','FM_DATA_OVERRIDE','FM_STATE_OVERRIDE','FM_CONFIG_OVERRIDE','FM_PROJECTS_OVERRIDE','TASKS_AXI_FILE','TASKS_AXI_BACKEND']:
    env.pop(key,None)
def case(name):
    p=base/name
    (p/'home/data').mkdir(parents=True)
    (p/'home/.tasks.toml').write_text('backend = "markdown"\n[markdown]\npath = "data/backlog.md"\narchive = "data/done-archive.md"\ndone_keep = 10\n')
    (p/'home/data/backlog.md').write_text('## In flight\n\n## Queued\n\n## Done\n')
    return p
def w(p,*args,rc=0,relative=False):
    e=env|{'FM_HOME':'home' if relative else str(p/'home'),'FM_ROOT_OVERRIDE':str(root)}
    proc=subprocess.run([str(root/'bin/fm-tasks-axi.sh'),*args],env=e,cwd=p,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    log.write('$ fm-tasks-axi.sh '+ ' '.join(args)+ (' [FM_HOME=home]' if relative else '')+'\n'+proc.stdout+f'[exit {proc.returncode}]\n')
    log.flush()
    assert proc.returncode==rc,(args,proc.returncode,proc.stdout)
    return proc.stdout
def setup(name):
    p=case(name)
    for t in ['obj','study','impl']: w(p,'add',t,t+' row')
    for t in ['study','impl']: w(p,'block','obj','--by',t)
    return p
def check(name,fn):
    log.write('\nSCENARIO: '+name+'\n')
    try:
        fn()
        results.append({'name':name,'result':'pass','live':True})
    except Exception as ex:
        log.write('FAIL: '+repr(ex)+'\n')
        results.append({'name':name,'result':'fail','live':True,'reason':repr(ex)})
def open_children():
    for action in ['done','close']:
        p=setup('open-'+action)
        before=(p/'home/data/backlog.md').read_bytes()
        out=w(p,action,'obj',rc=2)
        assert 'study' in out and 'impl' in out
        assert (p/'home/data/backlog.md').read_bytes()==before
        w(p,'done','study')
        out=w(p,action,'obj',rc=2)
        assert 'impl' in out and 'study' not in out
        assert 'state: queued' in w(p,'show','obj')
def done_children():
    for action in ['done','close']:
        p=setup('done-'+action)
        for t in ['study','impl']: w(p,'done',t)
        w(p,action,'obj')
        assert 'state: done' in w(p,'show','obj')
def unblock():
    p=setup('unblock')
    for t in ['study','impl']: w(p,'unblock','obj','--by',t)
    w(p,'close','obj')
    assert 'state: done' in w(p,'show','obj')
def missing():
    for action in ['done','close']:
        p=setup('missing-'+action)
        w(p,'done','study')
        file=p/'home/data/backlog.md'
        file.write_text(''.join(line for line in file.read_text().splitlines(True) if not line.startswith('- [ ] impl - ')))
        w(p,'show','impl',rc=1)
        assert 'blocked-by:impl' in w(p,'show','obj')
        before=file.read_bytes()
        out=w(p,action,'obj',rc=2)
        assert 'impl' in out and 'study' not in out
        assert file.read_bytes()==before
        w(p,'unblock','obj','--by','impl')
        w(p,action,'obj')
        assert 'state: done' in w(p,'show','obj')
def parent():
    p=case('parent')
    for action in ['done','close']:
        before=(p/'home/data/backlog.md').read_bytes()
        out=w(p,action,'missing-objective',rc=2)
        assert 'blocker verification failed' in out and 'NOT_FOUND' in out
        assert (p/'home/data/backlog.md').read_bytes()==before
def relative():
    for action in ['done','close']:
        p=setup('relative-'+action)
        assert 'impl' in w(p,action,'obj',rc=2,relative=True)
        for t in ['study','impl']: w(p,action,t,relative=True)
        w(p,action,'obj',relative=True)
        assert 'state: done' in w(p,'show','obj')
def help_requests():
    p=setup('help')
    for action in ['done','close']:
        for flag in ['--help','-h']:
            e=env|{'TASKS_AXI_FILE':str(p/'home/data/backlog.md')}
            expected=subprocess.run(['tasks-axi',action,flag],env=e,cwd=p/'home',text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            before=(p/'home/data/backlog.md').read_bytes()
            out=w(p,action,flag,rc=expected.returncode)
            assert out==expected.stdout
            assert (p/'home/data/backlog.md').read_bytes()==before
            if flag=='--help': assert 'usage:' in out

def backfill():
    p=setup('backfill')
    # Invoke the lifecycle backlog transition executable interface, bypassing only
    # the public wrapper's user closure policy as real teardown does.
    e=env|{'FM_HOME':str(p/'home'),'FM_ROOT_OVERRIDE':str(root)}
    cmd=['bash','-c','. "$1/bin/fm-tasks-axi-lib.sh"; . "$1/bin/fm-backlog-transition-lib.sh"; fm_backlog_done "$2" obj --note landed; rc=$?; printf "%s\n" "$FM_BACKLOG_TRANSITION_ERROR"; exit "$rc"', 'bash',str(root),str(p/'home/data')]
    out=subprocess.run(cmd,env=e,cwd=p,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    log.write('$ fm_backlog_done <isolated data> obj --note landed\n'+out.stdout+f'[exit {out.returncode}]\n')
    assert out.returncode==0
    assert 'state: done' in w(p,'show','obj')
    assert 'state: queued' in w(p,'show','impl')
    for action in ['done','close']: w(p,action,'obj','--note','backfilled')
    assert 'backfilled' in w(p,'show','obj')
try:
    check('Open study and implementation children prevent done and close without changing the objective',open_children)
    check('Completing every child permits done and close',done_children)
    check('Explicit unblock permits closure while children remain open',unblock)
    check('A missing child remains blocking until explicitly unblocked',missing)
    check('Unreadable objective refuses closure and preserves the read diagnostic',parent)
    check('Relative FM_HOME from a different working directory addresses the same backlog',relative)
    check('Closure command help flags pass through without mutation',help_requests)
    check('Lifecycle backlog completion bypasses ordering blockers and Done backfill remains idempotent',backfill)
finally:
    shutil.rmtree(base)
    log.close()
    (evidence/'live-results.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
