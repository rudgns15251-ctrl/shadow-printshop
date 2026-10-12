import json
import tempfile
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

import qa_gate
import engine_adapter
import harness

class HarnessQAIndependentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.game = self.root / engine_adapter.PROJECT_REL
        self.game.mkdir(parents=True)
        (self.game / 'project.godot').write_text('[application]\nrun/main_scene="res://main.tscn"', encoding='utf-8')
        self.old_reports = qa_gate.REPORTS
        qa_gate.REPORTS = self.root / 'reports'

    def tearDown(self):
        qa_gate.REPORTS = self.old_reports
        self.temp.cleanup()

    def test_symlinks_refused(self):
        with patch.object(Path, 'is_symlink', autospec=True, side_effect=lambda x: x.name=='game'):
            passed, _ = qa_gate.safety_scan(self.game)
        self.assertFalse(passed)

    def test_probe_marker_required(self):
        with patch.object(qa_gate.engine_adapter, 'locate', return_value='godot-mock'), \
             patch.object(qa_gate, 'run_engine', return_value=CompletedProcess([],0,'no marker')):
            passed, note = qa_gate.validate(self.root, {'id':'QA-TEST'})
        self.assertFalse(passed, note)
        self.assertTrue((qa_gate.REPORTS/'QA-TEST.json').exists())

    def test_scene_input_probe_success(self):
        calls = []
        def fake_run(cmd, cwd, timeout):
            calls.append(cmd)
            out = 'HARNESS_QA_SCENE_PASS\n' if '--script' in cmd else 'imported\n'
            return CompletedProcess(cmd,0,out)
        with patch.object(qa_gate.engine_adapter, 'locate', return_value='godot-mock'), \
             patch.object(qa_gate, 'run_engine', side_effect=fake_run):
            passed, note = qa_gate.validate(self.root, {'id':'QA-TEST'})
        self.assertTrue(passed,note)
        self.assertEqual(len(calls),2)
        self.assertTrue((qa_gate.REPORTS/'QA-TEST.json').exists())
        self.assertTrue(json.loads((qa_gate.REPORTS/'QA-TEST.json').read_text(encoding='utf-8'))['passed'])
        self.assertFalse((self.game/'tests'/'__harness_probe.gd').exists())

    def test_godot_gate_only_on_requested_task(self):
        with patch.object(harness, 'check_qa_gate', wraps=harness.check_qa_gate) as wrapped, \
             patch.object(qa_gate, 'validate', return_value=(True,'qa ok')) as run:
            self.assertEqual(harness.check_qa_gate(self.root,{'id':'PLAN-001'},True,'prior'), (True,'prior'))
            run.assert_not_called()
            self.assertEqual(harness.check_qa_gate(self.root,{'id':'PROTO-002','qa_validation':True},True,'prior'), (True,'qa ok'))
            run.assert_called_once()

    def test_regression_marker_enforced_when_requested(self):
        p = self.game / 'tests' / 'regression_test.gd'
        p.parent.mkdir(exist_ok=True)
        p.write_text('extends SceneTree\n', encoding='utf-8')
        def fake_run(cmd, cwd, timeout):
            if '--script' in cmd and 'regression_test.gd' in cmd:
                return CompletedProcess(cmd, 0, 'no marker')
            return CompletedProcess(cmd, 0, 'HARNESS_QA_SCENE_PASS\n')
        with patch.object(qa_gate.engine_adapter,'locate',return_value='godot-mock'), \
             patch.object(qa_gate,'run_engine',side_effect=fake_run):
            passed,note=qa_gate.validate(self.root, {'id':'QA-TEST','require_regression':True})
        self.assertFalse(passed)
        self.assertIn('regression marker missing',note)

    def test_auto_fix_same_worktree_until_pass(self):
        from subprocess import CompletedProcess
        task={'id':'PROTO-TEST','title':'test','kind':'godot_prototype',
              'dependencies':[], 'allowed_prefixes':['projects/first-game/game/'],
              'required_files':['projects/first-game/game/tests/regression_test.gd'],
              'godot_validation':True, 'qa_validation':True,'auto_fix_limit':2,
              'instructions':'test'}
        worktrees=self.root/'.worktrees'
        data=self.root/'.data'/'state.sqlite3'
        logs=self.root/'logs'
        calls=[]
        def git_fake(*args,cwd=None,timeout=60):
            if args[:2]==('worktree','add'):
                Path(args[3]).mkdir(parents=True,exist_ok=True)
            return CompletedProcess(args,0,'ok')
        def codex_fake(args,cwd=None,stdin=None,timeout=60):
            calls.append(stdin)
            return CompletedProcess(args,0,'codex run')
        with patch.object(harness,'DATA',data),patch.object(harness,'ROOT',self.root), \
             patch.object(harness,'LOGS',logs),patch.object(harness,'WORKTREES',worktrees), \
             patch.object(harness,'read_tasks',return_value=[task]), \
             patch.object(harness,'require_git_base'), \
             patch.object(harness,'git',side_effect=git_fake), \
             patch.object(harness.shutil,'which',return_value='codex-mock'), \
             patch.object(engine_adapter,'locate',return_value='godot-mock'), \
             patch.object(harness,'validate_workspace',return_value=(True,'allowed')), \
             patch.object(harness,'check_godot_gate',side_effect=[(False,'Godot smoke result marker missing'),(True,'ok')]), \
             patch.object(qa_gate,'validate',return_value=(True,'qa ok')), \
             patch.object(harness,'run_command',side_effect=codex_fake):
            harness.execute('PROTO-TEST',True)
            with harness.db() as conn:
                status=conn.execute('SELECT status FROM tasks WHERE id=?',('PROTO-TEST',)).fetchone()[0]
        self.assertEqual(status,'review')
        self.assertEqual(len(calls),2)
        self.assertIn('Godot smoke result marker missing',calls[1])

    def test_retry_decision_never_retries_out_of_scope(self):
        t = {'id':'TEST','kind':'godot_prototype','allowed_prefixes':['projects/first-game/game/'], 'auto_fix_limit':2}
        self.assertFalse(harness.can_auto_fix('Out-of-scope file changed: AGENTS.md', t))
        self.assertFalse(harness.can_auto_fix('Symlink not allowed: projects/first-game/game/data', t))
        self.assertFalse(harness.can_auto_fix('Unexpected Git commit in worktree.', t))
        self.assertTrue(harness.can_auto_fix('Godot smoke result marker missing', t))

if __name__ == '__main__': unittest.main()
