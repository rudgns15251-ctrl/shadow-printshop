import unittest

import harness


class MarketTaskIntegration(unittest.TestCase):
    def test_manifest_market_tasks(self):
        tasks = {x['id']: x for x in harness.read_tasks()}
        self.assertTrue(tasks['RESEARCH-001']['web_search'])
        self.assertTrue(tasks['RESEARCH-001']['research_validation'])
        self.assertEqual(tasks['RESEARCH-001']['dependencies'], ['PLAN-002'])
        self.assertEqual(tasks['ASSESS-001']['dependencies'], ['RESEARCH-001'])
        self.assertIn('projects/first-game/research/steam_competitors.json', tasks['RESEARCH-001']['required_files'])

    def test_codex_search_flag_is_only_for_marked_tasks(self):
        self.assertEqual(harness.codex_command_for_task({'web_search': True}, 'W')[1:3], ['--search', 'exec'])
        self.assertEqual(harness.codex_command_for_task({}, 'W')[1], 'exec')

if __name__ == '__main__':
    unittest.main()
