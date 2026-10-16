"""Independent fault injection for the coordinator; real temp Git, mock providers.

These tests do not claim to execute Godot or a real model. Real engine/CLI E2E
evidence belongs in .autodev/runs and the final QA report.
"""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import autonomous as a


class Coordinator(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.here = self.root / '.autodev'
        (self.here / 'checks').mkdir(parents=True)
        (self.here / 'checks/quality_probe.gd').write_text('extends SceneTree\n')
        self.game = self.root / 'game'
        for name, text in {
            'project.godot': '[application]\n', 'main.tscn': '[gd_scene]\n',
            'scripts/game_state.gd': 'extends RefCounted\n',
            'scripts/slice_main.gd': 'extends Control\n',
            'tests/smoke_test.gd': 'extends SceneTree\n',
            'tests/regression_test.gd': 'extends SceneTree\n',
            'tests/slice_acceptance.gd': 'extends SceneTree\n',
            'tests/mech_offline.py': 'print("PASS offline cases 8000")\n',
            'saves/existing.json': '{"keep":true}'} .items():
            target = self.game / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        self.p = {'approved_game_files': ['scripts/slice_main.gd'], 'protected': ['tests/'],
                  'max_tasks': 8, 'max_fixes': 3, 'codex_timeout_seconds': 5,
                  'development_branch_prefix': 'codex/', 'remote': 'origin',
                  'remote_url': 'https://github.com/example/fixture.git'}
        a.write(self.here / 'policy.json', self.p)
        self.c = {'game_dir': 'game', 'godot': sys.executable, 'exe_name': 'fixture.exe',
                  'tests': [{'name': n, 'script': s, 'marker': m} for n, s, m in [
                      ('SMOKE', 'tests/smoke_test.gd', 'HARNESS_SMOKE_PASS'),
                      ('REGRESSION', 'tests/regression_test.gd', 'HARNESS_REGRESSION_PASS'),
                      ('SLICE', 'tests/slice_acceptance.gd', 'SLICE_ACCEPTANCE_PASS')]]}
        for obj, key, value in [(a, 'ROOT', self.root), (a, 'HERE', self.here),
                                (a, 'STATE', self.here / 'state'), (a, 'PLAN', self.here / 'state/plan.json'),
                                (a, 'LOCK', self.here / 'state/worker.lock'), (a, 'PAUSE', self.here / 'state/pause.json'),
                                (a.auto, 'ROOT', self.root), (a.auto, 'HERE', self.here)]:
            change = patch.object(obj, key, value)
            change.start()
            self.addCleanup(change.stop)
        a.git('init', '-q')
        a.git('switch', '-c', 'codex/fixture')
        a.git('config', 'user.name', 'Fixture')
        a.git('config', 'user.email', 'fixture@invalid')
        (self.root / '.gitignore').write_text('.autodev/runs/\n.autodev/state/\n')
        a.git('add', '--', 'game', '.gitignore', '.autodev/policy.json', '.autodev/checks/quality_probe.gd')
        a.git('commit', '-qm', 'baseline')
        self.base = a.git('rev-parse', 'HEAD')
        self.calls = 0

    def task(self, ident='first', deps=None):
        return {'id': ident, 'objective': 'Small real edit', 'allowed': ['scripts/slice_main.gd'],
                'risk': 'low', 'depends_on': deps or [], 'acceptance': ['Specific behavior'],
                'expected_failures': ['parse error'], 'recovery': 'Keep stage, bounded repair',
                'deliverables': ['Changed game source']}

    def plan(self, tasks=None):
        tasks = a.validate_tasks(tasks or [self.task()], self.p)
        plan = {'branch': 'codex/fixture', 'policy_sha256': a.auto.sha(self.here / 'policy.json'), 'tasks': tasks}
        a.write(a.PLAN, plan)
        return plan

    def coder(self, stage, run, data, *args, **kwargs):
        self.calls += 1
        file = stage / 'scripts/slice_main.gd'
        file.write_text(file.read_text() + '# implemented %d\n' % self.calls)

    def provider(self, cmd, run, data, name, *args, **kwargs):
        if name.endswith('EXPORT'):
            file = Path(cmd[-1])
            file.write_bytes(b'MZ' + b'0' * 150000)
            file.with_suffix('.pck').write_bytes(b'pack')
        return 0, 'HARNESS_SMOKE_PASS HARNESS_REGRESSION_PASS SLICE_ACCEPTANCE_PASS PASS offline cases AUTODEV_QUALITY_PASS Godot Engine'

    def providers(self, coder=None, process=None):
        context = contextlib_exit_stack()
        context.enter_context(patch.object(a, 'codex', coder or self.coder))
        context.enter_context(patch.object(a, 'process', process or self.provider))
        context.enter_context(patch.object(a.auto, 'check_template', return_value='fixture'))
        return context

    def test_bom_and_atomic_checkpoints(self):
        file = self.root / 'bom.json'
        file.write_bytes(b'\xef\xbb\xbf{"x":1}')
        self.assertEqual(a.read(file), {'x': 1})
        a.write(file, {'x': 2})
        self.assertEqual(a.read(file), {'x': 2})

    def test_scope_paths_and_cycles(self):
        for path in ['../x', 'C:/secret', 'scripts\\x', '/tmp/x', 'scripts/*', 'scripts/./x', 'x:stream']:
            with self.subTest(path=path), self.assertRaises(a.ERROR): a.safe_rel(path)
        task = self.task(); task['allowed'] = ['tests/smoke_test.gd']
        with self.assertRaises(a.ERROR): a.validate_tasks([task], self.p)
        with self.assertRaises(a.ERROR): a.validate_tasks([self.task('first', ['second']), self.task('second', ['first'])], self.p)

    def test_symlink_detected_before_copy(self):
        link = self.game / 'escape'
        try:
            link.symlink_to(self.root, target_is_directory=True)
        except OSError:
            self.skipTest('OS does not permit creating test symlink')
        with self.assertRaises(a.ERROR): a.snapshot(self.game)
        with self.assertRaises(a.ERROR): a.inside(self.game, 'escape/file')
        link.unlink()

    def test_existing_changes_preserved_and_rejected(self):
        file = self.game / 'scripts/slice_main.gd'; file.write_text('user change')
        with self.assertRaises(a.ERROR): a.new_run(self.plan()['tasks'][0], self.c, self.p, self.plan())
        self.assertEqual(file.read_text(), 'user change')
        self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)

    def test_duplicate_lock_and_explicit_stale_recovery(self):
        with a.locked():
            with self.assertRaises(a.ERROR):
                with a.locked(True): pass
        a.write(a.LOCK, {'pid': 2147483647, 'token': 'old'})
        with self.assertRaises(a.ERROR):
            with a.locked(): pass
        with a.locked(True): self.assertTrue(a.LOCK.exists())
        self.assertFalse(a.LOCK.exists())

    def test_two_tasks_real_git_mock_model_and_engine(self):
        plan = self.plan([self.task(), self.task('second', ['first'])])
        with self.providers():
            self.assertEqual(a.run_plan(self.c, self.p), 0)
        done = a.read(a.PLAN)
        self.assertEqual([t['status'] for t in done['tasks']], ['DONE', 'DONE'])
        self.assertEqual(self.calls, 2)
        self.assertEqual(a.git('rev-list', '--count', self.base + '..HEAD'), '2')
        self.assertEqual((self.game / 'saves/existing.json').read_text(), '{"keep":true}')
        self.assertFalse((self.game / 'autodev_quality_probe.gd').exists())
        self.assertEqual(a.git('status', '--porcelain'), '')

    def test_code_error_then_repair(self):
        self.plan()
        def fail_once(*args, **kwargs):
            if args[3].endswith('IMPORT') and self.calls == 1:
                return 1, 'SCRIPT ERROR: Parse Error'
            return self.provider(*args, **kwargs)
        with self.providers(process=fail_once):
            self.assertEqual(a.run_plan(self.c, self.p), 0)
        self.assertEqual(self.calls, 2)
        task = a.read(a.PLAN)['tasks'][0]
        data = a.read(self.here / 'runs' / task['run'] / 'autonomous.json')
        self.assertEqual(data['failures'][0]['category'], 'GAME_CODE')

    def test_engine_access_violation_revalidates_without_regenerating_code(self):
        plan = self.plan()
        imports = []
        def crash_once(*args, **kwargs):
            if args[3].endswith('IMPORT'):
                imports.append(True)
                if len(imports) == 1: return 3221225477, 'Godot import stopped unexpectedly'
            return self.provider(*args, **kwargs)
        with self.providers(process=crash_once): a.execute(plan['tasks'][0], plan, self.c, self.p)
        self.assertEqual(plan['tasks'][0]['status'], 'DONE')
        self.assertEqual(self.calls, 1)
        self.assertEqual(len(imports), 2)

    def test_zero_exit_error_and_leak_never_integrate(self):
        for text in ['ERROR: export invalid', 'WARNING: 6 ObjectDB instances were leaked at exit', 'ERROR: resources still in use at exit']:
            with self.subTest(text=text):
                plan = self.plan()
                task = plan['tasks'][0]
                with self.providers(process=lambda *args, **kwargs: (0, 'SLICE_ACCEPTANCE_PASS\n' + text)):
                    a.execute(task, plan, self.c, self.p)
                self.assertEqual(task['status'], 'BLOCKED')
                self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)

    def test_scope_violation_has_no_retry_or_source_change(self):
        plan = self.plan()
        def bad(stage, *args, **kwargs):
            self.calls += 1
            (stage / 'tests/smoke_test.gd').write_text('weakened')
        with self.providers(coder=bad): a.execute(plan['tasks'][0], plan, self.c, self.p)
        self.assertEqual(self.calls, 1)
        self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)
        self.assertEqual((self.game / 'tests/smoke_test.gd').read_text(), 'extends SceneTree\n')

    def test_codex_crash_is_blocked(self):
        plan = self.plan()
        def crash(*args, **kwargs): raise a.ERROR('CODEX: subprocess failed exit=17')
        with self.providers(coder=crash): a.execute(plan['tasks'][0], plan, self.c, self.p)
        self.assertEqual(plan['tasks'][0]['status'], 'BLOCKED')
        self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)

    def test_repair_budget_exhaustion(self):
        plan = self.plan()
        self.p['max_fixes'] = 3
        def fail(*args, **kwargs): return 1, 'SCRIPT ERROR: unique fault %d' % self.calls
        with self.providers(process=fail): a.execute(plan['tasks'][0], plan, self.c, self.p)
        self.assertEqual(self.calls, 4)
        self.assertEqual(plan['tasks'][0]['status'], 'BLOCKED')
        self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)

    def test_push_failure_resume_does_not_recode_or_recommit(self):
        self.plan()
        with self.providers(), patch.object(a, 'remote_backup', side_effect=a.ERROR('GIT_FAILURE: push')):
            self.assertEqual(a.run_plan(self.c, self.p, push=True), 2)
        commit = a.git('rev-parse', 'HEAD')
        self.assertNotEqual(commit, self.base)
        with self.providers(), patch.object(a, 'remote_backup', return_value={'status': 'VERIFIED'}):
            self.assertEqual(a.run_plan(self.c, self.p, recover=True, push=True), 0)
        self.assertEqual(a.git('rev-parse', 'HEAD'), commit)
        self.assertEqual(self.calls, 1)

    def test_commit_before_checkpoint_crash_is_recognized(self):
        plan = self.plan()
        run, data = a.new_run(plan['tasks'][0], self.c, self.p, plan)
        with self.providers():
            self.coder(run / 'game', run, data)
            a.qa(run / 'game', run, data, self.c, self.p, plan['tasks'][0])
            a.integrate(run, data, plan['tasks'][0], self.c, self.p)
            first = a.git('rev-parse', 'HEAD')
            data['phase'] = 'INTEGRATE'; data.pop('commit')
            a.integrate(run, data, plan['tasks'][0], self.c, self.p)
        self.assertEqual(data['commit'], first)
        self.assertEqual(a.git('rev-list', '--count', self.base + '..HEAD'), '1')

    def test_verified_snapshot_tampering_rejected(self):
        plan = self.plan()
        run, data = a.new_run(plan['tasks'][0], self.c, self.p, plan)
        with self.providers():
            self.coder(run / 'game', run, data)
            a.qa(run / 'game', run, data, self.c, self.p, plan['tasks'][0])
            (run / 'game/scripts/slice_main.gd').write_text('unvalidated')
            with self.assertRaises(a.ERROR): a.integrate(run, data, plan['tasks'][0], self.c, self.p)
        self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)

    def test_independent_acceptance_blocker_prevents_integration(self):
        plan = self.plan()
        run, data = a.new_run(plan['tasks'][0], self.c, self.p, plan)
        with self.providers():
            self.coder(run / 'game', run, data)
            a.qa(run / 'game', run, data, self.c, self.p, plan['tasks'][0])
            data['acceptance_blockers'] = ['Independent repeated audio exit test failed']
            with self.assertRaises(a.ERROR): a.integrate(run, data, plan['tasks'][0], self.c, self.p)
        self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)

    def test_pause_before_execution(self):
        self.plan()
        a.write(a.PAUSE, {'requested': a.now()})
        with self.providers(): self.assertEqual(a.run_plan(self.c, self.p), 2)
        self.assertEqual(self.calls, 0)

    def test_real_subprocess_exit_and_error_log_recorded(self):
        run = self.here / 'runs/process-fixture'; run.mkdir(parents=True)
        data = {}
        rc, text = a.process([sys.executable, '-c', 'print("ERROR: zero-exit fault")'], run, data, 'fault')
        self.assertEqual(rc, 0)
        self.assertIsNotNone(a.auto.ERRORS.search(text))
        self.assertEqual(a.read(run / 'autonomous.json')['processes'][0]['exit_code'], 0)

    def test_real_subprocess_timeout_is_recorded(self):
        run = self.here / 'runs/timeout-fixture'; run.mkdir(parents=True)
        data = {}
        rc, text = a.process([sys.executable, '-c', 'import time;time.sleep(30)'], run, data, 'timeout', timeout=0.1)
        self.assertEqual(rc, -1)
        self.assertIn('TIMEOUT', text)
        self.assertTrue(a.read(run / 'autonomous.json')['processes'][0]['timed_out'])

    def test_registered_acceptance_probe_is_required_before_integration(self):
        task = self.task(); task['acceptance_probes'] = ['context_tooltips']
        plan = self.plan([task])
        run, data = a.new_run(plan['tasks'][0], self.c, self.p, plan)
        def provider(cmd, run, data, name, *args, **kwargs):
            rc, text = self.provider(cmd, run, data, name, *args, **kwargs)
            return rc, text + ' TOOLTIP_ACCEPTANCE_PASS'
        with self.providers(process=provider):
            self.coder(run / 'game', run, data)
            a.qa(run / 'game', run, data, self.c, self.p, plan['tasks'][0])
            data['qa'] = [q for q in data['qa'] if not q['name'].startswith('ACCEPTANCE:')]
            with self.assertRaises(a.ERROR): a.integrate(run, data, plan['tasks'][0], self.c, self.p)
        self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)

    def test_model_blocker_and_unverified_acceptance_are_not_success(self):
        run = self.here / 'runs/model-contract'; run.mkdir(parents=True)
        for status, unverified, valid in [('implemented', [], True), ('blocked', [], False),
                                          ('implemented', ['Audio leak remains'], False)]:
            def provider(cmd, *args, **kwargs):
                if '--help' in cmd:
                    return 0, '--sandbox --json --output-last-message --output-schema'
                last = Path(cmd[cmd.index('--output-last-message') + 1])
                a.write(last, {'status': status, 'summary': 'fixture', 'unverified_acceptance': unverified,
                               'tests_actually_run': []})
                return 0, '{"type":"turn.completed"}'
            with self.subTest(status=status, unverified=unverified), patch.object(a, 'process', provider), patch.object(a, 'codex_executable', return_value=sys.executable):
                if valid:
                    self.assertTrue(a.codex(self.game, run, {}, 'fixture', self.c, self.p, 'model').is_file())
                else:
                    with self.assertRaises(a.ERROR): a.codex(self.game, run, {}, 'fixture', self.c, self.p, 'model')

    def test_explicit_goal_replacement_preserves_unfinished_plan(self):
        plan = self.plan()
        with self.assertRaises(a.ERROR): a.goal('new goal')
        a.goal('new goal', replace_incomplete=True)
        archived = list(a.STATE.glob('plan-history-*.json'))
        self.assertEqual(len(archived), 1)
        self.assertEqual(a.read(archived[0]), plan)
        self.assertEqual(a.read(a.PLAN)['status'], 'SUPERSEDED')
        self.assertEqual(a.read(a.STATE / 'goal.json')['text'], 'new goal')
        with self.assertRaises(a.ERROR): a.run_plan(self.c, self.p)


def contextlib_exit_stack():
    import contextlib
    return contextlib.ExitStack()


if __name__ == '__main__':
    unittest.main(verbosity=2)
