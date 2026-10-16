"""Additional transaction faults, independent of the active real E2E run."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import engine_adapter
from test_autonomous import Coordinator, a, patch
import unittest

class Extra(Coordinator):
    # These tests extend the same fixture; load_tests below avoids duplicating its suite.
    def test_partial_copy_commit_failure_then_resume(self):
        plan = self.plan()
        run, data = a.new_run(plan['tasks'][0], self.c, self.p, plan)
        with self.providers():
            self.coder(run / 'game', run, data)
            a.qa(run / 'game', run, data, self.c, self.p, plan['tasks'][0])
            original = a.git
            def failing(*args, **kwargs):
                if args[0] == 'commit': raise a.ERROR('GIT_FAILURE: commit injected')
                return original(*args, **kwargs)
            with patch.object(a, 'git', failing), self.assertRaises(a.ERROR):
                a.integrate(run, data, plan['tasks'][0], self.c, self.p)
            self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)
            self.assertEqual(data['phase'], 'INTEGRATE')
            a.integrate(run, data, plan['tasks'][0], self.c, self.p)
        self.assertEqual(a.git('rev-list', '--count', self.base + '..HEAD'), '1')

    def test_same_failure_escalates_before_budget(self):
        plan = self.plan()
        with self.providers(process=lambda *args, **kwargs: (1, 'SCRIPT ERROR: same parser failure')):
            a.execute(plan['tasks'][0], plan, self.c, self.p)
        self.assertEqual(self.calls, 2)
        self.assertEqual(plan['tasks'][0]['status'], 'BLOCKED')

    def test_independent_next_task_after_blocked(self):
        self.plan([self.task(), self.task('second')])
        def first_bad(stage, run, data, *args, **kwargs):
            if data['task'] == 'first': raise a.ERROR('CODEX: injected nonzero')
            self.coder(stage, run, data)
        with self.providers(coder=first_bad):
            self.assertEqual(a.run_plan(self.c, self.p), 2)
        self.assertEqual([t['status'] for t in a.read(a.PLAN)['tasks']], ['BLOCKED', 'DONE'])

    def test_backup_failure_blocks_new_independent_task_on_resume(self):
        self.plan([self.task(), self.task('second')])
        with self.providers(), patch.object(a, 'remote_backup', side_effect=a.ERROR('GIT_FAILURE: push')):
            self.assertEqual(a.run_plan(self.c, self.p, push=True), 2)
            self.assertEqual(a.run_plan(self.c, self.p, recover=True, push=True), 2)
        self.assertEqual(self.calls, 1)
        self.assertEqual(a.read(a.PLAN)['tasks'][1]['status'], 'PENDING')

    def test_junction_path_escape_on_windows(self):
        import os, subprocess
        if os.name != 'nt': self.skipTest('Windows junction test')
        junction = self.game / 'escape'
        result = subprocess.run(['cmd.exe', '/c', 'mklink', '/J', str(junction), str(self.root)], capture_output=True)
        self.assertEqual(result.returncode, 0)
        try:
            with self.assertRaises(a.ERROR): a.snapshot(self.game)
            with self.assertRaises(a.ERROR): a.inside(self.game, 'escape/file')
        finally:
            junction.rmdir()

    def test_build_tampering_blocks_integration(self):
        plan = self.plan()
        run, data = a.new_run(plan['tasks'][0], self.c, self.p, plan)
        with self.providers():
            self.coder(run / 'game', run, data)
            a.qa(run / 'game', run, data, self.c, self.p, plan['tasks'][0])
            (run / 'release/fixture.pck').write_bytes(b'tampered')
            with self.assertRaises(a.ERROR): a.integrate(run, data, plan['tasks'][0], self.c, self.p)
        self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)

def load_tests(loader, tests, pattern):
    methods = [name for name in Extra.__dict__ if name.startswith('test_')]
    return unittest.TestSuite(Extra(name) for name in methods)

if __name__ == '__main__':
    unittest.main(verbosity=2)
