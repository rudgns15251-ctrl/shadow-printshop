import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from subprocess import CompletedProcess

import engine_adapter
import harness


class GodotGateTests(unittest.TestCase):
    def test_new_task_has_godot_gate(self):
        tasks = {t['id']: t for t in harness.read_tasks()}
        self.assertTrue(tasks['PROTO-001']['godot_validation'])
        self.assertEqual(tasks['PROTO-001']['dependencies'], ['ASSESS-001'])
        self.assertFalse(tasks['PLAN-002'].get('godot_validation', False))

    def test_missing_generated_game_files_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            ok, note = engine_adapter.check_sources(Path(temp))
            self.assertFalse(ok)

    def test_dangerous_process_launch_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            game = Path(temp)
            for rel in engine_adapter.REQUIRED:
                p = game / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('A' * 120, encoding='utf-8')
            script = game / 'scripts' / 'game_state.gd'
            script.write_text('OS.execute("cmd", [])\n', encoding='utf-8')
            ok, note = engine_adapter.check_sources(game)
            self.assertFalse(ok)
            self.assertIn('Blocked', note)

    def test_valid_generated_game_runs_three_headless_gates(self):
        with tempfile.TemporaryDirectory() as temp:
            original = engine_adapter.ROOT
            engine_adapter.ROOT = Path(temp)
            try:
                game = Path(temp) / engine_adapter.PROJECT_REL
                for rel in engine_adapter.REQUIRED:
                    p = game / rel
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text('extends Node\n' + '# dummy\n'*15, encoding='utf-8')
                observed = []
                def mock_command(cmd, timeout=90, cwd=None):
                    observed.append(cmd)
                    if '--script' in cmd:
                        return CompletedProcess(cmd, 0, 'HARNESS_SMOKE_PASS\n')
                    return CompletedProcess(cmd, 0, 'Godot 4.4\n')
                with patch.object(engine_adapter, 'locate', return_value='godot-mock'), patch.object(engine_adapter, 'run_command', side_effect=mock_command):
                    ok, note = engine_adapter.validate(Path(temp), {'id':'PROTO-001'})
                self.assertTrue(ok, note)
                self.assertEqual(len(observed), 3)
                self.assertTrue((Path(temp)/'logs/godot/PROTO-001.log').exists())
            finally:
                engine_adapter.ROOT = original

    def test_missing_smoke_marker_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            original = engine_adapter.ROOT
            engine_adapter.ROOT = Path(temp)
            try:
                game = Path(temp) / engine_adapter.PROJECT_REL
                for rel in engine_adapter.REQUIRED:
                    p = game / rel
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text('extends Node\n', encoding='utf-8')
                with patch.object(engine_adapter, 'locate', return_value='godot-mock'), patch.object(engine_adapter, 'run_command', return_value=CompletedProcess(['mock'], 0, 'Godot 4.4\n')):
                    ok, reason = engine_adapter.validate(Path(temp), {'id':'PROTO-001'})
                self.assertFalse(ok)
                self.assertIn('marker', reason)
            finally:
                engine_adapter.ROOT = original

    def test_game_gate_only_when_opted_in(self):
        with patch.object(engine_adapter, 'validate', return_value=(True, 'ok')) as validate:
            self.assertEqual(harness.check_godot_gate(Path('.'), {'id':'PLAN-001'}, True, 'valid'), (True, 'valid'))
            validate.assert_not_called()
            self.assertEqual(harness.check_godot_gate(Path('.'), {'id':'PROTO-001','godot_validation':True}, True, 'valid'), (True, 'ok'))
            validate.assert_called_once()

if __name__ == '__main__':
    unittest.main()
