"""v0.7-C control tests: no real Codex, WSL, Godot or SQLite mutation."""
from __future__ import annotations
import io
from contextlib import contextmanager, redirect_stdout
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

import autopilot
import v07c_controller as ctrl


class StopRequestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.lock = {'pid': 1234, 'started_at': '2026-10-12T03:00:00+00:00'}

    def test_no_active_worker_refuses_stop(self):
        with self.assertRaisesRegex(RuntimeError, 'No verified'):
            ctrl.request_stop(self.root, None, lambda pid: False)
        self.assertFalse(ctrl.stop_path(self.root).exists())

    def test_dead_worker_refuses_stop(self):
        with self.assertRaisesRegex(RuntimeError, 'No verified'):
            ctrl.request_stop(self.root, self.lock, lambda pid: False)

    def test_stop_request_bound_to_worker_token(self):
        self.assertEqual(ctrl.request_stop(self.root, self.lock, lambda pid: True), 'REQUESTED')
        self.assertTrue(ctrl.is_stop_requested(self.root, self.lock))
        self.assertFalse(ctrl.is_stop_requested(self.root, {'pid': 1234, 'started_at': 'other'}))

    def test_duplicate_request_idempotent(self):
        ctrl.request_stop(self.root, self.lock, lambda pid: True)
        self.assertEqual(ctrl.request_stop(self.root, self.lock, lambda pid: True), 'ALREADY_REQUESTED')

    def test_stale_stop_refused_not_overwritten(self):
        ctrl.request_stop(self.root, self.lock, lambda pid: True)
        with self.assertRaisesRegex(RuntimeError, 'stale'):
            ctrl.request_stop(self.root, {'pid': 1234, 'started_at':'different'}, lambda p:True)

    def test_clear_only_own_stop(self):
        ctrl.request_stop(self.root, self.lock, lambda pid: True)
        self.assertFalse(ctrl.clear_own_stop(self.root, {'pid': 4321, 'started_at':'different'}))
        self.assertTrue(ctrl.stop_path(self.root).exists())
        self.assertTrue(ctrl.clear_own_stop(self.root, self.lock))
        self.assertFalse(ctrl.stop_path(self.root).exists())

    def test_status_is_read_only(self):
        with redirect_stdout(io.StringIO()):
            ctrl.status(self.root, None)
        self.assertFalse((self.root / 'logs').exists())
        self.assertFalse((self.root / '.data').exists())


class RunReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_report_is_atomic_and_no_raw_stdout(self):
        report = ctrl.RunReport(self.root, max_tasks=2, minutes=45, max_retries=0,
                                continue_after_review=False)
        report.record('T-001', 0, 'review', 'passed', self.root/'logs'/'fake.log')
        path=report.finish('completed')
        import json
        saved=json.loads(path.read_text(encoding='utf-8'))
        self.assertEqual(saved['attempts'][0]['state'], 'review')
        self.assertEqual(saved['attempts'][0]['log'],'fake.log')
        self.assertTrue(saved['human_approval_required'])
        self.assertFalse(any(p.name.startswith('.'+path.name) for p in path.parent.iterdir()))

    def test_report_finish_idempotent(self):
        report=ctrl.RunReport(self.root, max_tasks=1, minutes=1, max_retries=0,
                              continue_after_review=False)
        a=report.finish('completed')
        b=report.finish('ignored')
        self.assertEqual(a,b)


class CLIIntegrationTests(unittest.TestCase):
    def test_controller_status_does_not_call_codex(self):
        with patch.object(ctrl, 'status') as status, patch.object(autopilot, 'current_lock', return_value=None):
            self.assertEqual(autopilot.main(['controller-status']),0)
        status.assert_called_once_with(autopilot.ROOT, None)

    def test_stop_requires_real_worker(self):
        with patch.object(autopilot, 'current_lock',return_value=None):
            with redirect_stdout(io.StringIO()):
                self.assertEqual(autopilot.main(['stop']),1)

    def test_stop_cli_delegates(self):
        with (patch.object(ctrl, 'request_stop',return_value='REQUESTED') as fn,
              patch.object(autopilot,'current_lock',return_value={'pid':44}),
              redirect_stdout(io.StringIO())):
            self.assertEqual(autopilot.main(['stop']),0)
        self.assertEqual(fn.call_args.args[0],autopilot.ROOT)

    def test_default_stops_at_human_review(self):
        self._run_fake_worker(expect=1, continue_after_review=False)

    def test_opt_in_allows_additional_independent_tasks(self):
        self._run_fake_worker(expect=2, continue_after_review=True)

    def test_stop_request_prevents_second_task(self):
        self._run_fake_worker(expect=1, continue_after_review=True, stop_after_first=True)

    def _run_fake_worker(self, expect, continue_after_review, stop_after_first=False):
        tasks=[{'id':'T1','dependencies':[]},{'id':'T2','dependencies':[]}]
        statuses={x['id']:{'status':'pending','attempts':0,'note':''} for x in tasks}
        @contextmanager
        def fake_db():
            class DB:
                def execute(self,*args):return type('Cursor',(),{'fetchone':lambda self:('review','QA passed')})()
            yield DB()
        # No actual files, external tools, task creation or DB writes.
        report=Mock()
        events=iter([False, True] if stop_after_first else [False]*5)
        def stop_probe(*a):return next(events,False)
        with (patch.object(autopilot.harness,'require_git_base'),
              patch.object(autopilot.harness,'git',return_value=type('R',(),{'stdout':''})()),
              patch.object(autopilot.harness.shutil,'which',return_value='codex'),
              patch.object(autopilot,'SingleWorker'),
              patch.object(autopilot,'current_lock',return_value={'pid':11,'started_at':'now'}),
              patch.object(autopilot,'snapshot',return_value=(tasks,statuses)),
              patch.object(autopilot,'ready_tasks',side_effect=lambda t,s:t),
              patch.object(autopilot,'enforce_v07a_preflight'),
              patch.object(autopilot.harness,'db',side_effect=fake_db),
              patch.object(autopilot,'call_harness',return_value=(0,Path('logs/fake.log'))) as call,
              patch.object(ctrl,'stop_path',return_value=Path('/impossible-v07c-no-stop')), 
              patch.object(ctrl,'is_stop_requested',side_effect=stop_probe),
              patch.object(ctrl,'RunReport',return_value=report),
              patch.object(ctrl,'clear_own_stop'),
              redirect_stdout(io.StringIO())):
            autopilot.run_worker(True,2,45,0,900,continue_after_review=continue_after_review)
        self.assertEqual(call.call_count,expect)
        self.assertEqual(report.record.call_count,expect)
        report.finish.assert_called_once()


if __name__=='__main__':unittest.main()
