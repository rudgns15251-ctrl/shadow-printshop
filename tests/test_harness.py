import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import harness


class StarterTests(unittest.TestCase):
    def test_task_manifest_valid(self):
        tasks = harness.read_tasks()
        self.assertEqual(len(tasks), 1)
        self.assertEqual(tasks[0]['id'], 'PLAN-001')

    def test_allowed_paths_with_boundary(self):
        prefix = ['projects/first-game/design/']
        self.assertTrue(harness.is_allowed('projects/first-game/design/concepts.md', prefix))
        self.assertFalse(harness.is_allowed('projects/first-game/design-evil/file.md', prefix))
        self.assertFalse(harness.is_allowed('harness.py', prefix))

    def test_parent_escape_rejected(self):
        with self.assertRaises(ValueError):
            harness.validate_relpath('projects/../escape.txt')
        with self.assertRaises(ValueError):
            harness.validate_relpath('C:\\Users\\secret')

    def test_prompt_scope(self):
        task = harness.read_tasks()[0]
        prompt = harness.build_prompt(task)
        self.assertIn('ONLY ALLOWED EDIT PATHS', prompt)
        self.assertIn('No Git commits', prompt)


if __name__ == '__main__':
    unittest.main()
