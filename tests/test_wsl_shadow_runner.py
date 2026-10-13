"""Isolated WSL shadow runner tests. No network, live Codex, Windows Git or SQLite."""
from __future__ import annotations
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import wsl_shadow_runner as shadow

FAKE_CODEX = '''#!{python}
import os, sys, subprocess
from pathlib import Path
args=sys.argv[1:]; wd=Path(args[args.index('-C')+1]); act=os.environ['FAKE_ACTION']
_ = sys.stdin.read()
if act == 'create':
 (wd/'projects/game/assets/art').mkdir(parents=True,exist_ok=True)
 (wd/'projects/game/assets/art/test.svg').write_bytes(b'<svg>test</svg>')
elif act == 'modify':
 (wd/'projects/game/notes.md').write_text('changed',encoding='utf-8')
elif act == 'outside':
 (wd/'README.md').write_text('bad',encoding='utf-8')
elif act == 'protected':
 (wd/'projects/game/protected.md').write_text('bad',encoding='utf-8')
elif act == 'delete':
 (wd/'projects/game/notes.md').unlink()
elif act == 'symlink':
 (wd/'projects/game/assets').mkdir(parents=True,exist_ok=True)
 (wd/'projects/game/assets/link').symlink_to('/tmp')
elif act == 'commit':
 (wd/'projects/game/notes.md').write_text('edited',encoding='utf-8')
 subprocess.run(['git','-C',str(wd),'add','-A'],check=True)
 subprocess.run(['git','-C',str(wd),'-c','user.name=X','-c','user.email=x@invalid','commit','-qm','agent commit'],check=True)
elif act == 'drop_lease':
 (wd/'projects/game/notes.md').write_text('changed', encoding='utf-8')
 Path(os.environ['FAKE_LEASE']).unlink()
elif act == 'fail':
 sys.exit(7)
else: raise Exception('unknown action')
print('FAKE_CODEX_DONE')
'''

@unittest.skipIf(os.name == 'nt', 'Run these native-Git shadow tests inside WSL Ubuntu')
class ShadowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.src = self.root / '.worktrees' / 'T01'
        self.src.mkdir(parents=True)
        (self.src / '.git').write_text('gitdir: C:/fake/linked/worktree\n')
        (self.src / 'projects/game/assets').mkdir(parents=True)
        (self.src / 'projects/game/notes.md').write_text('baseline',encoding='utf-8')
        (self.src / 'projects/game/protected.md').write_text('protected',encoding='utf-8')
        (self.src / 'README.md').write_text('do not modify',encoding='utf-8')
        (self.root / 'tasks').mkdir()
        (self.root/'tasks/backlog.json').write_text('''{"tasks":[{"id":"T01", "allowed_prefixes":["projects/game/"], "protected_files":["projects/game/protected.md"]}]}''')
        self.fake = self.root / 'fake-codex'
        self.fake.write_text(FAKE_CODEX.format(python=sys.executable))
        self.fake.chmod(0o755)
        self.args=['exec','--sandbox','workspace-write','-C',str(self.src),'--json','-']
        self.stage_root=self.root/'shadow'

    def run_case(self, action):
        with patch.dict(os.environ, {'FAKE_ACTION':action}):
            return shadow.run(self.src,str(self.fake),self.args,'PROMPT',stage_root=self.stage_root)

    def test_new_art_file_copied_to_windows_without_git_changes(self):
        self.assertEqual(self.run_case('create'),0)
        self.assertEqual((self.src/'projects/game/assets/art/test.svg').read_bytes(),b'<svg>test</svg>')
        self.assertEqual((self.src/'.git').read_text(),'gitdir: C:/fake/linked/worktree\n')
        self.assertFalse(list(self.stage_root.iterdir()))

    def test_allowed_existing_file_can_be_updated(self):
        self.assertEqual(self.run_case('modify'),0)
        self.assertEqual((self.src/'projects/game/notes.md').read_text(),'changed')

    def test_forbidden_file_is_refused_without_source_modification(self):
        with self.assertRaisesRegex(shadow.GuardError,'Out-of-scope'):
            self.run_case('outside')
        self.assertEqual((self.src/'README.md').read_text(),'do not modify')
        self.assertTrue(list(self.stage_root.iterdir()))

    def test_protected_file_is_refused(self):
        with self.assertRaisesRegex(shadow.GuardError,'Protected file'):
            self.run_case('protected')
        self.assertEqual((self.src/'projects/game/protected.md').read_text(),'protected')

    def test_deletion_is_refused(self):
        with self.assertRaisesRegex(shadow.GuardError,'Deleting existing files'):
            self.run_case('delete')
        self.assertEqual((self.src/'projects/game/notes.md').read_text(),'baseline')

    def test_symlink_is_refused(self):
        with self.assertRaisesRegex(shadow.GuardError,'Symlink'):
            self.run_case('symlink')
        self.assertFalse((self.src/'projects/game/assets/link').exists())

    def test_nonzero_exit_preserves_shadow_but_not_source(self):
        with self.assertRaisesRegex(shadow.GuardError,'exited with code 7'):
            self.run_case('fail')
        self.assertEqual((self.src/'projects/game/notes.md').read_text(),'baseline')
        self.assertTrue(list(self.stage_root.iterdir()))

    def test_agent_commit_is_refused(self):
        with self.assertRaisesRegex(shadow.GuardError,'created Git commit'):
            self.run_case('commit')
        self.assertEqual((self.src/'projects/game/notes.md').read_text(),'baseline')

    def test_expired_worker_lock_prevents_copy_back(self):
        data = self.root / '.data'
        data.mkdir()
        lease = data / 'autopilot.lock'
        lease.write_text('{"pid":4242,"started_at":"test","purpose":"autopilot run"}')
        with patch.dict(os.environ, {'FAKE_ACTION':'drop_lease', 'FAKE_LEASE':str(lease)}):
            with self.assertRaisesRegex(shadow.GuardError, 'lease no longer exists'):
                shadow.run(self.src, str(self.fake), self.args, 'PROMPT',
                           stage_root=self.stage_root, lock_path=lease)
        self.assertEqual((self.src/'projects/game/notes.md').read_text(), 'baseline')

    def test_unsupported_path_is_refused(self):
        with self.assertRaises(shadow.GuardError):
            shadow.guarded_relpath('../oops')
        with self.assertRaises(shadow.GuardError):
            shadow.guarded_relpath('C:/test')

    def test_concurrent_source_change_is_refused(self):
        original = shadow.file_map(self.src)
        (self.src/'README.md').write_text('external edit')
        with self.assertRaisesRegex(shadow.GuardError,'Source worktree changed'):
            shadow.verify_source(self.src,original)

if __name__ == '__main__': unittest.main(verbosity=2)
