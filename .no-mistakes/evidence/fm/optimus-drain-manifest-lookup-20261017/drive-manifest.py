import os, pathlib, tempfile, subprocess, time, json
root=pathlib.Path.cwd()
report=[]
with tempfile.TemporaryDirectory(prefix='live-manifest-',dir=root/'.gate-test-tmp') as temp:
    home=pathlib.Path(temp); state=home/'state'; state.mkdir(); (home/'config').mkdir(); (home/'tmux').mkdir()
    (home/'config'/'supervision-host-off').touch()
    env={k:v for k,v in os.environ.items() if not k.startswith('FM_') and k not in ('STATE','TMUX')}
    env.update(FM_HOME=str(home), FM_ROOT_OVERRIDE=str(home), FM_STATE_OVERRIDE=str(state), FM_CONFIG_OVERRIDE=str(home/'config'), FM_DATA_OVERRIDE=str(home/'data'), FM_PROJECTS_OVERRIDE=str(home/'projects'), TMUX_TMPDIR=str(home/'tmux'))
    manifest=state/'.status-presentation-cursor'
    def drain(label):
        start=time.monotonic()
        p=subprocess.run(['bash',str(root/'bin/fm-wake-drain.sh')],env=env,capture_output=True,text=True,timeout=60)
        report.append({'step':label,'rc':p.returncode,'seconds':round(time.monotonic()-start,3),'stdout':p.stdout,'stderr':p.stderr,'manifest':manifest.read_text() if manifest.exists() else None})
        assert p.returncode==0, report[-1]
        return p.stdout
    def write(task,text): (state/(task+'.status')).write_text(text)
    def append(task,text):
        with (state/(task+'.status')).open('a') as f:f.write(text)
    write('alpha','note: bootstrap\n'); drain('prime cursor via real CLI')
    append('alpha','note: answer retained\nnote: later routine note\n')
    out=drain('two unread notes surfaced'); assert 'alpha note: answer retained' in out and 'alpha note: later routine note' in out
    out=drain('repeat drain suppresses presented notes'); assert 'answer retained' not in out and 'UNREAD STATUS' not in out
    append('alpha','done: delivery verified\n'); out=drain('backstop surfaces fresh completion'); assert 'alpha done: delivery verified' in out and 'STATUS OUTCOME BACKSTOP' in out
    out=drain('backstop receipt suppresses repeat completion'); assert 'delivery verified' not in out
    (state/'alpha.status').rename(state/'alpha.rotated'); write('alpha','note: rotated file starts at zero\n')
    out=drain('rotation identity resets cursor'); assert 'alpha note: rotated file starts at zero' in out
    write('alpha','note: short\n'); out=drain('truncated file resets offset past EOF'); assert 'alpha note: short' in out
    write('1','note: numeric bootstrap\n'); write('01','note: leading-zero bootstrap\n'); drain('writer creates distinct numeric IDs')
    append('1','note: one new\n'); append('01','note: zero-one new\n'); out=drain('lookup preserves distinct numeric IDs'); assert '1 note: one new' in out and '01 note: zero-one new' in out
    good=manifest.read_text(); append('alpha','note: protected unread data\n')
    for label,mutate in [
        ('duplicate matched task',lambda rows:rows+[next(r for r in rows if r.startswith('alpha\t'))]),
        ('empty identity',lambda rows:['\t'.join([r.split('\t')[0],'']+r.split('\t')[2:]) if r.startswith('alpha\t') else r for r in rows]),
        ('empty presented offset',lambda rows:['\t'.join(r.split('\t')[:2]+['']+r.split('\t')[3:]) if r.startswith('alpha\t') else r for r in rows]),
        ('nonempty sixth field after empty fifth',lambda rows:[r+'\t\textra' if r.startswith('alpha\t') else r for r in rows]),
        ('malformed unrelated row after match',lambda rows:rows+['zz-damaged\tidentity\tnonnumeric\t0'])]:
        damaged='\n'.join(mutate(good.splitlines()))+'\n'; manifest.write_text(damaged)
        out=drain('reject '+label); assert 'protected unread data' not in out and manifest.read_text()==damaged, report[-1]
    manifest.write_text(good)
    out=drain('repair manifest recovers protected unread data'); assert 'alpha note: protected unread data' in out
    good=manifest.read_text(); manifest.write_text('\n'.join(r+'\t\t\t' for r in good.splitlines())+'\n')
    append('alpha','note: empty trailing columns accepted\n'); out=drain('accept empty trailing fields'); assert 'alpha note: empty trailing columns accepted' in out
    good=manifest.read_text(); manifest.write_text(good.rstrip('\n')); append('alpha','note: manifest final row has no newline\n')
    out=drain('accept manifest final row without newline'); assert 'alpha note: manifest final row has no newline' in out
    # Force a full real CLI lookup across 6000 irrelevant rows, without adding status files.
    good=manifest.read_text(); filler=''.join(f'filler-{i}\tweak:1:{i}\t10\t0\n' for i in range(6000))
    for trial in range(3):
        manifest.write_text(filler+good); append('alpha',f'note: large-manifest trial {trial}\n')
        out=drain(f'6000-row manifest end-to-end trial {trial}'); assert f'alpha note: large-manifest trial {trial}' in out
        good=manifest.read_text()
        if trial: assert f'alpha note: large-manifest trial {trial-1}' not in out
        rows=good.splitlines(); assert len(rows)==3 and {r.split('\t')[0] for r in rows}=={'alpha','1','01'}
    report.append({'result':'all real CLI assertions passed; disposable home removed on exit','scope':'No harness, lifecycle, shared session, installed-effect or comparative-speedup claim.'})
path=pathlib.Path('/home/maruthiprithivi/.no-mistakes/evidence/01M541Q7D6R5X06376GX6KSZH2/drain-transcript.json')
path.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'result':'pass','transcript':str(path),'drain_calls':len(report)-1}))
