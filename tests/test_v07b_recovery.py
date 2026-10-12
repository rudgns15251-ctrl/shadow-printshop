"""v0.7-B recovery gates; isolated local Git fixtures only (no Codex/Godot)."""
import contextlib
from contextlib import closing
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import v07b_recovery as recovery


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'repo'
        self.root.mkdir()
        self._git('init', '-q')
        self._git('config', 'user.email', 'test@invalid.example')
        self._git('config', 'user.name', 'Fixture')
        (self.root / '.gitignore').write_text('.data/\n.worktrees/\n', encoding='utf-8')
        (self.root / 'tasks').mkdir()
        (self.root / 'tasks' / 'backlog.json').write_text(json.dumps({'tasks': [{'id': 'ITER-002'}]}), encoding='utf-8')
        (self.root / 'dummy.txt').write_text('original', encoding='utf-8')
        self._git('add', '.')
        self._git('commit', '-qm', 'baseline')
        self.ws = self.root / '.worktrees' / 'ITER-002'
        self._git('worktree', 'add', '--detach', str(self.ws), 'HEAD')
        data = self.root / '.data'
        data.mkdir()
        with closing(sqlite3.connect(data / 'state.sqlite3')) as db, db:
            db.execute('CREATE TABLE tasks(id TEXT PRIMARY KEY,status TEXT, attempts INTEGER, workspace TEXT, last_note TEXT, updated TEXT)')
            db.execute('INSERT INTO tasks VALUES (?,?,?,?,?,?)',
                       ('ITER-002', 'blocked', 3, str(self.ws), 'Codex did not change any files.', 'before'))

    def _git(self, *a):
        result = subprocess.run(['git', *a], cwd=self.root, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def _registered_worktree_paths(self):
        """Compare parsed Git paths, not raw strings (Windows Git can emit / or \\)."""
        output = self._git('worktree', 'list', '--porcelain')
        return {
            Path(line[len('worktree '):]).resolve()
            for line in output.splitlines()
            if line.startswith('worktree ')
        }

    def _set(self, status=None, note=None):
        with closing(sqlite3.connect(self.root / '.data/state.sqlite3')) as db, db:
            if status is not None:
                db.execute('UPDATE tasks SET status=? WHERE id=?', (status, 'ITER-002'))
            if note is not None:
                db.execute('UPDATE tasks SET last_note=? WHERE id=?', (note, 'ITER-002'))

    def test_eligible_no_output(self):
        a = recovery.assess(self.root, 'ITER-002')
        self.assertTrue(a.eligible)
        self.assertEqual(a.category, 'NO_OUTPUT')

    def test_eligible_codex_exit(self):
        self._set(note='Codex exited with code 1. See logs/ITER-002.jsonl.log')
        self.assertTrue(recovery.assess(self.root, 'ITER-002').eligible)

    def test_running_refused(self):
        self._set(status='running')
        self.assertFalse(recovery.assess(self.root, 'ITER-002').eligible)

    def test_policy_refused(self):
        self._set(note='Out-of-scope file changed: etc')
        self.assertFalse(recovery.assess(self.root, 'ITER-002').eligible)

    def test_uncertain_execution_error_refused(self):
        self._set(note='Execution or validation failed: unknown access')
        self.assertFalse(recovery.assess(self.root, 'ITER-002').eligible)

    def test_modified_and_untracked_files_refused(self):
        (self.ws / 'scratch.txt').write_text('agent output')
        self.assertFalse(recovery.assess(self.root, 'ITER-002').eligible)
        (self.ws / 'scratch.txt').unlink()
        (self.ws / 'dummy.txt').write_text('changed')
        self.assertFalse(recovery.assess(self.root, 'ITER-002').eligible)

    def test_lock_refused(self):
        (self.root / '.data/autopilot.lock').write_text('{"pid": 123}')
        self.assertFalse(recovery.assess(self.root, 'ITER-002').eligible)

    def test_dirty_main_refused(self):
        (self.root / 'dummy.txt').write_text('dirty')
        self.assertFalse(recovery.assess(self.root, 'ITER-002').eligible)

    def test_no_mutation_on_check(self):
        with contextlib.redirect_stdout(io.StringIO()) as captured:
            rc = recovery.main(['recover', 'ITER-002', '--check'], root=self.root)
        self.assertEqual(rc, 0)
        self.assertIn('READ ONLY', captured.getvalue())
        with closing(sqlite3.connect(self.root / '.data/state.sqlite3')) as db, db:
            self.assertEqual(db.execute("SELECT status FROM tasks").fetchone()[0], 'blocked')
        self.assertTrue(self.ws.exists())
        self.assertFalse((self.root / '.data/recovery-v07b').exists())

    def test_recovery_moves_registered_worktree_and_preserves_history(self):
        old_head = self._git('rev-parse', 'HEAD').strip()
        self.assertIn(self.ws.resolve(), self._registered_worktree_paths())
        report = recovery.recover(self.root, 'ITER-002')
        self.assertFalse(self.ws.exists())
        self.assertTrue(Path(report['archived_worktree']).is_dir())
        self.assertTrue(Path(report['sqlite_backup']).is_file())
        self.assertIn(Path(report['archived_worktree']).resolve(), self._registered_worktree_paths())
        self.assertNotIn(self.ws.resolve(), self._registered_worktree_paths())
        self.assertEqual(self._git('rev-parse', 'HEAD').strip(), old_head)
        with closing(sqlite3.connect(self.root / '.data/state.sqlite3')) as db, db:
            self.assertEqual(db.execute('SELECT status, attempts, workspace, last_note FROM tasks').fetchone(),
                             ('pending', 3, None, 'Codex did not change any files.'))
        with closing(sqlite3.connect(report['sqlite_backup'])) as db:
            self.assertEqual(db.execute('SELECT status, attempts FROM tasks').fetchone(), ('blocked', 3))
        self.assertFalse(recovery.assess(self.root, 'ITER-002').eligible)

    def test_bad_identifier_refused(self):
        with self.assertRaises(recovery.RecoveryRefused):
            recovery.assess(self.root, '../outside')

    def test_unknown_task_refused(self):
        with self.assertRaises(recovery.RecoveryRefused):
            recovery.assess(self.root, 'ANOTHER')


class SchedulerCLITests(unittest.TestCase):
    def test_triage_cli_delegates_without_apply(self):
        import autopilot
        with patch('v07b_recovery.main', return_value=0) as delegate:
            self.assertEqual(autopilot.main(['triage', 'ITER-002']), 0)
        delegate.assert_called_once_with(['triage', 'ITER-002'], root=autopilot.ROOT)

    def test_recover_cli_defaults_to_check(self):
        import autopilot
        with patch('v07b_recovery.main', return_value=0) as delegate:
            self.assertEqual(autopilot.main(['recover', 'ITER-002']), 0)
        delegate.assert_called_once_with(['recover', 'ITER-002', '--check'], root=autopilot.ROOT)

    def test_recover_cli_requires_explicit_apply(self):
        import autopilot
        with patch('v07b_recovery.main', return_value=0) as delegate:
            self.assertEqual(autopilot.main(['recover', 'ITER-002', '--apply']), 0)
        delegate.assert_called_once_with(['recover', 'ITER-002', '--apply'], root=autopilot.ROOT)

    def test_default_legacy_autoretry_is_disabled(self):
        import autopilot
        with patch.object(autopilot, 'run_worker') as run:
            self.assertEqual(autopilot.main(['run']), 0)
        self.assertEqual(run.call_args.args[3], 0)


if __name__ == '__main__':
    unittest.main()
