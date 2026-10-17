"""Custom-engine provenance and protected-installation regression checks."""
import copy
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import auto


class EngineProfile(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.here = self.root / '.autodev'
        self.stage = self.root / '.data/stage'
        self.stage.mkdir(parents=True)
        self.engine = self.root / '.data/engine.exe'
        self.engine.write_bytes(b'MZ' + b'engine' * 20000)
        profile = {'engine_sha256': auto.sha(self.engine)}
        for mode in ('debug', 'release'):
            binary = self.root / ('.data/' + mode + '.exe')
            binary.write_bytes(b'MZ' + mode.encode() * 30000)
            profile[mode] = {'path': str(binary), 'sha256': auto.sha(binary)}
        self.config = {'godot': str(self.engine), 'engine_profile': profile}
        for key, value in [('ROOT', self.root), ('HERE', self.here)]:
            context = patch.object(auto, key, value)
            context.start()
            self.addCleanup(context.stop)
        context = patch.dict(os.environ, {}, clear=False)
        context.start()
        self.addCleanup(context.stop)
        os.environ.pop('GODOT_BIN', None)

    def test_pinned_templates_are_only_configured_in_isolated_copy(self):
        auto.make_export_preset(self.stage, self.config)
        preset = self.stage / 'export_presets.cfg'
        before = preset.read_bytes()
        self.assertIn(Path(self.config['engine_profile']['release']['path']).as_posix(), before.decode())
        auto.make_export_preset(self.stage, self.config)
        self.assertEqual(preset.read_bytes(), before)
        user_game = self.root / 'game'
        user_game.mkdir()
        original = user_game / 'export_presets.cfg'
        original.write_text('user content')
        with self.assertRaises(auto.StopRun):
            auto.make_export_preset(user_game, self.config)
        self.assertEqual(original.read_text(), 'user content')

    def test_changed_engine_is_rejected(self):
        self.engine.write_bytes(b'MZ' + b'changed' * 20000)
        with self.assertRaisesRegex(auto.StopRun, 'engine hash mismatch'):
            auto.make_export_preset(self.stage, self.config)
        self.assertFalse((self.stage / 'export_presets.cfg').exists())

    def test_changed_or_missing_template_is_rejected(self):
        binary = Path(self.config['engine_profile']['release']['path'])
        binary.write_bytes(b'MZ' + b'tampered' * 20000)
        with self.assertRaisesRegex(auto.StopRun, 'template hash mismatch'):
            auto.profile_templates(self.engine, self.config)
        missing = copy.deepcopy(self.config)
        missing['engine_profile'].pop('debug')
        with self.assertRaisesRegex(auto.StopRun, 'template missing'):
            auto.profile_templates(self.engine, missing)

    def test_template_outside_workspace_is_rejected_even_with_matching_hash(self):
        binary = self.root / 'installed-template.exe'
        binary.write_bytes(b'MZ' + b'outside' * 20000)
        self.config['engine_profile']['release'] = {'path': str(binary), 'sha256': auto.sha(binary)}
        with self.assertRaisesRegex(auto.StopRun, 'workspace .data'):
            auto.profile_templates(self.engine, self.config)

    def test_existing_unrelated_preset_is_preserved(self):
        preset = self.stage / 'export_presets.cfg'
        text = auto.PRESET.replace('custom_template/debug=""', 'custom_template/debug="user.exe"')
        preset.write_text(text, encoding='utf-8')
        with self.assertRaisesRegex(auto.StopRun, 'unrelated custom export template'):
            auto.make_export_preset(self.stage, self.config)
        self.assertEqual(preset.read_text(encoding='utf-8'), text)


if __name__ == '__main__':
    unittest.main()
