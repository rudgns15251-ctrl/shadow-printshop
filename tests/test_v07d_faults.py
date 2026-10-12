"""v0.7-D fault-injection regression suite.

All failure injection is in-memory / temporary directory and mocks.
NEVER invokes real Codex, WSL, Godot, Git mutation or a user's SQLite database.
"""
from __future__ import annotations

from contextlib import contextmanager, redirect_stdout, redirect_stderr, closing
import io
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import autopilot
import harness
import doctor_v07a
import v07b_recovery as recovery
import v07c_controller as controller


class PreflightFaults(unittest.TestCase):
    def checks(self, status='PASS'):
        return [doctor_v07a.Check(f'test {i}', status if i == 0 else 'PASS', 'injected') for i in range(8)]

    def test_wsl_failure_blocks_live_gate(self):
        with patch.object(doctor_v07a, 'preflight', return_value=self.checks('FAIL')), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'preflight stopped'):
                autopilot.enforce_v07a_preflight()

    def test_warning_blocks_live_gate(self):
        with patch.object(doctor_v07a, 'preflight', return_value=self.checks('WARN')), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'preflight stopped'):
                autopilot.enforce_v07a_preflight()

    def test_missing_diagnostic_blocks_gate(self):
        with patch.object(doctor_v07a, 'preflight', return_value=self.checks()[:7]), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'Expected 8'):
                autopilot.enforce_v07a_preflight()

    def test_sqlite_corruption_is_detected_without_rewrite(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            db = root / '.data' / 'state.sqlite3'
            db.parent.mkdir()
            db.write_bytes(b'not a sqlite database!')
            before = db.read_bytes()
            result = doctor_v07a.check_sqlite(root)
            self.assertEqual(result.status, 'FAIL')
            self.assertEqual(db.read_bytes(), before)


class LockAndRecoveryFaults(unittest.TestCase):
    def test_existing_lock_prevents_duplicate_worker(self):
        with tempfile.TemporaryDirectory() as td:
            lock = Path(td)/'autopilot.lock'
            lock.write_text('{"pid":123,"started_at":"token"}', encoding='utf-8')
            with patch.object(autopilot, 'LOCK', lock):
                with self.assertRaisesRegex(RuntimeError, 'lock exists'):
                    with autopilot.SingleWorker():
                        pass
            self.assertTrue(lock.exists())

    def test_stale_stop_request_never_stops_new_worker(self):
        with tempfile.TemporaryDirectory() as td:
            old = {'pid': 27, 'started_at': 'old'}
            current = {'pid': 27, 'started_at': 'new'}
            self.assertEqual(controller.request_stop(td, old, lambda p: True), 'REQUESTED')
            self.assertFalse(controller.is_stop_requested(td, current))
            self.assertFalse(controller.clear_own_stop(td, current))
            self.assertTrue(controller.stop_path(td).exists())

    def test_uncertain_errors_not_recoverable(self):
        for text in ('Codex timed out after 900 seconds.', 'Execution or validation failed: denied',
                     'Out-of-scope file changed: x', 'Godot regression failed'):
            with self.subTest(note=text):
                kind, eligible = recovery._category(text)
                self.assertFalse(eligible, kind)

    def test_no_automatic_apply_in_triage_and_check(self):
        assessment = recovery.Assessment('T1', 'blocked', 2, 'Codex did not change any files.',
                                         'NO_OUTPUT', True, 'eligible', '/fake')
        with (patch.object(recovery, 'assess', return_value=assessment),
              patch.object(recovery, 'recover') as mutation,
              redirect_stdout(io.StringIO())):
            self.assertEqual(recovery.main(['triage', 'T1'], root='/unimportant'), 0)
            self.assertEqual(recovery.main(['recover', 'T1', '--check'], root='/unimportant'), 0)
        mutation.assert_not_called()

    def test_blocked_recovery_refuses_unapproved_category(self):
        assessment = recovery.Assessment('T1', 'blocked', 2, 'untrusted failure',
                                         'UNCLASSIFIED', False, 'not eligible', '/fake')
        with (patch.object(recovery, 'assess', return_value=assessment),
              patch.object(recovery, 'recover') as mutation,
              redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO())):
            self.assertNotEqual(recovery.main(['recover', 'T1', '--apply'], root='/unimportant'), 0)
        mutation.assert_not_called()

    def test_report_write_is_idempotent_and_private(self):
        with tempfile.TemporaryDirectory() as td:
            report = controller.RunReport(td, max_tasks=1, minutes=5, max_retries=0,
                                          continue_after_review=False)
            report.record('TEST', 1, 'blocked', 'note', Path(td)/'private'/'run.log')
            a = report.finish('interrupted')
            self.assertEqual(report.finish('completed'), a)
            payload = json.loads(a.read_text(encoding='utf-8'))
            self.assertEqual(payload['outcome'], 'interrupted')
            self.assertEqual(payload['attempts'][0]['log'], 'run.log')
            self.assertTrue(payload['human_approval_required'])


class IsolatedExecutionFaults(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.data = self.root/'.data'/'state.sqlite3'
        self.data.parent.mkdir()
        with closing(sqlite3.connect(self.data)) as conn:
            conn.execute('CREATE TABLE tasks (id TEXT PRIMARY KEY, status TEXT, attempts INTEGER, workspace TEXT, last_note TEXT, updated TEXT)')
            conn.execute("INSERT INTO tasks(id, status, attempts) VALUES('FAULT', 'pending', 0)")
            conn.commit()
        self.task = {'id':'FAULT', 'title':'injected', 'instructions':'test', 'dependencies':[],
                     'allowed_prefixes':['projects/first-game/game/'], 'required_files':[],
                     'kind':'godot_prototype', 'auto_fix_limit':0}

    @contextmanager
    def db(self):
        with closing(sqlite3.connect(self.data)) as conn:
            with conn:
                yield conn

    def state(self):
        with closing(sqlite3.connect(self.data)) as conn:
            return conn.execute("SELECT status,attempts,workspace,last_note FROM tasks WHERE id='FAULT'").fetchone()

    def fake_git(self, *args, **kwargs):
        if args[:2] == ('worktree', 'add'):
            Path(args[3]).mkdir(parents=True, exist_ok=False)
        return Mock(returncode=0, stdout='')

    def execute_fault(self, side_effect=None, result=None):
        with (patch.object(harness, 'ROOT', self.root), patch.object(harness, 'DATA', self.data),
              patch.object(harness, 'WORKTREES', self.root/'.worktrees'),
              patch.object(harness, 'LOGS', self.root/'logs'),
              patch.object(harness, 'initialize'), patch.object(harness, 'read_tasks', return_value=[self.task]),
              patch.object(harness, 'db', self.db),
              patch.object(harness, 'require_git_base'),
              patch.object(harness.shutil, 'which', return_value='codex'),
              patch.object(harness.engine_adapter, 'locate', return_value='godot'),
              patch.object(harness, 'git', side_effect=self.fake_git),
              patch.object(harness, 'run_command', side_effect=side_effect, return_value=result),
              redirect_stdout(io.StringIO())):
            harness.execute('FAULT', True)

    def test_codex_exit_nonzero_preserves_workspace_and_attempt(self):
        self.execute_fault(result=Mock(returncode=17, stdout='injected CLI failure'))
        status, attempts, ws, note = self.state()
        self.assertEqual((status, attempts), ('blocked', 1))
        self.assertTrue(Path(ws).is_dir())
        self.assertIn('code 17', note)
        self.assertIn('injected CLI failure', (self.root/'logs'/'FAULT.jsonl.log').read_text(encoding='utf-8'))

    def test_codex_timeout_blocks_and_preserves_workspace(self):
        self.execute_fault(side_effect=subprocess.TimeoutExpired('codex', 900))
        status, attempts, ws, note = self.state()
        self.assertEqual((status, attempts), ('blocked', 1))
        self.assertTrue(Path(ws).is_dir())
        self.assertIn('timed out', note)

    def test_failed_qa_gate_does_not_mark_passed(self):
        with patch.object(harness.qa_gate, 'validate', return_value=(False, 'Harness QA regression failed')):
            passed, note = harness.check_qa_gate(self.root, {'qa_validation': True}, True, 'prior pass')
        self.assertFalse(passed)
        self.assertIn('failed', note)

    def test_failed_godot_gate_does_not_mark_passed(self):
        with patch.object(harness.engine_adapter, 'validate', return_value=(False, 'Godot smoke failed')):
            passed, note = harness.check_godot_gate(self.root, {'godot_validation': True}, True, 'prior pass')
        self.assertFalse(passed)
        self.assertIn('failed', note)


class SchedulerFaults(unittest.TestCase):
    def test_dirty_main_git_prevents_call(self):
        with (patch.object(autopilot.harness, 'require_git_base'),
              patch.object(autopilot.harness, 'git', return_value=Mock(stdout='?? unexpected.txt')),
              patch.object(autopilot, 'call_harness') as caller):
            with self.assertRaisesRegex(RuntimeError, 'not clean'):
                autopilot.run_worker(True, 1, 1, 0, 30)
        caller.assert_not_called()

    def test_stale_running_task_prevents_duplicate_execute(self):
        tasks = [{'id':'RUNNING','dependencies':[]}]
        states = {'RUNNING':{'status':'running','attempts':1,'note':''}}
        lock = {'pid': 9, 'started_at':'token'}
        with tempfile.TemporaryDirectory() as td:
            with (patch.object(autopilot, 'ROOT', Path(td)),
                  patch.object(autopilot.harness, 'require_git_base'),
                  patch.object(autopilot.harness, 'git', return_value=Mock(stdout='')),
                  patch.object(autopilot.harness.shutil, 'which', return_value='codex'),
                  patch.object(autopilot, 'SingleWorker'),
                  patch.object(autopilot, 'current_lock', return_value=lock),
                  patch.object(autopilot, 'snapshot', return_value=(tasks,states)),
                  patch.object(autopilot, 'call_harness') as caller,
                  redirect_stdout(io.StringIO())):
                autopilot.run_worker(True, 1, 1, 0, 30)
            caller.assert_not_called()

    def test_explicit_stop_prevents_first_execution(self):
        tasks = [{'id':'READY','dependencies':[]}]
        states = {'READY':{'status':'pending','attempts':0,'note':''}}
        lock = {'pid': 9, 'started_at':'token'}
        with tempfile.TemporaryDirectory() as td:
            with (patch.object(autopilot, 'ROOT', Path(td)),
                  patch.object(autopilot.harness, 'require_git_base'),
                  patch.object(autopilot.harness, 'git', return_value=Mock(stdout='')),
                  patch.object(autopilot.harness.shutil, 'which', return_value='codex'),
                  patch.object(autopilot, 'SingleWorker'),
                  patch.object(autopilot, 'current_lock', return_value=lock),
                  patch.object(autopilot, 'snapshot', return_value=(tasks,states)),
                  patch.object(controller, 'is_stop_requested', return_value=True),
                  patch.object(autopilot, 'call_harness') as caller,
                  redirect_stdout(io.StringIO())):
                autopilot.run_worker(True, 1, 1, 0, 30)
            caller.assert_not_called()

    def test_default_retry_is_zero(self):
        import argparse
        # The user-facing CLI sends retry=0 unless the caller explicitly opts in.
        with (patch.object(autopilot, 'run_worker') as worker,
              redirect_stdout(io.StringIO())):
            self.assertEqual(autopilot.main(['run','--live','--max-tasks','1']),0)
        self.assertEqual(worker.call_args.args[3], 0)


if __name__ == '__main__':
    unittest.main()
