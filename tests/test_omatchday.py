import json
import unittest
from datetime import datetime, timezone
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import omatchday


class OmatchdayTests(unittest.TestCase):
    def test_scoreboard_url_uses_date_range(self):
        url = omatchday.scoreboard_url(
            "eng.1",
            datetime(2026, 8, 1, tzinfo=timezone.utc).date(),
            datetime(2026, 8, 31, tzinfo=timezone.utc).date(),
        )
        self.assertIn("soccer/eng.1/scoreboard", url)
        self.assertIn("dates=20260801-20260831", url)

    def test_normalize_event_keeps_selected_fixture(self):
        raw = {
            "id": "123",
            "date": "2026-08-21T19:00Z",
            "season": {"slug": "2026-27-english-premier-league"},
            "competitions": [{
                "status": {"type": {"state": "pre", "completed": False, "shortDetail": "Fri, Aug 21 at 15:00"}},
                "venue": {"fullName": "Emirates Stadium", "address": {"city": "London"}},
                "competitors": [
                    {"id": "359", "homeAway": "home", "team": {"id": "359", "displayName": "Arsenal", "abbreviation": "ARS"}, "score": "0"},
                    {"id": "388", "homeAway": "away", "team": {"id": "388", "displayName": "Coventry City", "abbreviation": "COV"}, "score": "0"},
                ],
            }],
        }
        result = omatchday.normalize_event(raw, "eng.1", {"359"}, datetime(2026, 8, 17, tzinfo=timezone.utc))
        self.assertIsNotNone(result)
        self.assertEqual(result["home"]["name"], "Arsenal")
        self.assertEqual(result["away"]["abbreviation"], "COV")
        self.assertFalse(result["completed"])

    def test_collect_events_deduplicates_across_leagues(self):
        payload = {"events": []}
        calls = []

        def fetcher(url):
            calls.append(url)
            return payload

        events, errors = omatchday.collect_events(
            {"leagues": ["eng.1", "eng.1"], "teams": [{"id": "359"}]},
            now=datetime(2026, 8, 17, tzinfo=timezone.utc),
            fetcher=fetcher,
        )
        self.assertEqual(events, [])
        self.assertEqual(errors, [])
        self.assertEqual(len(calls), 1)

    def test_empty_config_reports_missing_teams(self):
        events, errors = omatchday.collect_events({}, now=datetime(2026, 8, 17, tzinfo=timezone.utc), fetcher=lambda _: {})
        self.assertEqual(events, [])
        self.assertEqual(errors, ["No hay equipos configurados"])


if __name__ == "__main__":
    unittest.main()
