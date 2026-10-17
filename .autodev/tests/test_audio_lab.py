"""The lab's verdict parser is independent of the engine's exit code and marker."""
import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'audio_lab/runner.py'
spec = importlib.util.spec_from_file_location('audio_lab_runner', MODULE)
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class Verdicts(unittest.TestCase):
    clean = 'LAB_BEGIN {"driver":"WASAPI"}\nLAB_RESULT {"completed":true}\n'

    def test_clean_real_driver(self):
        self.assertTrue(lab.parse_log(self.clean, 'WASAPI', 0)['passed'])

    def test_zero_exit_and_success_marker_do_not_override_leak(self):
        result = lab.parse_log(self.clean + 'Leaked instance: AudioStreamWAV:123\nWARNING: 1 ObjectDB instances were leaked at exit\n', 'WASAPI', 0)
        self.assertFalse(result['passed'])
        self.assertEqual(result['leaked_objects'], {'AudioStreamWAV': 1})

    def test_warning_without_per_object_verbose_lines_is_failure(self):
        self.assertFalse(lab.parse_log(self.clean + 'WARNING: ObjectDB instances leaked at exit\n', 'WASAPI', 0)['passed'])

    def test_arbitrary_error_is_failure(self):
        self.assertFalse(lab.parse_log(self.clean + 'ERROR: something unrelated\n', 'WASAPI', 0)['passed'])

    def test_wrong_driver_is_failure(self):
        self.assertFalse(lab.parse_log(self.clean.replace('WASAPI', 'Dummy'), 'WASAPI', 0)['passed'])

    def test_crash_or_missing_result_is_failure(self):
        self.assertFalse(lab.parse_log(self.clean, 'WASAPI', 3221225477)['passed'])
        self.assertFalse(lab.parse_log('LAB_BEGIN {"driver":"WASAPI"}\n', 'WASAPI', 0)['passed'])

    def test_original_script_requires_wasapi_activation_and_marker(self):
        text = 'WASAPI: Activated output_device using IAudioClient3 interface\nRAPID_SFX_IMMEDIATE_EXIT\n'
        self.assertTrue(lab.parse_log(text, 'WASAPI', 0, original=True)['passed'])
        self.assertFalse(lab.parse_log(text.replace('WASAPI: Activated', 'Other: Activated'), 'WASAPI', 0, original=True)['passed'])

    def test_original_script_fallback_is_not_wasapi_pass(self):
        text = 'WASAPI: Activated output_device using IAudioClient3 interface\nAll audio drivers failed, falling back to the dummy driver.\nRAPID_SFX_IMMEDIATE_EXIT\n'
        self.assertFalse(lab.parse_log(text, 'WASAPI', 0, original=True)['passed'])

    def test_unknown_object_class_is_still_counted(self):
        result = lab.parse_log(self.clean + 'Leaked instance: :12345\n', 'WASAPI', 0)
        self.assertFalse(result['passed'])
        self.assertEqual(result['leaked_objects'], {'<unknown>': 1})

    def test_failed_attempts_remain_in_aggregate(self):
        records = [{'project': 'minimal', 'case': 'E', 'driver_requested': 'WASAPI',
                    'passed': ok, 'leaked_objects': {} if ok else {'AudioStreamWAV': 3}, 'duration_s': 0.3}
                   for ok in (False, True, False)]
        group = lab.summary(records)['minimal/E/WASAPI']
        self.assertEqual((group['attempts'], group['passed'], group['failed']), (3, 1, 2))
        self.assertEqual(group['leaked_objects'], {'AudioStreamWAV': 6})


if __name__ == '__main__':
    unittest.main(verbosity=2)
