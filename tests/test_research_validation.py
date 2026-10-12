import json
import tempfile
import unittest
from pathlib import Path

from research_validation import check_json, has_search_event, valid_steam_url, validate_research


def fixture():
    return {
        "source_policy": "steam_links_are_leads_not_verified_sales",
        "research_date": "2026-10-12",
        "candidates": [
            {
                "id": cid,
                "evidence_status": "enough_links_for_manual_review",
                "comparables": [
                    {"app_id": num, "url": f"https://store.steampowered.com/app/{num}/Some_Game/", "title": "Example Game", "overlap": "Some common mechanic", "evidence_note": "Observed similar features in description", "claim_status": "observed_in_search"}
                    for num in range(10000 + i * 10, 10003 + i * 10)
                ],
            }
            for i, cid in enumerate(("C01", "C04", "C08"))
        ],
    }

class ResearchValidationTests(unittest.TestCase):
    def test_valid_evidence_schema(self):
        self.assertTrue(check_json(fixture())[0])

    def test_duplicate_ids_rejected(self):
        data = fixture()
        data['candidates'][0]['comparables'][1]['app_id'] = data['candidates'][0]['comparables'][0]['app_id']
        self.assertFalse(check_json(data)[0])

    def test_fake_domain_rejected(self):
        self.assertFalse(valid_steam_url('https://store.steampowered.com.attacker.tld/app/111/', 111))
        self.assertFalse(valid_steam_url('http://store.steampowered.com/app/111/', 111))
        self.assertTrue(valid_steam_url('https://store.steampowered.com/app/111/Title/', 111))

    def test_shortage_must_be_explicit(self):
        data = fixture()
        target = data['candidates'][0]
        target['comparables'] = []
        self.assertFalse(check_json(data)[0])
        target['evidence_status'] = 'insufficient_evidence'
        target['evidence_gaps'] = ['Could not establish comparable Steam title pages']
        self.assertTrue(check_json(data)[0])

    def test_valid_short_steam_title(self):
        data = fixture()
        data['candidates'][0]['comparables'][0]['title'] = 'VOI'
        self.assertTrue(check_json(data)[0])
        data['candidates'][0]['comparables'][0]['title'] = '  '
        self.assertFalse(check_json(data)[0])

    def test_search_event_required(self):
        self.assertTrue(has_search_event(json.dumps({'type':'item.completed', 'item':{'type':'web_search_call'}})))
        self.assertFalse(has_search_event(json.dumps({'type':'item.completed', 'item':{'type':'agent_message'}})))
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            file = ws/'projects/first-game/research/steam_competitors.json'
            file.parent.mkdir(parents=True)
            file.write_text(json.dumps(fixture()), encoding='utf-8')
            task={'required_files':['projects/first-game/research/steam_competitors.json']}
            self.assertFalse(validate_research(ws, task, '{}')[0])
            self.assertTrue(validate_research(ws, task, json.dumps({'item':{'type':'web_search_call'}}))[0])

if __name__ == '__main__':
    unittest.main()
