"""Single-owner production loop over the existing, unchanged mandatory game gates.

No model can expand policy, mutate the queue, integrate itself, or mark release ready.
The foreground CLI can exit while the hidden Windows worker retains its OS lease.
"""
from __future__ import annotations
import argparse
import contextlib
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import time
import uuid
import zipfile

import autonomous as a

ROOT=a.ROOT
MANIFEST=a.HERE/'production.json'
HOME=a.STATE/'production'
STATE=HOME/'state.json'
PAUSE=HOME/'pause.json'
OWNER=HOME/'owner.json'
LEASE=HOME/'owner.lock'
BIBLES=('GAME_VISION.md','GAME_DESIGN_BIBLE.md','NARRATIVE_BIBLE.md','CHARACTER_BIBLE.md',
        'ART_STYLE_BIBLE.md','AUDIO_STYLE_BIBLE.md','CONTENT_ROADMAP.md','QUALITY_CRITERIA.md','RELEASE_CHECKLIST.md')

def read(p,default=None):return a.read(p) if p.exists() else default

@contextlib.contextmanager
def lease(path=LEASE):
    """OS ownership survives frontend exit and is released automatically on crash."""
    path.parent.mkdir(parents=True,exist_ok=True)
    f=path.open('a+b')
    if f.seek(0,2)==0:f.write(b'0');f.flush()
    f.seek(0)
    try:
        if os.name=='nt':
            import msvcrt
            msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(f.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
    except OSError:
        f.close();raise a.ERROR('DIRECTOR_ALREADY_RUNNING')
    try:yield
    finally:
        f.seek(0)
        if os.name=='nt':
            import msvcrt
            msvcrt.locking(f.fileno(),msvcrt.LK_UNLCK,1)
        else:
            import fcntl
            fcntl.flock(f.fileno(),fcntl.LOCK_UN)
        f.close()

def held():
    try:
        with lease():return False
    except a.ERROR:return True

def manifest():
    m=a.read(MANIFEST)
    a.require(m['branch'].startswith('codex/') and m['branch'] not in {'main','master'},'Protected production branch')
    ids={x['id'] for x in m['milestones']}
    a.require(len(ids)==len(m['milestones']) and all(set(x['depends_on'])<=ids for x in m['milestones']),'Invalid production graph')
    for x in m['milestones']:
        a.safe_rel(x['id'])
        a.require(set(x['probes'])<=set(a.ACCEPTANCE_PROBES),'Unknown production probe')
    visited=set()
    while len(visited)<len(ids):
        ready={x['id'] for x in m['milestones'] if set(x['depends_on'])<=visited}
        a.require(bool(ready-visited),'Cyclic production dependencies')
        visited|=ready
    return m

def checkpoint(state,phase=None):
    if phase:state['phase']=phase
    state['updated']=a.now();a.write(STATE,state)

def initial(m):
    return {'version':1,'status':'READY','phase':'DIRECTOR','manifest_sha256':a.auto.sha(MANIFEST),
            'milestones':[{'id':x['id'],'status':'PENDING'} for x in m['milestones']],
            'events':[],'last_verified_commit':None,'release_candidate_ready':False,'shutdown_executed':False}

def recoverable_item(item,state,p):
    # Only the current retained plan may repair a blocked milestone. Never
    # supersede it with a freshly generated plan or reset its attempt counter.
    if state.get('current') != item['id']:return False
    plan=read(a.PLAN,{})
    # Every task verified and backed up (e.g. after operator recovery): only the
    # milestone's packaging step remains, which run_item performs without a model.
    if (plan.get('status')=='DONE' and plan.get('tasks') and plan.get('goal')==milestone_goal(item,state)
            and all(t.get('backup',{}).get('status')=='VERIFIED' for t in plan['tasks'])):
        return True
    blocked=[t for t in plan.get('tasks',[]) if t['status']=='BLOCKED']
    return bool(blocked) and all(t.get('run') and a.recovery_decision(
        a.read(a.HERE/'runs'/t['run']/'autonomous.json'),p,t)[0] for t in blocked)

def choose(state,m,recover=False,attempted=()):
    done={x['id'] for x in state['milestones'] if x['status']=='DONE'}
    statuses={x['id']:x['status'] for x in state['milestones']}
    return next((x for x in m['milestones'] if set(x['depends_on'])<=done and
                 (statuses[x['id']] in {'PENDING','RUNNING','PAUSED'} or
                  (recover and x['id'] not in attempted and statuses[x['id']]=='BLOCKED' and recoverable_item(x,state,a.policy())))),None)

def readonly_review(run,data,task,c,p):
    stage=run/'game';before=a.snapshot(stage)
    schema=run/'product-review-schema.json'
    a.write(schema,{'type':'object','additionalProperties':False,'properties':{
        'decision':{'type':'string','enum':['accept','revise']},
        'implementation_status':{'type':'string','enum':['code_ready','blocked']},
        'narrative_editor':{'type':'array','items':{'type':'string'}},
        'design_visual_flow_technical':{'type':'array','items':{'type':'string'}},
        'blocking_issues':{'type':'array','items':{'type':'string'}},
        'human_review_pending':{'type':'array','items':{'type':'string'}}},
        'required':['decision','implementation_status','narrative_editor','design_visual_flow_technical','blocking_issues','human_review_pending']})
    bible='\n'.join('\n'+n+'\n'+(ROOT/n).read_text(encoding='utf-8') for n in BIBLES[:4])
    prompt=('Independent product and narrative editor. This is a fresh read-only review, separate from implementation. '
            'Inspect the actual changed game source, task acceptance and existing tests. Do not run Godot, write files, '
            'spawn agents, install, use network, commit or publish. Evaluate specific contradictions, dead UI, save/input '
            'regressions and concrete code defects. Keep narrative editing distinct from technical/visual/flow findings. '
            'Cite event IDs or source functions with corrections. Do not fabricate screenshots, human playtesting, listening '
            'or objective taste scores. Unknown subjective presentation belongs in human_review_pending, not a fictional pass. '
            'Executable trusted QA has already run; do not demand the restricted writer execute it again. '
            'This is an incremental production task, not a release-candidate claim. Do not block current work '
            'for explicitly later roadmap features such as chapters2/3 or new music; record those as future advisory items. '
            'Accept only if no known blocking implementation issue remains. Canonical bibles are trusted context:\n'+bible+
            '\nTASK:'+json.dumps(task,ensure_ascii=False)+'\nCHANGED FILES:'+json.dumps(data['changes'])+
            '\nTRUSTED QA:'+json.dumps(data['qa']))
    prompt += ('\nSeparately report implementation_status=code_ready only when actual code and trusted objective evidence '
               'have no known implementation blocker; otherwise blocked. Human prose quality, puzzle variety/difficulty, '
               'visual taste and listening are human_review_pending and never certified as human-approved. '
               'Do not treat their pending human judgment as proof of a code defect. Cite concrete contradictions '
               'or missing behavior as blocking_issues. A writer may have conservatively reported blocked solely for '
               'those quality judgments; preserve that response. Your independent exact-source implementation '
               'disposition cannot override an objective, permission, authentication, policy or Git blocker.\n'
               'WRITER OUTCOME:'+json.dumps((data.get('model_outcomes') or [{}])[-1],ensure_ascii=False))
    a.checkpoint(run,data,'REVIEW')
    index=len(data.get('production_reviews',[]))+1
    last=a.codex(stage,run,data,prompt,c,p,'product-review-%d'%index,True,schema)
    result=a.read(last)
    a.require(a.snapshot(stage)==before,'Read-only product reviewer modified source')
    data.setdefault('production_reviews',[]).append({'time':a.now(),'source_sha256':data['qa_source_sha256'],**result})
    a.checkpoint(run,data)
    a.require(result['decision']=='accept' and result['implementation_status']=='code_ready' and not result['blocking_issues'],
              'REVIEW FAIL: '+json.dumps(result['blocking_issues'],ensure_ascii=False))
    data['production_review_snapshot']=dict(data['validated_snapshot'])
    if a.human_review_only((data.get('model_outcomes') or [{}])[-1]):
        data['production_handoff']={'attempt':data['attempts'],'source_sha256':data['qa_source_sha256'],
            'snapshot':dict(data['validated_snapshot']),'response':last.relative_to(run).as_posix(),
            'sha256':a.auto.sha(last),'human_approval':'not_granted'}
    a.checkpoint(run,data,'VERIFIED')

def report():
    state=read(STATE,{'status':'NOT_STARTED','release_candidate_ready':False})
    owner=read(OWNER,{})
    state=dict(state,worker_running=held() and a.alive(owner.get('pid')),owner_pid=owner.get('pid'),
               pause_requested=PAUSE.exists(),workspace=str(ROOT))
    try:
        c=a.config();state['model_cli']=a.model_cli(c)
        state['model_cli_ready']=a.claude_logged_in(c) if state['model_cli']=='claude' else None
    except (a.ERROR,OSError,ValueError,KeyError):state['model_cli_ready']=False
    if state.get('status')=='RUNNING' and not state['worker_running']:state['status']='INTERRUPTED'
    plan=read(a.PLAN,{})
    if plan:
        state['current_tasks']=[]
        for task in plan.get('tasks',[]):
            row={k:task.get(k) for k in ('id','status','attempts','run','commit')}
            meta=read(a.HERE/'runs'/task['run']/'autonomous.json',{}) if task.get('run') else {}
            if meta:
                row.update(phase=meta['phase'],attempts=meta['attempts'],child_pid=meta.get('child_pid'),
                           qa_passed=sum(q['pass'] for q in meta.get('qa',[])),qa_failed=sum(not q['pass'] for q in meta.get('qa',[])))
                if meta.get('backup',{}).get('status')=='VERIFIED':state['last_verified_commit']=meta['commit']
            state['current_tasks'].append(row)
    HOME.mkdir(parents=True,exist_ok=True);a.write(HOME/'report.json',state)
    rows='\n'.join('%s : %s'%(t['id'],t['status']) for t in state.get('milestones',[]))
    ready={True:'로그인됨',False:'로그인 필요 (claude auth login)',None:'해당 없음'}.get(state.get('model_cli_ready'),'확인 불가')
    (HOME/'현황_KO.txt').write_text('음영 인쇄소 제작 상태\n'+state['status']+'\n실제 관리자 실행: '+str(state['worker_running'])+'\n모델 CLI: '+str(state.get('model_cli'))+' · '+ready+'\n'+rows+'\n마지막 검증 커밋: '+str(state.get('last_verified_commit'))+'\n최근 빌드: '+str(state.get('latest_build','없음'))+'\n사람의 플레이·청취·출시 승인은 별도입니다.\n',encoding='utf-8')
    return state

def environment():
    env=os.environ.copy();env['PYTHONIOENCODING']='utf-8';env['PYTHONUTF8']='1';env['AUTODEV_PYTHON']=sys.executable
    env['GODOT_BIN']=a.config()['godot'];env['PATH']=str(Path(sys.executable).parent)+os.pathsep+env.get('PATH','')
    for key,sub in [('APPDATA','roaming'),('LOCALAPPDATA','local'),('XDG_DATA_HOME','xdg'),('TEMP','temp'),('TMP','temp')]:
        folder=ROOT/'.data/production-userdata'/sub;folder.mkdir(parents=True,exist_ok=True);env[key]=str(folder)
    return env

def package(item,state):
    plan=a.read(a.PLAN);task=plan['tasks'][-1];run=a.HERE/'runs'/task['run'];d=a.read(run/'autonomous.json')
    release=run/'release';out=ROOT/'.data/production-builds';out.mkdir(parents=True,exist_ok=True)
    dest=out/(item['id']+'-'+d['commit'][:12]+'.zip')
    if not dest.exists():
        with zipfile.ZipFile(dest,'x',zipfile.ZIP_DEFLATED) as z:
            for name,info in d['build'].items():
                a.require(a.auto.sha(release/name)==info['sha256'],'Validated build changed')
                z.write(release/name,name)
            z.write(release/'build_manifest.json','build_manifest.json')
    state['latest_build']=str(dest.relative_to(ROOT));state['latest_build_sha256']=a.auto.sha(dest)

def certify_release(state,c):
    """Run the exact new product executable in both drivers, with fresh user data.

    This is not an engine rebuild or a human playtest. It prevents a queue/DONE flag
    from certifying the legacy scene while a different exported product is broken.
    """
    plan=a.read(a.PLAN);task=plan['tasks'][-1];run=a.HERE/'runs'/task['run'];data=a.read(run/'autonomous.json')
    a.require(all(q['pass'] for q in data['qa']) and any(q['name']=='ACCEPTANCE:release_candidate' and q['pass'] for q in data['qa']),'Release product acceptance missing')
    evidence=HOME/'release-evidence.json'
    old=read(evidence)
    if old and old.get('passed') and old.get('commit')==data['commit']:
        state['release_evidence']=str(evidence.relative_to(ROOT));return
    history=HOME/('release-'+uuid.uuid4().hex);history.mkdir()
    result={'commit':data['commit'],'passed':False,'attempts':[],'human_playtest':'not_performed','human_listening':'not_performed','shutdown_executed':False}
    exe=run/'release'/c.get('exe_name','C01_Windows_Test.exe')
    a.require(a.auto.sha(exe)==data['build'][exe.name]['sha256'],'Release binary differs from verified build')
    debug=history/'C01_Debug.exe'
    godot=a.auto.resolve_godot(None,c)
    code,text=a.process([godot,'--headless','--path',run/'game','--export-debug','Windows Desktop',debug],
                        run,data,'production-final-debug-export',360,environment())
    a.require(code==0 and not a.auto.ERRORS.search(text) and debug.is_file(),'Final debug export failed')
    a.require(a.auto.sha(debug)==c['engine_profile']['debug']['sha256'],'Final debug template identity mismatch')
    for mode,binary in [('debug',debug),('release',exe)]:
        for driver in ('WASAPI','Dummy'):
            for index in range(30):
                log=history/('%s-%s-%02d.log'%(mode,driver,index+1))
                env=environment()
                user=history/('userdata-%s-%s-%02d'%(mode,driver,index+1));user.mkdir()
                for key,sub in [('APPDATA','roaming'),('LOCALAPPDATA','local'),('XDG_DATA_HOME','xdg')]:
                    path=user/sub;path.mkdir();env[key]=str(path)
                code,text=a.process([binary,'--headless','--audio-driver',driver,'--verbose','--quit-after','90'],
                                    run,data,'production-final-%s-%s-%02d'%(mode,driver,index+1),45,env)
                log=run/data['processes'][-1]['log']
                diagnostic=bool(a.auto.ERRORS.search(text) or re.search(r'Leaked instance:|Resource still in use:',text))
                actual=('CAMPAIGN_AUDIO_DRIVER '+driver) in text
                row={'mode':mode,'driver':driver,'attempt':index+1,'exit_code':code,'passed':code==0 and not diagnostic and actual,'log':str(log.relative_to(ROOT)),'sha256':a.auto.sha(log)}
                result['attempts'].append(row);a.write(evidence,result)
                a.require(row['passed'],'Release executable/driver regression failed; retained '+str(log.relative_to(ROOT)))
    # Inspect and extract only the archive produced by this trusted coordinator.
    zipped=ROOT/state['latest_build'];fresh=history/'fresh-unzip';fresh.mkdir()
    with zipfile.ZipFile(zipped) as z:
        for name in z.namelist():
            a.require(Path(name).name==name,'Unexpected release archive path')
            z.extract(name,fresh)
    a.require(a.auto.sha(fresh/exe.name)==a.auto.sha(exe),'Unpacked executable differs')
    log=history/'fresh-graphical.log'
    fresh_env=environment()
    for key,sub in [('APPDATA','roaming'),('LOCALAPPDATA','local'),('XDG_DATA_HOME','xdg')]:
        folder=history/'fresh-userdata'/sub;folder.mkdir(parents=True,exist_ok=True);fresh_env[key]=str(folder)
    code,text=a.process([fresh/exe.name,'--audio-driver','WASAPI','--verbose','--rendering-method','gl_compatibility','--quit-after','120'],
                        run,data,'production-final-fresh-graphical',90,fresh_env)
    log=run/data['processes'][-1]['log']
    a.require(code==0 and not a.auto.ERRORS.search(text) and 'OpenGL' in text and 'CAMPAIGN_AUDIO_DRIVER WASAPI' in text,'Fresh extracted graphical release failed')
    a.require(a.git('ls-remote','--heads','origin','refs/heads/'+manifest()['branch']).split()[0]==data['commit'],'Final release backup mismatch')
    result.update(passed=True,archive=state['latest_build'],archive_sha256=state['latest_build_sha256'],fresh_graphical_log=str(log.relative_to(ROOT)))
    a.write(evidence,result);state['release_evidence']=str(evidence.relative_to(ROOT))

def milestone_goal(item,state):
    goal=item['goal']+'\nTrusted production rules: preserve all nine production bibles. Exactly '+str(item['tasks'])+' sequential small implementation tasks. '
    repair=next((x.get('release_repair') for x in state['milestones'] if x['id']==item['id']),None)
    if repair:goal+='\nConcrete final release failure to repair without relaxing criteria: '+json.dumps(repair,ensure_ascii=False)+'\n'
    goal+='Every task selects these registered probes: '+', '.join(item['probes'])+'. Keep mandatory configured probes and all core gates. '
    goal+='The qualified coordinator owns runtime QA and independent read-only product review before integration. '
    goal+='Complete static implementation reports code_ready with runtime checks in verification_pending. Human taste/listening are human_review_pending. '
    goal+='Only new metadata sidecars explicitly in the exact policy/task allowlist may be created. New GDScripts need valid unique .uid files. No agents, installs, commits, network or Godot from restricted model. '
    goal+='\nBIBLE SUMMARY:\n'+(ROOT/'NARRATIVE_BIBLE.md').read_text(encoding='utf-8')+'\n'+(ROOT/'CHARACTER_BIBLE.md').read_text(encoding='utf-8')
    return goal

def run_item(item,state,c,p):
    goal=milestone_goal(item,state)
    existing=read(a.PLAN,{})
    if any(t['status']=='BLOCKED' for t in existing.get('tasks',[])):
        a.require(existing.get('goal')==goal,'Blocked plan goal differs; explicit reconciliation required')
    if existing.get('goal')!=goal:
        checkpoint(state,'PLAN');a.goal(goal,replace_incomplete=True)
        existing=read(a.PLAN,{})
    if existing.get('status')=='SUPERSEDED' or existing.get('goal')!=goal:
        a.make_plan(c,p)
    plan=a.read(a.PLAN)
    a.require(len(plan['tasks'])==item['tasks'],'Planner task count differs from production scope')
    a.require(all(set(item['probes'])<=set(t['acceptance_probes']) for t in plan['tasks']),'Missing production acceptance probe')
    # Exact generated sidecars are a trusted planning decision, never a model policy expansion.
    refined=[]
    for task in plan['tasks']:
        if task['status']!='PENDING' or task.get('run'):continue
        for rel in list(task['allowed']):
            if not (a.source(c)/rel).exists():
                suffix='.uid' if rel.endswith('.gd') else ('.import' if rel.endswith(('.svg','.wav')) else None)
                if suffix and rel+suffix in p['approved_game_files'] and rel+suffix not in task['allowed']:
                    task['allowed'].append(rel+suffix);refined.append({'task':task['id'],'new_metadata':rel+suffix})
    if refined:
        plan.setdefault('trusted_metadata_planning',[]).append({'time':a.now(),'decisions':refined})
        a.write(a.PLAN,plan)
    if plan['status']!='DONE':
        checkpoint(state,'IMPLEMENT_VALIDATE_REVIEW')
        recover=any(t['status'] in {'RUNNING','PAUSED','BLOCKED'} for t in plan['tasks'])
        a.run_plan(c,p,recover=recover,push=True)
    plan=a.read(a.PLAN)
    if PAUSE.exists() or a.PAUSE.exists():return 'PAUSED'
    if plan['status']!='DONE':
        blocked=[t for t in plan['tasks'] if t['status']=='BLOCKED']
        details=[a.read(a.HERE/'runs'/t['run']/'autonomous.json') for t in blocked if t.get('run')]
        if any(d.get('failure_category') in a.FATAL for d in details):
            raise a.ERROR('Unsafe failure: '+json.dumps([d.get('failure_category') for d in details])+'; checkpoint preserved')
        if any(d['phase'] in {'INTEGRATE','COMMITTED','BACKUP'} for d in details):raise a.ERROR('Uncertain integration/backup; no next job')
        return 'BLOCKED'
    a.require(all(t.get('backup',{}).get('status')=='VERIFIED' for t in plan['tasks']),'Missing verified development backup')
    state['last_verified_commit']=a.git('rev-parse','HEAD');package(item,state)
    return 'DONE'

def worker(max_milestones=None,recover_blocked=False):
    with lease():
        a.write(OWNER,{'pid':os.getpid(),'token':uuid.uuid4().hex,'started':a.now()})
        m=manifest();state=read(STATE,initial(m))
        a.require(state['manifest_sha256']==a.auto.sha(MANIFEST),'Production manifest changed; explicit state reconciliation required')
        a.require(a.branch_ok(a.policy())==m['branch'],'Production branch mismatch')
        a.require(a.git('rev-parse',m['stable_branch'])==m['stable_commit'],'Stable branch changed')
        a.clean();c,p=a.config(),a.policy();a.handoff_enabled(c)
        a.TASK_REVIEWER=readonly_review
        if PAUSE.exists():PAUSE.rename(HOME/('pause-handled-'+uuid.uuid4().hex+'.json'))
        if a.PAUSE.exists():a.PAUSE.rename(a.STATE/('pause-production-handled-'+uuid.uuid4().hex+'.json'))
        state.update(status='RUNNING',owner_pid=os.getpid());checkpoint(state,'DIRECTOR')
        completed=0;attempted=set()
        try:
            while not PAUSE.exists():
                item=choose(state,m,recover_blocked,attempted)
                if item is None:
                    all_done=all(x['status']=='DONE' for x in state['milestones'])
                    latest=read(a.PLAN,{})
                    release_verified=all_done and any('release_candidate' in t.get('acceptance_probes',[]) and t['status']=='DONE' for t in latest.get('tasks',[]))
                    if release_verified:
                        checkpoint(state,'FINAL_RELEASE_CERTIFICATION')
                        try:certify_release(state,c)
                        except (a.ERROR,OSError,subprocess.SubprocessError) as exc:
                            state['release_repairs']=state.get('release_repairs',0)+1
                            if state['release_repairs']<=m.get('max_release_repairs',2):
                                state['milestones'][-1].update(status='PENDING',release_repair={'round':state['release_repairs'],'failure':str(exc),'evidence':'production/release-evidence.json'})
                                checkpoint(state,'REPAIR_RELEASE');continue
                            state.update(status='RELEASE_BLOCKED',error=str(exc),release_candidate_ready=False);break
                    state['release_candidate_ready']=release_verified
                    state['status']='RELEASE_CANDIDATE_READY' if release_verified else ('RELEASE_REVIEW_REQUIRED' if all_done else 'BLOCKED_DEPENDENCIES')
                    break
                current=next(x for x in state['milestones'] if x['id']==item['id'])
                attempted.add(item['id'])
                current['status']='RUNNING';state['current']=item['id'];checkpoint(state,'DESIGN')
                log=HOME/(item['id']+'-'+uuid.uuid4().hex[:10]+'.log')
                with log.open('x',encoding='utf-8',buffering=1) as output,contextlib.redirect_stdout(output),contextlib.redirect_stderr(output):
                    try:result=run_item(item,state,c,p)
                    except Exception as exc:
                        current['error']=str(exc);result='BLOCKED'
                        if isinstance(exc,PermissionError) or 'AUTH_OR_USAGE' in str(exc) or 'Unsafe failure:' in str(exc) or 'integration/backup' in str(exc):raise
                current.update(status=result,log=log.relative_to(ROOT).as_posix(),updated=a.now())
                state['events'].append({'milestone':item['id'],'status':result,'time':a.now()})
                checkpoint(state,'NEXT_TASK');report()
                if result=='PAUSED':state['status']='PAUSED';break
                completed+=1
                if max_milestones is not None and completed>=max_milestones:
                    state['status']='CHECKPOINT_STOP';break
            if PAUSE.exists():state['status']='PAUSED'
        except Exception as exc:
            state.update(status='BLOCKED',error=str(exc));checkpoint(state,'BLOCKED');raise
        finally:
            checkpoint(state);a.TASK_REVIEWER=None
    report()
    return 0 if state['status'] not in {'BLOCKED','BLOCKED_DEPENDENCIES'} else 2

def start(recover=False,max_milestones=None):
    HOME.mkdir(parents=True,exist_ok=True)
    if held():return report()
    # Never clear a running child's checkpoint merely because its coordinator died.
    prior_plan=read(a.PLAN,{})
    for task in prior_plan.get('tasks',[]):
        if task.get('run'):
            meta=read(a.HERE/'runs'/task['run']/'autonomous.json',{})
            a.require(not a.alive(meta.get('child_pid')),'Previous child is still alive, including final release QA')
    if a.LOCK.exists():
        previous=a.read(a.LOCK)
        a.require(not a.alive(previous.get('pid')),'Existing autonomous coordinator is live')
        plan=read(a.PLAN,{})
        for t in plan.get('tasks',[]):
            if t.get('run'):a.require(not a.alive(a.read(a.HERE/'runs'/t['run']/'autonomous.json').get('child_pid')),'Orphan child still running')
        a.LOCK.rename(a.STATE/('worker-stale-director-'+uuid.uuid4().hex+'.json'))
    log=HOME/('worker-'+uuid.uuid4().hex+'.log')
    cmd=[sys.executable,'-X','utf8',str(Path(__file__).resolve()),'_worker']
    if recover:cmd.append('--recover-blocked')
    # Stop after N milestones so an operator can plan the next one with test-first probes.
    if max_milestones is not None:cmd+=['--max-milestones',str(int(max_milestones))]
    launched=a.now()
    with log.open('xb') as output:
        kw={'creationflags':subprocess.DETACHED_PROCESS|subprocess.CREATE_NEW_PROCESS_GROUP} if os.name=='nt' else {'start_new_session':True}
        child=subprocess.Popen(cmd,cwd=ROOT,env=environment(),stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT,**kw)
    deadline=time.monotonic()+5
    while time.monotonic()<deadline:
        owner=read(OWNER,{})
        if held() and owner.get('pid')==child.pid:return report()
        if child.poll() is not None:break
        time.sleep(0.05)
    # A worker can finish real work (e.g. packaging only) before this check. A venv
    # python.exe is a launcher, so the owner pid may be its child: also accept an
    # owner record written after this launch by a worker that exited cleanly.
    owner=read(OWNER,{})
    if child.poll()==0 and (owner.get('pid')==child.pid or str(owner.get('started',''))>=launched):return report()
    a.require(held(),'Worker failed startup; inspect '+str(log.relative_to(ROOT)))
    return report()

def operator_plan(milestone_id,tasks_file,reason):
    """Replace a milestone's plan with an operator-authored one at a safe stop.

    The prior plan is archived (never deleted) by autonomous.goal, its runs stay
    under .autodev/runs, and the tasks pass the same validator as model plans.
    A milestone is never marked DONE here: only verified integration can.
    """
    HOME.mkdir(parents=True,exist_ok=True)
    a.require(reason.strip(),'Operator replan reason required')
    with lease():
        m=manifest();state=read(STATE)
        a.require(state is not None,'No production state')
        digest=a.auto.sha(MANIFEST)
        if state['manifest_sha256']!=digest:
            # Scope/goal text may change and new milestones may be appended; existing
            # milestone identity and order stay fixed and their status is untouched.
            known=[x['id'] for x in state['milestones']];ids=[x['id'] for x in m['milestones']]
            a.require(ids[:len(known)]==known,'Milestone identity changed')
            added=ids[len(known):]
            state['milestones'].extend({'id':x,'status':'PENDING'} for x in added)
            state['events'].append({'type':'MANIFEST_RECONCILED','previous':state['manifest_sha256'],'current':digest,
                                    'added_milestones':added,'by':'claude-code-operator','reason':reason,'time':a.now()})
            state['manifest_sha256']=digest
        item=next((x for x in m['milestones'] if x['id']==milestone_id),None)
        a.require(item is not None,'Unknown milestone')
        current=next(x for x in state['milestones'] if x['id']==milestone_id)
        done={x['id'] for x in state['milestones'] if x['status']=='DONE'}
        a.require(set(item['depends_on'])<=done and current['status'] in {'PENDING','BLOCKED'},'Milestone not ready for an operator plan')
        c,p=a.config(),a.policy()
        a.require(a.branch_ok(p)==m['branch'],'Production branch mismatch');a.clean()
        old=read(a.PLAN,{})
        current.setdefault('operator_replans',[]).append({'time':a.now(),'reason':reason,'previous_plan_status':old.get('status'),
            'previous_planning_run':old.get('planning_run'),
            'previous_tasks':[{k:t.get(k) for k in ('id','status','run','attempts','last_failure')} for t in old.get('tasks',[])]})
        goal=milestone_goal(item,state)
        a.goal(goal,replace_incomplete=True)  # archives the old plan; refuses live children/partial integration
        tasks=a.validate_tasks(a.read(Path(tasks_file))['tasks'],p)
        a.require(len(tasks)==item['tasks'],'Operator task count differs from production scope')
        a.require(all(set(item['probes'])<=set(t['acceptance_probes']) for t in tasks),'Missing production acceptance probe')
        a.write(a.PLAN,{'version':1,'goal':goal,'created':a.now(),'branch':m['branch'],
                        'policy_sha256':a.auto.sha(a.HERE/'policy.json'),'tasks':tasks,
                        'planning_run':'operator-'+uuid.uuid4().hex[:10],'planner':'claude-code-operator','status':'PLANNED'})
        current['status']='PENDING';current.pop('error',None)
        state['events'].append({'milestone':milestone_id,'status':'OPERATOR_REPLAN','time':a.now()})
        state.update(status='READY',current=milestone_id);checkpoint(state,'OPERATOR_PLAN')
    return report()

def redirect(args):
    pointer=read(a.STATE/'production-home.json')
    if not pointer:return None
    target=Path(pointer['workspace']).resolve()
    a.require(target.is_relative_to((ROOT/'.data').resolve()) and target!=ROOT and (target/'.git').is_file(),'Invalid production workspace pointer')
    return subprocess.call([sys.executable,'-X','utf8',str(target/'.autodev/director.py'),*args],cwd=target)

def main(argv=None):
    argv=list(sys.argv[1:] if argv is None else argv)
    forwarded=redirect(argv)
    if forwarded is not None:return forwarded
    parser=argparse.ArgumentParser(description='음영 인쇄소 지속 제작 관리자')
    parser.add_argument('command',choices=['start','resume','recover','status','report','pause','operator-plan','_worker'])
    parser.add_argument('--max-milestones',type=int)
    parser.add_argument('--recover-blocked',action='store_true')
    parser.add_argument('--milestone');parser.add_argument('--tasks');parser.add_argument('--reason',default='')
    args=parser.parse_args(argv)
    try:
        if args.command=='_worker':return worker(args.max_milestones,args.recover_blocked)
        if args.command=='operator-plan':
            a.require(args.milestone and args.tasks,'operator-plan requires --milestone and --tasks')
            print(json.dumps(operator_plan(args.milestone,args.tasks,args.reason),ensure_ascii=False,indent=2));return 0
        if args.command in {'start','resume','recover'}:result=start(recover=args.command=='recover',max_milestones=args.max_milestones)
        elif args.command=='pause':
            a.write(PAUSE,{'time':a.now(),'mode':'cooperative; no kill or unverified integration'})
            a.write(a.PAUSE,{'requested':a.now(),'mode':'production cooperative boundary'})
            result=report()
        else:result=report()
        print(json.dumps(result,ensure_ascii=False,indent=2));return 0
    except (a.ERROR,OSError,ValueError,KeyError,subprocess.SubprocessError) as exc:
        print('PRODUCTION_STOP: '+str(exc),file=sys.stderr);return 2

if __name__=='__main__':sys.exit(main())
