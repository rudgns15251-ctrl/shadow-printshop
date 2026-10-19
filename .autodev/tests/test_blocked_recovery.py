"""Independent faults: real temporary Git, injected model/engine; no game gates weakened."""
import copy
from pathlib import Path
import unittest
from unittest.mock import patch
import test_autonomous as fixture
import test_director as production
a = fixture.a
d = production.d

class RecoveryFaults(unittest.TestCase):
    def setUp(self):
        self.f = fixture.Coordinator('runTest'); self.f.setUp()
        self.addCleanup(self.f.doCleanups)

    def test_import_crash_then_qa_failure_repairs_and_advances_task(self):
        self.f.plan([self.f.task(), self.f.task('second', ['first'])])
        imports = []; failures = []
        def engine(*args, **kw):
            name = args[3]
            if name.endswith('IMPORT'):
                imports.append(name)
                if len(imports) == 1: return 3221225477, 'engine import crash'
            if name.endswith('SMOKE') and self.f.calls == 1:
                failures.append(name); return 2, 'ASSERT FAIL: injected real behavior defect'
            return self.f.provider(*args, **kw)
        with self.f.providers(process=engine):
            self.assertEqual(a.run_plan(self.f.c,self.f.p),0)
        tasks = a.read(a.PLAN)['tasks']; self.assertEqual([t['status'] for t in tasks],['DONE','DONE'])
        data = a.read(a.HERE/'runs'/tasks[0]['run']/'autonomous.json')
        self.assertEqual([x['category'] for x in data['failures']],['ENVIRONMENT','EXPECTATION_MISMATCH'])
        self.assertEqual(tasks[0]['attempts'],2); self.assertEqual(self.f.calls,3)
        self.assertEqual(len(failures),1)

    def test_acceptance_storage_isolated_across_probes_and_revalidations(self):
        plan=self.f.plan(); task=plan['tasks'][0]
        task['acceptance_probes']=['story_archive','story_archive_extended']
        run,data=a.new_run(task,self.f.c,self.f.p,plan); paths=[]
        self.f.coder(run/'game',run,data)
        def engine(*args,**kw):
            env = args[5] if len(args)>5 else kw.get('env')
            if 'ACCEPTANCE' in args[3]:
                folder=Path(env['APPDATA']); paths.append(folder)
                target=folder/'corrupt.bak'
                self.assertFalse(target.exists()); target.write_bytes(b'preserve')
                marker = 'STORY_ARCHIVE_PASS' if args[3].endswith('-story_archive') else 'ARCHIVE_EXTENDED_PASS'
                return 0,marker
            return self.f.provider(*args,**kw)
        with self.f.providers(process=engine):
            a.qa(run/'game',run,data,self.f.c,self.f.p,task)
            a.qa(run/'game',run,data,self.f.c,self.f.p,task)
        self.assertEqual(len(set(paths)),4)
        self.assertTrue(all((p/'corrupt.bak').read_bytes()==b'preserve' for p in paths))

    def test_blocked_qa_reuses_stage_without_new_writer_or_attempt_reset(self):
        plan=self.f.plan(); task=plan['tasks'][0]
        run,data=a.new_run(task,self.f.c,self.f.p,plan)
        self.f.coder(run/'game',run,data)
        data.update(status='BLOCKED',phase='QA',attempts=1,error='ASSERT FAIL: old fixture',failure_category='ENVIRONMENT')
        task.update(status='BLOCKED',run=run.name,attempts=1)
        a.checkpoint(run,data); a.write(a.PLAN,plan)
        with self.f.providers():
            self.assertEqual(a.run_plan(self.f.c,self.f.p,recover=True),0)
        self.assertEqual(self.f.calls,1)
        self.assertEqual(a.read(run/'autonomous.json')['attempts'],1)

    def test_fatal_errors_stop_other_tasks_and_recover_never_recodes(self):
        for category,message in [('PERMISSION','PermissionError: access denied'),('AUTH_OR_USAGE','401 unauthorized'),('GIT_CONFLICT','GIT_FAILURE: corrupt index')]:
            with self.subTest(category=category):
                plan=self.f.plan([self.f.task(),self.f.task('independent')])
                calls=[]
                def reject(*args,**kw):
                    calls.append(1); raise a.ERROR(message)
                with self.f.providers(coder=reject):
                    self.assertEqual(a.run_plan(self.f.c,self.f.p),2)
                    self.assertEqual(a.run_plan(self.f.c,self.f.p,recover=True),2)
                self.assertEqual(len(calls),1)
                self.assertEqual(a.read(a.PLAN)['tasks'][1]['status'],'PENDING')
                task=a.read(a.PLAN)['tasks'][0]
                self.assertEqual(a.read(a.HERE/'runs'/task['run']/'autonomous.json')['failure_category'],category)

    def test_exhausted_recovery_refused_without_calls(self):
        data={'phase':'QA','attempts':4,'error':'ASSERT FAIL: broken'}
        self.assertFalse(a.recovery_decision(data,self.f.p)[0])
        data['attempts']=1
        for phase in ['INTEGRATE','COMMITTED','BACKUP']:
            data['phase']=phase; self.assertFalse(a.recovery_decision(data,self.f.p)[0])

    def test_source_sha_tampering_still_blocks_recovery(self):
        plan=self.f.plan(); task=plan['tasks'][0]
        run,data=a.new_run(task,self.f.c,self.f.p,plan)
        data.update(status='BLOCKED',phase='QA',attempts=1,error='ASSERT FAIL: old',source_commit='bad')
        task.update(status='BLOCKED',run=run.name); a.checkpoint(run,data)
        with self.f.providers(): a.execute(task,plan,self.f.c,self.f.p,recover=True)
        self.assertEqual(task['status'],'BLOCKED'); self.assertEqual(self.f.calls,0)
        self.assertEqual(a.git('rev-parse','HEAD'),self.f.base)

    def test_reconcile_preserves_recorded_import_bytes_after_later_failed_import(self):
        asset=self.f.game/'example.svg.import';asset.write_text('baseline')
        a.git('add','--','game/example.svg.import');a.git('commit','-qm','fixture metadata')
        plan=self.f.plan();run,data=a.new_run(plan['tasks'][0],self.f.c,self.f.p,plan)
        stage=run/'game';before=a.snapshot(stage);(stage/asset.name).write_text('trusted import')
        log=run/'import.log';log.write_text('imported then editor shutdown failed')
        record={'name':'attempt-1-IMPORT','log':log.name,'sha256':a.auto.sha(log),'exit_code':3221225477}
        data['processes']=[record];a.record_import_metadata(stage,before,data,record)
        data['qa']=[{'name':'STATIC','pass':True},{'name':'IMPORT','pass':False}]
        a.checkpoint(run,data,'QA')
        infra=a.HERE/'director.py';infra.write_text('# reviewed infrastructure')
        a.git('add','--','.autodev/director.py');a.git('commit','-qm','fixture recovery')
        a.reconcile_infrastructure(run.name,self.f.c,self.f.p)
        self.assertFalse(a.read(run/'autonomous.json')['qa'][-1]['pass'])
        log.write_text('tampered')
        with self.assertRaisesRegex(a.ERROR,'log missing or changed'):
            a.reconcile_infrastructure(run.name,self.f.c,self.f.p)

    def test_complete_director_loop_qa_fix_review_integrate_and_next_sprint(self):
        # Real worker/run_item/run_plan/execute/qa/integrate/package and temporary
        # Git. Only external planner, model, engine and remote are providers.
        home=a.STATE/'production'; home.mkdir(parents=True)
        for key,value in [('ROOT',self.f.root),('HOME',home),('STATE',home/'state.json'),
                          ('PAUSE',home/'pause.json'),('OWNER',home/'owner.json'),
                          ('LEASE',home/'owner.lock'),('MANIFEST',a.HERE/'production.json')]:
            change=patch.object(d,key,value);change.start();self.addCleanup(change.stop)
        original=d.lease
        change=patch.object(d,'lease',lambda path=None:original(path or d.LEASE));change.start();self.addCleanup(change.stop)
        for name in ['NARRATIVE_BIBLE.md','CHARACTER_BIBLE.md']:(self.f.root/name).write_text('fixture')
        ignore=self.f.root/'.gitignore';ignore.write_text(ignore.read_text()+'.data/\n')
        a.git('add','--','NARRATIVE_BIBLE.md','CHARACTER_BIBLE.md','.gitignore');a.git('commit','-qm','fixture bibles')
        m={'branch':'codex/fixture','stable_branch':'stable','stable_commit':a.git('rev-parse','HEAD'),
           'milestones':[{'id':'sprint1','depends_on':[],'tasks':1,'goal':'first','probes':[]},
                         {'id':'sprint2','depends_on':['sprint1'],'tasks':1,'goal':'second','probes':[]}]}
        a.git('branch','stable');a.write(d.MANIFEST,m)
        a.git('add','--','.autodev/production.json');a.git('commit','-qm','fixture manifest')
        starting=a.git('rev-parse','HEAD')
        planned=[];reviewed=[];faults=[]
        def planner(c,p):
            ident='one' if not planned else 'two';planned.append(ident)
            plan=self.f.plan([self.f.task(ident)])
            plan.update(goal=a.read(a.STATE/'goal.json')['text'],status='READY');a.write(a.PLAN,plan)
        def writer(stage,run,data,*args,**kw):
            self.f.coder(stage,run,data)
            data.setdefault('model_outcomes',[]).append({'status':'implemented','unverified_acceptance':[]})
        def engine(*args,**kw):
            if args[3].endswith('SMOKE') and self.f.calls==1:
                faults.append('SMOKE');return 2,'ASSERT FAIL: must fix game'
            return self.f.provider(*args,**kw)
        def reviewer(run,data,task,c,p):
            reviewed.append(task['id']);data['production_review_snapshot']=dict(data['validated_snapshot'])
        with self.f.providers(coder=writer,process=engine),patch.object(a,'make_plan',side_effect=planner),patch.object(a,'handoff_enabled'),patch.object(d,'readonly_review',side_effect=reviewer),patch.object(a,'config',return_value=self.f.c),patch.object(a,'policy',return_value=self.f.p),patch.object(a,'remote_backup',return_value={'status':'VERIFIED'}):
            code=d.worker()
            self.assertEqual(code,0,str(a.read(d.STATE))+'\n'+'\n'.join(p.read_text() for p in home.glob('*.log')))
        self.assertEqual(faults,['SMOKE']);self.assertEqual(self.f.calls,3)
        self.assertEqual(planned,['one','two']);self.assertEqual(reviewed,['one','two'])
        self.assertEqual([x['status'] for x in a.read(d.STATE)['milestones']],['DONE','DONE'])
        self.assertEqual(a.git('rev-list','--count',starting+'..HEAD'),'2')
        self.assertEqual(len(list((self.f.root/'.data/production-builds').glob('*.zip'))),2)

class DirectorRecoveryFaults(unittest.TestCase):
    def setUp(self):
        self.f=production.ProductionTests('runTest'); self.f.setUp()
        self.addCleanup(self.f.doCleanups)

    def test_recovered_sprint_automatically_selects_dependent_sprint(self):
        state=d.initial(self.f.m); state['current']='story'; state['milestones'][0]['status']='BLOCKED'
        a.write(d.STATE,state)
        run=a.HERE/'runs/retained';run.mkdir(parents=True)
        a.write(run/'autonomous.json',{'phase':'QA','attempts':1,'error':'ASSERT FAIL: fixable'})
        a.write(a.PLAN,{'tasks':[{'id':'one','status':'BLOCKED','run':run.name}]})
        calls=[]
        def implementation(item,state,c,p):calls.append(item['id']);return 'DONE'
        with patch.object(a,'branch_ok',return_value='codex/fixture'),patch.object(a,'policy',return_value={'max_fixes':3}),patch.object(a,'config',return_value={}),patch.object(a,'git',return_value='same'),patch.object(a,'clean'),patch.object(a,'handoff_enabled'),patch.object(d,'run_item',side_effect=implementation):
            self.assertEqual(d.worker(recover_blocked=True),0)
        self.assertEqual(calls,['story','art','ending'])
        self.assertTrue(all(x['status']=='DONE' for x in a.read(d.STATE)['milestones']))

    def test_unsafe_and_exhausted_blocked_sprints_are_never_selected(self):
        state=d.initial(self.f.m);state['current']='story';state['milestones'][0]['status']='BLOCKED'
        state['milestones'][1]['status']='DONE'
        run=a.HERE/'runs/retained';run.mkdir(parents=True)
        a.write(a.PLAN,{'tasks':[{'id':'one','status':'BLOCKED','run':run.name}]})
        for phase,error,attempts in [('QA','401 unauthorized',1),('QA','PermissionError: access denied',1),('BACKUP','GIT_FAILURE',1),('QA','ASSERT FAIL: fixable',4)]:
            a.write(run/'autonomous.json',{'phase':phase,'attempts':attempts,'error':error})
            with patch.object(a,'policy',return_value={'max_fixes':3}):
                self.assertIsNone(d.choose(state,self.f.m,recover=True))

if __name__=='__main__':unittest.main()
