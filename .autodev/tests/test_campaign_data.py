"""Independent campaign arithmetic, scope and blocked-review recovery faults."""
import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import campaign_data as cd
import test_autonomous as fixture
a = fixture.a
ROOT = Path(__file__).resolve().parents[2]
SPECS = [('C02-01',11,0,[0],[0]), ('C02-02',7,292,[1],[4,5]),
         ('C02-03',170,388,[0,1],[1,3,6]), ('C02-04',341,216,[0],[0,1,2]),
         ('C02-05',85,147,[0,1],[0,2,5,7]), ('C03-01',448,362,[1],[4,5,6,7]),
         ('C03-02',128,110,[0],[1,3]), ('C03-03',257,453,[0,1],[0,3,4]),
         ('C03-04',511,446,[0,1],[1,2,4,6]), ('C03-05',16,408,[0,1],[0,1,3,5,7])]

def puzzles():
    original = json.loads((ROOT/'projects/first-game/game/data/mech_puzzles.json').read_text())
    rows = [dict(row, chapter=1) for row in copy.deepcopy(original)]
    for ident, start, target, masks, witness in SPECS:
        rows.append({'id': ident, 'chapter': int(ident[1:3]),
                     'start': [(start>>i)&1 for i in range(9)], 'target': [(target>>i)&1 for i in range(9)],
                     'allowed_masks': masks, 'solution': witness, 'minimum_prints': None, 'reachable_states': None})
    return rows, original

class Arithmetic(unittest.TestCase):
    def test_two_independent_complete_graphs_and_published_answers(self):
        rows, original = puzzles(); before=copy.deepcopy(rows)
        results=cd.calculate(rows,original)
        self.assertEqual([(r['minimum_prints'],r['reachable_states']) for r in results[8:]],
                         [(1,16),(2,16),(3,256),(3,16),(4,256),(4,16),(2,16),(3,256),(4,256),(5,256)])
        self.assertEqual(rows,before)
        text=json.dumps(rows,ensure_ascii=False,indent=2)
        completed=cd.completed_text(text,results); updated=json.loads(completed)
        self.assertEqual(updated[:8],before[:8])
        for old,new in zip(before[8:],updated[8:]):
            self.assertEqual({k:v for k,v in old.items() if k not in ('minimum_prints','reachable_states')},
                             {k:v for k,v in new.items() if k not in ('minimum_prints','reachable_states')})
        self.assertEqual(cd.completed_text(completed,results),completed)

    def test_physical_rotation_verifier_detects_integer_mask_corruption(self):
        rows,original=puzzles()
        with patch.object(cd,'MASKS',(10,*cd.MASKS[1:])):
            with self.assertRaisesRegex(ValueError,'rotations'): cd.calculate(rows,original)

    def test_illegal_witness_duplicate_and_changed_original_are_rejected(self):
        for kind in ['witness','duplicate','original','premature','binary']:
            rows,original=puzzles()
            if kind=='witness':rows[8]['solution']=[4]
            if kind=='duplicate':
                for key in ['start','target','allowed_masks']:rows[9][key]=copy.deepcopy(rows[8][key])
            if kind=='original':rows[0]['title']='changed'
            if kind=='premature':rows[8]['solution']=[0,0,0]
            if kind=='binary':rows[8]['start'][0]=True
            with self.subTest(kind=kind),self.assertRaises(ValueError):cd.calculate(rows,original)

class Recovery(unittest.TestCase):
    def setUp(self):
        self.f=fixture.Coordinator('runTest');self.f.setUp();self.addCleanup(self.f.doCleanups)

    def blocked(self):
        plan=self.f.plan([self.f.task(),self.f.task('next',['first'])]);task=plan['tasks'][0]
        run,data=a.new_run(task,self.f.c,self.f.p,plan);self.f.coder(run/'game',run,data)
        data.update(status='BLOCKED',attempts=2,failure_category='UNKNOWN',
                    last_failure='ACCEPTANCE_UNVERIFIED: needs concrete correction',error='UNKNOWN: bounded stop; inspect preserved failure evidence',
                    model_outcomes=[{'status':'blocked','summary':'No files changed','unverified_acceptance':['Fix the reviewed implementation defect']}],
                    production_reviews=[{'decision':'revise','source_sha256':'prior','blocking_issues':['scripts/slice_main.gd: concrete incorrect value']}])
        data['failures']=[{'detail':data['last_failure'],'fingerprint':'one','category':'UNKNOWN'}]
        task.update(status='BLOCKED',attempts=2,run=run.name)
        a.checkpoint(run,data,'REPAIR');a.write(a.PLAN,plan)
        return plan,task,run,data

    def test_file_scoped_review_repairs_blocked_writer_and_advances_dependency(self):
        plan,task,run,data=self.blocked();calls=[]
        self.f.c['task_attempt_limits']={'first':3}
        def writer(stage,where,current,prompt,*args,**kw):
            calls.append((current['task'],current['attempts'],prompt))
            self.f.coder(stage,where,current)
            a.write(where/('coder-%d-last.txt'%current['attempts']),{'status':'implemented','unverified_acceptance':[]})
        with self.f.providers(coder=writer):self.assertEqual(a.run_plan(self.f.c,self.f.p,recover=True),0)
        self.assertEqual([(t,n) for t,n,_ in calls],[('first',3),('next',1)])
        self.assertIn('concrete incorrect value',calls[0][2])
        self.assertEqual(a.read(run/'autonomous.json')['attempts'],3)
        self.assertEqual(a.read(run/'autonomous.json')['failures'],data['failures'])

    def test_review_then_blocked_writer_is_converted_to_automatic_bounded_repair(self):
        self.f.plan([self.f.task(),self.f.task('next',['first'])]);calls=[]
        self.f.c['task_attempt_limits']={'first':3}
        def writer(stage,run,data,*args,**kw):
            calls.append((data['task'],data['attempts']))
            outcome={'status':'implemented','unverified_acceptance':[]}
            if data['task']=='first' and data['attempts']==2:
                outcome={'status':'blocked','summary':'Need reviewed correction','unverified_acceptance':['Implement concrete reviewed value']}
                data.setdefault('model_outcomes',[]).append(outcome)
                a.write(run/'coder-2-last.txt',outcome)
                raise a.ERROR('ACCEPTANCE_UNVERIFIED: Implement concrete reviewed value')
            self.f.coder(stage,run,data)
            a.write(run/('coder-%d-last.txt'%data['attempts']),outcome)
        def reviewer(run,data,task,c,p):
            if task['id']=='first' and data['attempts']==1:
                data.setdefault('production_reviews',[]).append({'decision':'revise','blocking_issues':['scripts/slice_main.gd: concrete incorrect value']})
                a.checkpoint(run,data,'REVIEW');raise a.ERROR('REVIEW FAIL: scripts/slice_main.gd: concrete incorrect value')
            data['production_review_snapshot']=dict(data['validated_snapshot'])
        with self.f.providers(coder=writer),patch.object(a,'TASK_REVIEWER',reviewer):
            self.assertEqual(a.run_plan(self.f.c,self.f.p),0)
        self.assertEqual(calls,[('first',1),('first',2),('first',3),('next',1)])
        task=a.read(a.PLAN)['tasks'][0];data=a.read(a.HERE/'runs'/task['run']/'autonomous.json')
        self.assertEqual([f['category'] for f in data['failures']],['EXPECTATION_MISMATCH','REVIEW_REPAIR'])
        self.assertEqual(a.read(a.HERE/'runs'/task['run']/'coder-2-last.txt')['status'],'blocked')

    def test_unknown_without_review_unsafe_and_repeated_failures_stay_blocked(self):
        plan,task,run,data=self.blocked()
        self.assertTrue(a.recovery_decision(data,self.f.p,task)[0])
        for kind in ['no_review','outside_scope','permission','auth','git','policy','repeated']:
            candidate=copy.deepcopy(data)
            if kind=='no_review':candidate['production_reviews']=[]
            if kind=='outside_scope':candidate['production_reviews'][-1]['blocking_issues']=['tests/protected.gd: change assertion']
            if kind in ['permission','auth','git']:candidate['failure_category']={'permission':'PERMISSION','auth':'AUTH_OR_USAGE','git':'GIT_CONFLICT'}[kind]
            if kind=='policy':candidate['model_outcomes'][-1]['unverified_acceptance']=['policy violation requires expanding the allowlist']
            if kind=='repeated':candidate['failures']*=2
            with self.subTest(kind=kind):self.assertFalse(a.recovery_decision(candidate,self.f.p,task)[0])

    def test_quality_deferral_needs_fresh_independent_readiness_without_new_attempt(self):
        plan,task,run,data=self.blocked()
        quality={'status':'blocked','summary':'Implementation ready; human quality judgment pending',
                 'unverified_acceptance':['Canonical coherence against all nine bibles requires human review.',
                                          'Qualitative puzzle variety and human difficulty remain unverified.'],
                 'human_review_pending':['Actual listening']}
        data.update(model_outcomes=[quality],attempts=3)
        task['attempts']=3;self.f.c['task_attempt_limits']={'first':3}
        a.write(run/'coder-3-last.txt',quality);a.checkpoint(run,data);a.write(a.PLAN,plan)
        def reviewer(where,current,*args):
            result={'decision':'accept','implementation_status':'code_ready','blocking_issues':[],
                    'human_review_pending':['Human quality approval not granted']}
            response=where/'product-review-1-last.txt';a.write(response,result)
            current['production_review_snapshot']=dict(current['validated_snapshot'])
            current['production_handoff']={'attempt':current['attempts'],'source_sha256':current['qa_source_sha256'],
                'snapshot':dict(current['validated_snapshot']),'response':response.name,'sha256':a.auto.sha(response)}
        def no_writer(*args,**kw):self.fail('No correction attempt remains; only QA/read-only review permitted')
        with self.f.providers(coder=no_writer),patch.object(a,'handoff_enabled',return_value=True),patch.object(a,'TASK_REVIEWER',reviewer):
            self.assertEqual(a.run_plan(self.f.c,self.f.p,recover=True,limit=1),2)
        done=a.read(run/'autonomous.json')
        self.assertEqual(done['status'],'DONE');self.assertEqual(done['attempts'],3)
        self.assertEqual(a.read(run/'coder-3-last.txt'),quality)
        self.assertIn('Actual listening',done['human_review_pending'])
        self.assertEqual(a.read(a.PLAN)['tasks'][1]['status'],'PENDING')

    def test_quality_deferral_never_covers_missing_math_or_unsafe_errors(self):
        quality={'status':'blocked','summary':'Awaiting quality review',
                 'unverified_acceptance':['Canonical coherence against all nine bibles requires human review.']}
        self.assertTrue(a.human_review_only(quality))
        for objective in ['minimum_prints remains null','Unknown runtime acceptance','401 unauthorized','Git HEAD changed']:
            bad=copy.deepcopy(quality);bad['unverified_acceptance'].append(objective)
            self.assertFalse(a.human_review_only(bad))
        plan,task,run,data=self.blocked();data['model_outcomes']=[quality]
        for category in ['PERMISSION','AUTH_OR_USAGE','GIT_CONFLICT','SCOPE']:
            data['failure_category']=category
            self.assertFalse(a.recovery_decision(data,self.f.p,task)[0])
        data['failure_category']='UNKNOWN';data['failures']*=2
        self.assertFalse(a.recovery_decision(data,self.f.p,task)[0])

    def test_passing_qa_alone_cannot_dispose_of_a_quality_block(self):
        plan,task,run,data=self.blocked()
        quality={'status':'blocked','unverified_acceptance':['Qualitative puzzle variety and human difficulty remain unverified.']}
        data.update(attempts=3,model_outcomes=[quality]);a.write(run/'coder-3-last.txt',quality)
        with self.f.providers():a.qa(run/'game',run,data,self.f.c,self.f.p,task)
        with patch.object(a,'handoff_enabled',return_value=True):
            with self.assertRaisesRegex(a.ERROR,'Unresolved model acceptance blocker'):
                a.integrate(run,data,task,self.f.c,self.f.p)
        self.assertEqual(a.git('rev-parse','HEAD'),self.f.base)

    def test_campaign_metadata_requires_exact_scope_and_records_actual_results(self):
        rows,original=puzzles();folder=self.f.game/'data';folder.mkdir()
        a.write(folder/'mech_puzzles.json',original);a.write(folder/'campaign_puzzles.json',rows)
        a.git('add','--','game/data');a.git('commit','-qm','fixture campaign')
        task_spec=self.f.task();task_spec['allowed'].append('data/campaign_puzzles.json');task_spec['acceptance_probes']=['campaign_full']
        self.f.p['approved_game_files'].append('data/campaign_puzzles.json');a.write(a.HERE/'policy.json',self.f.p)
        a.git('add','--','.autodev/policy.json');a.git('commit','-qm','fixture exact scope')
        plan=self.f.plan([task_spec]);task=plan['tasks'][0];run,data=a.new_run(task,self.f.c,self.f.p,plan)
        report=a.prepare_campaign_data(run/'game',run,data,self.f.p,task)
        self.assertEqual(len(report['rows']),18)
        updated=a.read(run/'game/data/campaign_puzzles.json');self.assertEqual(updated[:8],rows[:8])
        self.assertTrue(all(type(r['minimum_prints']) is int for r in updated))
        self.assertEqual(a.read(self.f.game/'data/campaign_puzzles.json'),rows)
        self.assertTrue((run/data['campaign_bfs_history'][-1]['report']).is_file())
        # Reintroduce the failure, then remove write authority: no implicit scope expansion.
        a.write(run/'game/data/campaign_puzzles.json',rows)
        task['allowed'].remove('data/campaign_puzzles.json')
        with self.assertRaisesRegex(a.ERROR,'SCOPE'):a.prepare_campaign_data(run/'game',run,data,self.f.p,task)

if __name__=='__main__':unittest.main()
