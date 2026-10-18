"""Fault injection and actual OS lease tests. Not a substitute for real model/game E2E."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import director as d
import autonomous as a

class ProductionTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.here=self.root/'.autodev';self.home=self.here/'state/production'
        self.home.mkdir(parents=True)
        for module,key,value in [(d,'ROOT',self.root),(d,'HOME',self.home),(d,'STATE',self.home/'state.json'),
            (d,'PAUSE',self.home/'pause.json'),(d,'OWNER',self.home/'owner.json'),(d,'LEASE',self.home/'owner.lock'),
            (d,'MANIFEST',self.here/'production.json'),(a,'ROOT',self.root),(a,'HERE',self.here),
            (a,'STATE',self.here/'state'),(a,'PLAN',self.here/'state/plan.json'),(a,'LOCK',self.here/'state/worker.lock'),(a,'PAUSE',self.here/'state/pause.json')]:
            obj=patch.object(module,key,value);obj.start();self.addCleanup(obj.stop)
        self.addCleanup(setattr,a,'TASK_REVIEWER',None)
        # lease's explicit default must not bind the real workspace in a test.
        original=d.lease
        obj=patch.object(d,'lease',lambda path=None:original(path or d.LEASE));obj.start();self.addCleanup(obj.stop)
        self.m={'branch':'codex/fixture','stable_branch':'stable','stable_commit':'same',
                'milestones':[{'id':'story','depends_on':[],'tasks':2,'goal':'story','probes':[]},
                              {'id':'art','depends_on':[],'tasks':2,'goal':'art','probes':[]},
                              {'id':'ending','depends_on':['story'],'tasks':2,'goal':'ending','probes':[]}]}
        a.write(d.MANIFEST,self.m)

    def test_real_cross_process_lease_and_crash_release(self):
        path=self.home/'real.lock'
        code='import sys;from pathlib import Path;sys.path.insert(0,sys.argv[1]);import director;\nwith director.lease(Path(sys.argv[2])): print("OWNED")'
        with d.lease(path):
            result=subprocess.run([sys.executable,'-c',code,str(Path(d.__file__).parent),str(path)],capture_output=True,timeout=15)
            self.assertNotEqual(result.returncode,0);self.assertIn(b'DIRECTOR_ALREADY_RUNNING',result.stderr)
        result=subprocess.run([sys.executable,'-c',code,str(Path(d.__file__).parent),str(path)],capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0);self.assertIn(b'OWNED',result.stdout)

    def test_dependencies_and_independent_blocked_work(self):
        state=d.initial(self.m)
        self.assertEqual(d.choose(state,self.m)['id'],'story')
        state['milestones'][0]['status']='BLOCKED'
        self.assertEqual(d.choose(state,self.m)['id'],'art')
        state['milestones'][1]['status']='DONE';self.assertIsNone(d.choose(state,self.m))

    def test_resume_selects_paused_without_duplicate_done(self):
        state=d.initial(self.m);state['milestones'][0]['status']='DONE';state['milestones'][1]['status']='PAUSED'
        self.assertEqual(d.choose(state,self.m)['id'],'art')

    def test_atomic_windows_sharing_retry(self):
        target=self.home/'atomic.json';a.write(target,{'old':True});real=os.replace;calls=[]
        def transient(src,dst):
            calls.append(1)
            if len(calls)<3:
                err=PermissionError('sharing');err.winerror=32;raise err
            return real(src,dst)
        with patch.object(a.os,'replace',side_effect=transient),patch.object(a.time,'sleep'):
            a.write(target,{'new':True})
        self.assertEqual(a.read(target),{'new':True});self.assertEqual(len(calls),3)

    def test_atomic_permanent_error_keeps_old_and_temp(self):
        target=self.home/'atomic.json';a.write(target,{'old':True})
        err=PermissionError('permanent');err.winerror=13
        with patch.object(a.os,'replace',side_effect=err):
            with self.assertRaises(PermissionError):a.write(target,{'new':True})
        self.assertEqual(a.read(target),{'old':True});self.assertEqual(len(list(self.home.glob('atomic.json.*.tmp'))),1)

    def test_review_snapshot_cannot_be_bypassed(self):
        with patch.object(a,'TASK_REVIEWER',object()):
            with self.assertRaisesRegex(a.ERROR,'review missing or stale'):
                a.integrate(self.home,{'validated_snapshot':{'a':'new'},'production_review_snapshot':{'a':'old'}},{},{},{})

    def test_new_metadata_remains_in_actual_integration_diff(self):
        stage=self.root/'game';stage.mkdir();(stage/'new.gd').write_text('extends Node\n')
        baseline=a.snapshot(stage);(stage/'new.gd.uid').write_text('uid://b123\n')
        data={'baseline':baseline}
        a.record_import_metadata(stage,baseline,data,{'log':'import.log','sha256':'x'},['new.gd.uid'])
        task={'allowed':['new.gd','new.gd.uid']};policy={'approved_game_files':task['allowed']}
        self.assertEqual(a.run_changes(data,a.snapshot(stage),task,policy),['new.gd.uid'])
        (stage/'new.gd.uid').write_text('uid://changed\n')
        with self.assertRaises(a.ERROR):a.run_changes(data,a.snapshot(stage),task,policy)

    def test_new_metadata_cannot_expand_exact_scope(self):
        stage=self.root/'game';stage.mkdir();before=a.snapshot(stage);(stage/'unapproved.uid').write_text('uid://x')
        with self.assertRaises(a.ERROR):a.record_import_metadata(stage,before,{}, {'log':'l'}, [])

    def test_worker_continues_independent_job_after_failure(self):
        calls=[]
        def run(item,state,c,p):
            calls.append(item['id']);return 'BLOCKED' if item['id']=='story' else 'DONE'
        with patch.object(a,'branch_ok',return_value='codex/fixture'),patch.object(a,'policy',return_value={}),patch.object(a,'config',return_value={}),patch.object(a,'git',return_value='same'),patch.object(a,'clean'),patch.object(a,'handoff_enabled'),patch.object(d,'run_item',side_effect=run):
            code=d.worker()
        self.assertEqual(calls,['story','art']);self.assertEqual(code,2)
        self.assertFalse(a.read(d.STATE)['release_candidate_ready'])

    def test_auth_failure_stops_without_other_model_calls(self):
        with patch.object(a,'branch_ok',return_value='codex/fixture'),patch.object(a,'policy',return_value={}),patch.object(a,'config',return_value={}),patch.object(a,'git',return_value='same'),patch.object(a,'clean'),patch.object(a,'handoff_enabled'),patch.object(d,'run_item',side_effect=a.ERROR('AUTH_OR_USAGE: limit')) as run:
            with self.assertRaises(a.ERROR):d.worker()
        self.assertEqual(run.call_count,1);self.assertEqual(a.read(d.STATE)['status'],'BLOCKED')
        self.assertFalse(d.held())

    def test_pause_checkpoint_and_resume_does_not_lose_job(self):
        def pause(item,state,c,p):a.write(d.PAUSE,{'pause':True});return 'PAUSED'
        with patch.object(a,'branch_ok',return_value='codex/fixture'),patch.object(a,'policy',return_value={}),patch.object(a,'config',return_value={}),patch.object(a,'git',return_value='same'),patch.object(a,'clean'),patch.object(a,'handoff_enabled'),patch.object(d,'run_item',side_effect=pause):
            self.assertEqual(d.worker(),0)
        state=a.read(d.STATE);self.assertEqual(state['status'],'PAUSED');self.assertEqual(state['milestones'][0]['status'],'PAUSED')
        self.assertFalse(d.held())

    def test_stale_running_report_does_not_claim_background_worker(self):
        state=d.initial(self.m);state['status']='RUNNING';a.write(d.STATE,state)
        result=d.report();self.assertFalse(result['worker_running']);self.assertEqual(result['status'],'INTERRUPTED')

    def test_branch_allowlist_rejects_other_codex_branch(self):
        with patch.object(a,'git',return_value='codex/unapproved'):
            with self.assertRaises(a.ERROR):a.branch_ok({'development_branch_prefix':'codex/','approved_development_branches':['codex/fixture']})

    def test_cycle_is_rejected_before_model_launch(self):
        m=copy.deepcopy(self.m);m['milestones'][0]['depends_on']=['ending'];a.write(d.MANIFEST,m)
        with self.assertRaisesRegex(a.ERROR,'Cyclic'):d.manifest()

    def test_exhausted_queue_without_release_proof_is_not_ready(self):
        state=d.initial(self.m)
        for entry in state['milestones']:entry['status']='DONE'
        a.write(d.STATE,state)
        with patch.object(a,'branch_ok',return_value='codex/fixture'),patch.object(a,'policy',return_value={}),patch.object(a,'config',return_value={}),patch.object(a,'git',return_value='same'),patch.object(a,'clean'),patch.object(a,'handoff_enabled'):
            d.worker()
        saved=a.read(d.STATE);self.assertFalse(saved['release_candidate_ready']);self.assertEqual(saved['status'],'RELEASE_REVIEW_REQUIRED')

    def test_text_resource_export_is_explicit_and_refuses_unrelated_filter(self):
        stage=self.root/'.data/game';stage.mkdir(parents=True)
        preset=stage/'export_presets.cfg';preset.write_text(a.auto.PRESET,encoding='utf-8')
        templates={'debug':self.root/'debug.exe','release':self.root/'release.exe'}
        with patch.object(a.auto,'ROOT',self.root),patch.object(a.auto,'HERE',self.here),patch.object(a.auto,'profile_templates',return_value=templates),patch.object(a.auto,'resolve_godot',return_value=Path(sys.executable)):
            a.auto.make_export_preset(stage,{'engine_profile':True,'production_text_resources':True})
            self.assertIn('include_filter="*.json,*.md"',preset.read_text(encoding='utf-8'))
            preset.write_text(preset.read_text(encoding='utf-8').replace('*.json,*.md','*.secret'),encoding='utf-8')
            with self.assertRaises(a.ERROR):a.auto.make_export_preset(stage,{'engine_profile':True,'production_text_resources':True})

if __name__=='__main__':unittest.main()
