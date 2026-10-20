"""Fault injection for the Claude CLI adapter, operator path and operator replan.

Mock providers only: these tests never call a real model, Godot or GitHub.
"""
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(1, str(Path(__file__).resolve().parents[2]))
import engine_adapter  # noqa: F401  (static_check imports it after ROOT is patched to a fixture)
import autonomous as a
import director as d
import test_autonomous as base
import test_director as dbase

HELP = 'Usage: claude ' + ' '.join(a.CLAUDE_FLAGS)

def result(**extra):
    row = {'type': 'result', 'subtype': 'success', 'is_error': False, 'num_turns': 3, 'total_cost_usd': 0.1,
           'result': 'done', 'permission_denials': []}
    row.update(extra)
    return json.dumps(row)

def outcome(status='code_ready', unverified=()):
    return {'status': status, 'summary': 'edited', 'unverified_acceptance': list(unverified),
            'tests_actually_run': ['static read'], 'verification_pending': ['trusted QA'],
            'human_review_pending': ['taste']}

class ClaudeAdapter(base.Coordinator):
    def setUp(self):
        super().setUp()
        self.c = dict(self.c, model_cli='claude', claude_executable=sys.executable, claude_model='opus')
        self.run = self.root / 'run'; self.run.mkdir()
        self.data = {}
        self.commands = []

    def fake(self, final_line, code=0):
        def provider(cmd, run, data, name, timeout=240, env=None, stdin=None, cwd=None):
            self.commands.append((list(map(str, cmd)), name, env, cwd))
            if name.endswith('-help'):
                return 0, HELP
            return code, 'warning on stderr\n' + final_line + '\n'
        return provider

    def call(self, final_line, code=0, read_only=False, schema=None, logged_in=True):
        with patch.object(a, 'process', self.fake(final_line, code)), \
             patch.object(a, 'claude_logged_in', return_value=logged_in), \
             patch.object(a, 'handoff_enabled', return_value=True):
            return a.codex(self.game, self.run, self.data, 'prompt', self.c, self.p, 'coder-1', read_only, schema)

    def test_writer_success_and_restricted_contract(self):
        last = self.call(result(structured_output=outcome()))
        self.assertEqual(a.read(last)['status'], 'code_ready')
        cmd, name, env, cwd = self.commands[-1]
        self.assertEqual(cwd, self.game)
        self.assertIn('--print', cmd); self.assertIn('--safe-mode', cmd); self.assertIn('--no-session-persistence', cmd)
        self.assertEqual(cmd[cmd.index('--tools') + 1], 'Read,Grep,Glob,Edit,Write')
        self.assertEqual(cmd[cmd.index('--permission-mode') + 1], 'acceptEdits')
        joined = ' '.join(cmd)
        for forbidden in ('Bash', 'PowerShell', 'bypassPermissions', 'dangerously', 'WebFetch'):
            self.assertNotIn(forbidden, joined)
        self.assertEqual(self.data['model_calls'][-1]['subtype'], 'success')
        self.assertEqual(self.data['model_outcomes'][-1]['name'], 'coder-1')

    def test_read_only_roles_have_no_edit_tools(self):
        schema = self.run / 'review.json'; a.write(schema, a.REVIEW_SCHEMA)
        review = {'decision': 'accept', 'implementation_status': 'code_ready', 'narrative_editor': [],
                  'design_visual_flow_technical': [], 'blocking_issues': [], 'human_review_pending': []}
        self.call(result(structured_output=review), read_only=True, schema=schema)
        cmd = self.commands[-1][0]
        self.assertEqual(cmd[cmd.index('--tools') + 1], 'Read,Grep,Glob')
        self.assertEqual(cmd[cmd.index('--permission-mode') + 1], 'dontAsk')

    def test_not_logged_in_stops_before_model_call(self):
        with self.assertRaises(a.ERROR) as caught:
            self.call(result(structured_output=outcome()), logged_in=False)
        self.assertTrue(str(caught.exception).startswith('AUTH_OR_USAGE: bounded stop;'))
        self.assertIn(a.classify('IMPLEMENT', str(caught.exception)), a.FATAL)
        self.assertEqual([n for _, n, _, _ in self.commands], ['coder-1-help'])

    def test_cli_auth_rate_and_budget_failures_are_fatal(self):
        for line, code in [(result(is_error=True, result='Not logged in · Please run /login'), 1),
                           (result(is_error=True, result='API Error', api_error_status=429), 1),
                           (result(is_error=True, subtype='error_max_budget_usd', result=''), 1)]:
            with self.subTest(line=line), self.assertRaises(a.ERROR) as caught:
                self.call(line, code)
            self.assertIn(a.classify('IMPLEMENT', str(caught.exception)), a.FATAL)

    def test_model_failures_stop_without_success(self):
        for line, code in [(result(is_error=True, subtype='error_max_turns', result=''), 1),
                           ('not json at all', 0), ('', -1),
                           (result(structured_output={'status': 'implemented'}), 0),
                           (result(), 0)]:
            with self.subTest(line=line), self.assertRaises(a.ERROR) as caught:
                self.call(line, code)
            self.assertEqual(a.classify('IMPLEMENT', str(caught.exception)), 'CODEX')
            self.assertFalse((self.run / 'coder-1-last.txt').exists())

    def test_blocked_or_unverified_writer_is_never_success(self):
        for status, unverified in [('blocked', ['x']), ('implemented', ['still unverified'])]:
            with self.subTest(status=status), self.assertRaisesRegex(a.ERROR, 'ACCEPTANCE_UNVERIFIED'):
                self.call(result(structured_output=outcome(status, unverified)))

    def test_session_identity_is_not_inherited(self):
        with patch.dict(os.environ, {'CLAUDECODE': '1', 'CLAUDE_CODE_SIMPLE': '1', 'CLAUDE_AGENT_SDK_VERSION': 'x',
                                     'KEEP_ME': 'y'}):
            env = a.claude_env()
        self.assertNotIn('CLAUDECODE', env); self.assertNotIn('CLAUDE_CODE_SIMPLE', env)
        self.assertNotIn('CLAUDE_AGENT_SDK_VERSION', env); self.assertEqual(env['KEEP_ME'], 'y')

    def test_codex_remains_default(self):
        c = dict(self.c); c.pop('model_cli')
        with patch.object(a, 'codex_executable', side_effect=a.ERROR('codex path used')):
            with self.assertRaisesRegex(a.ERROR, 'codex path used'):
                a.codex(self.game, self.run, {}, 'p', c, self.p, 'x')

    def test_run_plan_refuses_unauthenticated_before_attempt(self):
        self.plan()
        with self.providers(), patch.object(a, 'claude_logged_in', return_value=False):
            with self.assertRaisesRegex(a.ERROR, 'AUTH_OR_USAGE'):
                a.run_plan(self.c, self.p)
        task = a.read(a.PLAN)['tasks'][0]
        self.assertEqual((task['status'], task['attempts'], task.get('run')), ('PENDING', 0, None))


class OperatorPath(base.Coordinator):
    def setUp(self):
        super().setUp()
        self.plan()
        self.ctx = self.providers(); self.ctx.__enter__(); self.addCleanup(self.ctx.__exit__, None, None, None)
        handoff = patch.object(a, 'handoff_enabled', return_value=True); handoff.start(); self.addCleanup(handoff.stop)

    def stage(self):
        with patch('builtins.print'):
            a.operator_stage('first', self.c, self.p)
        task = a.read(a.PLAN)['tasks'][0]
        return task['run'], a.HERE / 'runs' / task['run'] / 'game'

    def file(self, name, value):
        # Untracked evidence inside the repository would (correctly) block integration.
        path = a.STATE / 'operator' / name; a.write(path, value); return path

    def review(self, decision='accept', issues=()):
        return self.file('review.json', {'decision': decision, 'implementation_status': 'code_ready',
                                         'narrative_editor': [], 'design_visual_flow_technical': [],
                                         'blocking_issues': list(issues), 'human_review_pending': ['taste']})

    def test_full_operator_flow_integrates_with_recorded_review(self):
        run, stage = self.stage()
        (stage / 'scripts/slice_main.gd').write_text('extends Control\n# operator edit\n')
        with patch('builtins.print'):
            a.operator_verify(run, self.file('out.json', outcome()), self.c, self.p)
            a.operator_review(run, self.review(), 'independent read-only reviewer', self.c, self.p)
            a.operator_integrate(run, self.c, self.p, push=False)
        plan = a.read(a.PLAN)
        self.assertEqual((plan['tasks'][0]['status'], plan['status']), ('DONE', 'DONE'))
        self.assertEqual(a.git('rev-list', '--count', self.base + '..HEAD'), '1')
        self.assertIn('# operator edit', (self.game / 'scripts/slice_main.gd').read_text())
        data = a.read(a.HERE / 'runs' / run / 'autonomous.json')
        self.assertEqual(data['production_reviews'][-1]['reviewer'], 'independent read-only reviewer')
        self.assertEqual(a.git('status', '--porcelain'), '')

    def test_pre_integration_guard_refusal_can_retry_without_reverification(self):
        run, stage = self.stage()
        (stage / 'scripts/slice_main.gd').write_text('extends Control\n# edit\n')
        with patch('builtins.print'):
            a.operator_verify(run, self.file('out.json', outcome()), self.c, self.p)
            a.operator_review(run, self.review(), 'reviewer', self.c, self.p)
        stray = self.root / 'stray.txt'; stray.write_text('unrelated')
        with self.assertRaisesRegex(a.ERROR, 'dirty'):
            a.operator_integrate(run, self.c, self.p, push=False)
        self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)
        (stage / 'scripts/slice_main.gd').write_text('extends Control\n# tampered\n')
        stray.unlink()
        with self.assertRaisesRegex(a.ERROR, 'changed'):
            a.operator_integrate(run, self.c, self.p, push=False)
        (stage / 'scripts/slice_main.gd').write_text('extends Control\n# edit\n')
        with patch('builtins.print'):
            a.operator_integrate(run, self.c, self.p, push=False)
        self.assertEqual(a.read(a.PLAN)['tasks'][0]['status'], 'DONE')
        self.assertEqual(len(a.read(a.HERE / 'runs' / run / 'autonomous.json')['integration_retries']), 1)

    def test_integration_refused_without_review_or_after_revise(self):
        run, stage = self.stage()
        (stage / 'scripts/slice_main.gd').write_text('extends Control\n# edit\n')
        with patch('builtins.print'):
            a.operator_verify(run, self.file('out.json', outcome()), self.c, self.p)
        with self.assertRaisesRegex(a.ERROR, 'review missing or stale'):
            a.operator_integrate(run, self.c, self.p, push=False)
        with self.assertRaisesRegex(a.ERROR, 'REVIEW FAIL'):
            a.operator_review(run, self.review('revise', ['scripts/slice_main.gd: defect']), 'reviewer', self.c, self.p)
        with self.assertRaisesRegex(a.ERROR, 'Run not verified'):
            a.operator_integrate(run, self.c, self.p, push=False)
        self.assertEqual(a.git('rev-parse', 'HEAD'), self.base)

    def test_blocked_outcome_and_scope_violation_never_reach_qa(self):
        run, stage = self.stage()
        (stage / 'scripts/slice_main.gd').write_text('extends Control\n# edit\n')
        with self.assertRaisesRegex(a.ERROR, 'operator verification failed'):
            a.operator_verify(run, self.file('out.json', outcome('blocked', ['gap'])), self.c, self.p)
        (stage / 'tests/smoke_test.gd').write_text('extends SceneTree\n# weakened\n')
        with self.assertRaisesRegex(a.ERROR, 'SCOPE'):
            a.operator_verify(run, self.file('out.json', outcome()), self.c, self.p)
        data = a.read(a.HERE / 'runs' / run / 'autonomous.json')
        self.assertEqual((data['attempts'], data['phase'], data['qa']), (2, 'REPAIR', []))

    def test_budget_and_live_owner_are_enforced(self):
        run, stage = self.stage()
        out = self.file('out.json', outcome('blocked', ['gap']))
        for _ in range(4):
            with self.assertRaises(a.ERROR): a.operator_verify(run, out, self.c, self.p)
        with self.assertRaisesRegex(a.ERROR, 'budget'):
            a.operator_verify(run, out, self.c, self.p)
        a.write(a.STATE / 'production/owner.json', {'pid': os.getpid()})
        with self.assertRaisesRegex(a.ERROR, 'owner is live'):
            a.operator_verify(run, out, self.c, self.p)


class OperatorReplan(dbase.ProductionTests):
    def test_operator_plan_archives_blocked_plan_and_reconciles_scope(self):
        for name in ('NARRATIVE_BIBLE.md', 'CHARACTER_BIBLE.md'): (self.root / name).write_text('fixture', encoding='utf-8')
        self.m['milestones'][0]['tasks'] = 1
        a.write(d.MANIFEST, self.m)
        state = d.initial(self.m); state['manifest_sha256'] = 'previous'
        state['milestones'][0]['status'] = 'BLOCKED'
        a.write(d.STATE, state)
        old = {'goal': 'old', 'status': 'INCOMPLETE', 'planning_run': 'r1',
               'tasks': [{'id': 'old', 'status': 'BLOCKED', 'run': None}]}
        a.write(a.PLAN, old)
        tasks ={'tasks': [{'id': 'fresh', 'objective': 'o', 'allowed': ['scripts/slice_main.gd'], 'risk': 'low',
                            'depends_on': [], 'acceptance': ['x'], 'expected_failures': ['y'], 'recovery': 'z',
                            'deliverables': ['w'], 'acceptance_probes': []}]}
        tasks_file = self.root / 'tasks.json'; a.write(tasks_file, tasks)
        policy = {'approved_game_files': ['scripts/slice_main.gd'], 'protected': [], 'max_tasks': 8, 'max_fixes': 3}
        with patch.object(a, 'config', return_value={}), patch.object(a, 'policy', return_value=policy), \
             patch.object(a, 'branch_ok', return_value='codex/fixture'), patch.object(a, 'clean'), \
             patch.object(a.auto, 'sha', side_effect=lambda path: 'digest-' + Path(path).name), \
             patch.object(d, 'report', return_value={}), patch('builtins.print'):
            d.operator_plan('story', str(tasks_file), 'blocked plan demanded uncovered human review')
        plan = a.read(a.PLAN)
        self.assertEqual((plan['planner'], plan['status'], [t['id'] for t in plan['tasks']]),
                         ('claude-code-operator', 'PLANNED', ['fresh']))
        self.assertEqual(plan['tasks'][0]['attempts'], 0)
        history = list((a.STATE).glob('plan-history-*.json'))
        self.assertEqual(len(history), 1); self.assertEqual(a.read(history[0])['tasks'][0]['id'], 'old')
        saved = a.read(d.STATE)
        self.assertEqual(saved['milestones'][0]['status'], 'PENDING')
        self.assertEqual(saved['manifest_sha256'], 'digest-production.json')
        self.assertTrue(any(e.get('type') == 'MANIFEST_RECONCILED' for e in saved['events']))
        self.assertEqual(saved['milestones'][0]['operator_replans'][0]['previous_tasks'][0]['id'], 'old')

    def test_operator_plan_refuses_wrong_task_count_and_done_milestone(self):
        state = d.initial(self.m); state['manifest_sha256'] = 'x'; state['milestones'][0]['status'] = 'DONE'
        a.write(d.STATE, state)
        with patch.object(a.auto, 'sha', return_value='x'):
            with self.assertRaisesRegex(a.ERROR, 'not ready'):
                d.operator_plan('story', 'unused.json', 'reason')


def load_tests(loader, tests, pattern):
    # Only this module's own tests; inherited fixture tests already run elsewhere.
    suite = unittest.TestSuite()
    for cls in (ClaudeAdapter, OperatorPath, OperatorReplan):
        for name in sorted(n for n, v in vars(cls).items() if n.startswith('test_') and callable(v)):
            suite.addTest(cls(name))
    return suite

if __name__ == '__main__':
    unittest.main()
