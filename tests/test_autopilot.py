import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import autopilot


class AutopilotV02Tests(unittest.TestCase):
    def test_ready_orders_priority_and_dependencies(self):
        tasks = [
            {'id':'A','priority':1,'dependencies':[]},
            {'id':'B','priority':40,'dependencies':['A']},
            {'id':'C','priority':20,'dependencies':[]},
        ]
        rows = {k:{'status':'pending'} for k in ('A','B','C')}
        self.assertEqual([t['id'] for t in autopilot.ready_tasks(tasks,rows)], ['C','A'])
        rows['A']['status'] = 'completed'
        self.assertEqual([t['id'] for t in autopilot.ready_tasks(tasks,rows)], ['B','C'])

    def test_safe_retry_rejects_changed_files(self):
        fake_ws = ROOT / '.worktrees' / 'PLAN-002'
        with patch.object(autopilot.harness, 'read_tasks',return_value=[{'id':'PLAN-002'}]), \
             patch.object(autopilot.harness,'db') as db, \
             patch.object(autopilot.harness,'changed_paths', return_value=['new_file.md']), \
             patch.object(Path,'is_dir',return_value=True):
            db.return_value.__enter__.return_value.execute.return_value.fetchone.return_value = \
                ('blocked',str(fake_ws),'Codex exited with code 1')
            self.assertFalse(autopilot.safe_retry_if_clean('PLAN-002'))

    def test_no_unrequested_live_actions_by_default(self):
        # A dry run only prints a plan; never launches Codex.
        with patch.object(autopilot, 'show_plan') as show, \
             patch.object(autopilot, 'call_harness') as call:
            autopilot.run_worker(False,2,45,1,930)
            show.assert_called_once()
            call.assert_not_called()

    def test_lock_is_unique(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp, patch.object(autopilot,'LOCK',Path(tmp)/'lock'):
            with autopilot.SingleWorker():
                with self.assertRaises(RuntimeError):
                    with autopilot.SingleWorker():
                        pass
            self.assertFalse(autopilot.LOCK.exists())


if __name__ == '__main__':
    unittest.main()
