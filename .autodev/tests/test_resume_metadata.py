"""Fault injection for trusted importer provenance and constrained recovery."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import test_autonomous as fixture
a = fixture.a

class ResumeMetadata(unittest.TestCase):
    def setUp(self):
        self.f = fixture.Coordinator('runTest')
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        self.asset = self.f.game / 'assets/example.svg.import'
        self.asset.parent.mkdir()
        self.asset.write_text('original metadata')
        a.git('add', '--', 'game/assets/example.svg.import')
        a.git('commit', '-qm', 'metadata fixture')
        self.plan = self.f.plan()
        self.task = self.plan['tasks'][0]
        self.run, self.data = a.new_run(self.task, self.f.c, self.f.p, self.plan)
        self.stage = self.run / 'game'

    def test_only_recorded_metadata_is_accepted_and_never_copied_to_source(self):
        self.f.coder(self.stage, self.run, self.data)
        before = a.snapshot(self.stage)
        metadata = self.stage / 'assets/example.svg.import'
        metadata.write_text('trusted generated metadata')
        with self.assertRaises(a.ERROR): a.static_check(self.stage, self.data, self.f.p, self.task)
        a.record_import_metadata(self.stage, before, self.data, {'log': 'fixture', 'sha256': 'digest'})
        self.assertEqual(a.run_changes(self.data, a.snapshot(self.stage), self.task, self.f.p), ['scripts/slice_main.gd'])
        with self.f.providers():
            a.qa(self.stage, self.run, self.data, self.f.c, self.f.p, self.task)
            a.integrate(self.run, self.data, self.task, self.f.c, self.f.p)
        self.assertEqual(self.asset.read_text(), 'original metadata')
        self.assertNotEqual((self.f.game / 'scripts/slice_main.gd').read_text(), 'extends Control\n')
        metadata.write_text('later unauthorized modification')
        with self.assertRaises(a.ERROR): a.static_check(self.stage, self.data, self.f.p, self.task)

    def test_importer_cannot_authorize_substantive_or_new_metadata_files(self):
        before = a.snapshot(self.stage)
        (self.stage / 'tests/smoke_test.gd').write_text('weakened test')
        with self.assertRaises(a.ERROR): a.record_import_metadata(self.stage, before, self.data, {})
        self.assertFalse(self.data.get('trusted_import_metadata'))
        (self.stage / 'tests/smoke_test.gd').write_text('extends SceneTree\n')
        (self.stage / 'new.import').write_text('unknown')
        with self.assertRaises(a.ERROR): a.record_import_metadata(self.stage, before, self.data, {})

    def test_failed_import_records_provenance_and_keeps_failure_during_retry(self):
        self.f.coder(self.stage, self.run, self.data)
        def failed(cmd, run, data, name, *args, **kwargs):
            if name.endswith('IMPORT'):
                (self.stage / 'assets/example.svg.import').write_text('generated despite editor shutdown error')
                return 0, 'ERROR: Parameter singleton is null'
            return self.f.provider(cmd, run, data, name, *args, **kwargs)
        with self.f.providers(process=failed):
            with self.assertRaises(a.ERROR): a.qa(self.stage, self.run, self.data, self.f.c, self.f.p, self.task)
        self.assertFalse(self.data['qa'][-1]['pass'])
        self.assertIn('assets/example.svg.import', self.data['trusted_import_metadata'])
        with self.f.providers(): a.qa(self.stage, self.run, self.data, self.f.c, self.f.p, self.task)
        self.assertFalse(self.data['qa_history'][0]['gates'][-1]['pass'])
        self.assertTrue(all(gate['pass'] for gate in self.data['qa']))

    def test_reconciliation_requires_unchanged_game_and_known_infrastructure(self):
        file = self.f.here / 'autonomous.py'
        file.write_text('# reviewed infrastructure fixture\n')
        a.git('add', '--', '.autodev/autonomous.py')
        a.git('commit', '-qm', 'reviewed infrastructure')
        old = self.data['source_commit']
        a.reconcile_infrastructure(self.run.name, self.f.c, self.f.p)
        recovered = a.read(self.run / 'autonomous.json')
        self.assertEqual(recovered['infrastructure_history'][0]['previous_source_commit'], old)
        self.assertEqual(recovered['source_commit'], a.git('rev-parse', 'HEAD'))
        (self.f.game / 'scripts/slice_main.gd').write_text('changed user game')
        a.git('add', '--', 'game/scripts/slice_main.gd')
        a.git('commit', '-qm', 'different game')
        with self.assertRaises(a.ERROR): a.reconcile_infrastructure(self.run.name, self.f.c, self.f.p)

    def test_model_code_ready_requires_profile_and_all_trusted_probes(self):
        def provider(cmd, *args, **kwargs):
            if '--help' in cmd: return 0, '--sandbox --json --output-last-message --output-schema'
            last = Path(cmd[cmd.index('--output-last-message') + 1])
            a.write(last, {'status': 'code_ready', 'summary': 'fixture', 'unverified_acceptance': [],
                           'tests_actually_run': [], 'verification_pending': ['trusted QA'],
                           'human_review_pending': ['physical listening']})
            return 0, '{"type":"turn.completed"}'
        config = copy.deepcopy(self.f.c)
        with patch.object(a, 'process', provider), patch.object(a, 'codex_executable', return_value=sys.executable):
            with self.assertRaises(a.ERROR): a.codex(self.stage, self.run, {}, 'fixture', config, self.f.p, 'model')
            config.update(engine_profile={'fixture': True}, trusted_handoff_probes=['save_settings', 'audio_immediate'])
            with patch.object(a.auto, 'profile_templates', return_value={}):
                self.assertTrue(a.codex(self.stage, self.run, {}, 'fixture', config, self.f.p, 'model').is_file())

    def test_import_shutdown_error_classifies_for_one_bounded_revalidation(self):
        self.assertEqual(a.classify('QA', 'IMPORT: exit=0\nERROR: Parameter singleton is null'), 'ENGINE_IMPORT')
        self.assertEqual(a.classify('QA', 'IMPORT: SCRIPT ERROR: bad code'), 'GAME_CODE')

    def test_standard_qa_cannot_override_a_model_acceptance_blocker(self):
        self.f.coder(self.stage, self.run, self.data)
        with self.f.providers(): a.qa(self.stage, self.run, self.data, self.f.c, self.f.p, self.task)
        a.write(self.run / ('coder-%d-last.txt' % self.data['attempts']), {
            'status': 'blocked', 'unverified_acceptance': ['Unverified behavior']})
        before = a.git('rev-parse', 'HEAD')
        with self.assertRaises(a.ERROR): a.integrate(self.run, self.data, self.task, self.f.c, self.f.p)
        self.assertEqual(a.git('rev-parse', 'HEAD'), before)

if __name__ == '__main__': unittest.main()
