import os, pathlib, subprocess, time
root=pathlib.Path.cwd()
lab=pathlib.Path((root/'.test-tmp/live-lab-path').read_text().strip())
env=os.environ.copy()
for k in ['FM_ROOT_OVERRIDE','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_CONFIG_OVERRIDE','FM_PROJECTS_OVERRIDE','FM_GATE_REFUSE_BYPASS']:
    env.pop(k,None)
env['FM_HOME']=str(lab)
log=open('/home/maruthiprithivi/.no-mistakes/evidence/01M4VZER7TSR95QQPA3ANRWA73/live-actions.log','w')
def act(*args,ok=True):
    p=subprocess.run([str(root/'bin/fm-action.sh'),*map(str,args)],env=env,text=True,capture_output=True,timeout=8)
    print('$ fm-action.sh '+' '.join(map(str,args)),file=log)
    print(p.stdout+p.stderr+'exit='+str(p.returncode),file=log,flush=True)
    assert (p.returncode==0)==ok, args
    return p.stdout

def admit(task,id,**kw):
    args=['admit',task,'--id',id,'--class',kw.pop('class_','authorized'),'--owner','worker','--operation',kw.pop('operation','prepare image'),'--at',100]
    if '--class' in args and args[args.index('--class')+1]=='authorized': args+=['--source','captain:one-runner']
    for k,v in kw.items(): args+=['--'+k.replace('_','-'),v]
    act(*args)

admit('timing','ready')
assert act('incidents','timing','--now',399)==''
assert 'unacked-unstarted' in act('incidents','timing','--now',401)
act('ack','timing','ready','--at',402)
assert 'acked-unexecuted' in act('incidents','timing','--now',403)
act('hold','timing','ready','--kind','resource-wait','--until',900,'--reason','runner offline','--at',404)
assert act('incidents','timing','--now',899)==''
assert 'acked-unexecuted' in act('incidents','timing','--now',901)
act('start','timing','ready','--at',902)
assert act('incidents','timing','--now',10000)==''
admit('timing','refusal')
act('result','timing','refusal','refused','--reason','runner unreachable','--at',110)
assert act('incidents','timing','--now',10000)==''
act('hold','timing','ready','--kind','resource-wait','--reason','no deadline',ok=False)
for cls in ['human-decision','external-gate']:
    admit(cls,'gate',class_=cls,operation='approve export?',ready_with='ready',due=500)
    admit(cls,'ready')
    assert 'unacked-unstarted' in act('incidents',cls,'--now',401)
    for outcome in ['ok','failed','refused']:
        act('result',cls,'gate',outcome,'--reason','query unavailable','--at',450)
        assert 'gate-overdue' in act('incidents',cls,'--now',501)
    act('result',cls,'gate','answered','--at',502)
    act('start',cls,'ready','--at',503)
    assert act('incidents',cls,'--now',504)==''
act('admit','grant','--id','generic','--class','authorized','--owner','worker','--operation','runner','--source','yolo',ok=False)
admit('grant','one',units=1)
act('start','grant','one','--units',1,'--at',101)
assert act('incidents','grant','--now',102)==''
act('start','grant','one','--units',3,'--at',103)
assert 'over-grant' in act('incidents','grant','--now',104)
for command in ['respond','run']:
    admit('returns',command,operation='no-mistakes axi '+command+' --wait')
    act('start','returns',command,'--at',101)
    assert act('incidents','returns','--now',10000)==''
    act('result','returns',command,'ok','--at',10000)
    assert act('incidents','returns','--now',10299)==''
    act('ack','returns',command,'--at',10300)
    assert 'result-unconsumed' in act('incidents','returns','--now',10301)
    act('consume','returns',command,'--reason','read and reported returned gate','--at',10302)
    assert act('incidents','returns','--now',20000)==''
for name in ['receipt.json','missing/receipt.json']:
    assert act('probe',name)=='absent\n'
    act('accept','timing','ready','--evidence',name,ok=False)
locked=lab/'locked'; locked.mkdir(); (locked/'receipt').touch(); locked.chmod(0)
try:
    assert 'unknown reason=permission-denied' in act('probe',locked/'receipt')
    act('accept','timing','ready','--evidence',locked/'receipt',ok=False)
finally: locked.chmod(0o700)
receipt=lab/'state/t1.action-receipts/steer-001'
original=receipt.read_text()
for index in range(1,9):
    fields=original.strip().split('\t'); fields[index]='wrong'
    receipt.write_text('\t'.join(fields)+'\n')
    act('accept','t1','steer-001','--evidence',receipt,ok=False)
receipt.write_text(original)
act('accept','t1','steer-001','--evidence',receipt)
meta=lab/'state/t1.meta'; m=meta.read_text(); meta.write_text(m.replace('spawn_gen=run-1','spawn_gen=run-2'))
act('accept','t1','steer-001','--evidence',receipt,ok=False)
meta.write_text(m)
print('All direct CLI assertions completed.',file=log)
