"""Structural evidence gate for limited-scope Steam market research (v0.3).

This does NOT fact-check the claims or certify live availability of URLs.
It requires a recorded Codex web search tool event and traceable Steam app URLs.
"""
from __future__ import annotations

import json
import re
from datetime import date
from pathlib import Path
from urllib.parse import urlsplit

REQUIRED_CANDIDATES = {"C01", "C04", "C08"}
MIN_COMPARABLES = 3
ID_PATTERN = re.compile(r"^[1-9][0-9]{0,11}$")


def has_search_event(log_text: str) -> bool:
    for line in log_text.splitlines():
        try:
            event = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            continue
        # Account for CLI revisions: tool entries may be on either item or event.
        item = event.get("item") if isinstance(event, dict) else None
        values = [event.get("type"), item.get("type") if isinstance(item, dict) else None]
        if any(isinstance(v, str) and "web_search" in v for v in values):
            return True
        if isinstance(item, dict) and item.get("name") == "web_search":
            return True
    return False


def valid_steam_url(url: str, app_id: int) -> bool:
    if not isinstance(url, str):
        return False
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != "store.steampowered.com":
        return False
    if parsed.username or parsed.password or parsed.port:
        return False
    match = re.fullmatch(r"/app/([1-9][0-9]{0,11})(?:/[^?#]*)?", parsed.path)
    return bool(match and int(match.group(1)) == app_id)


def check_json(data: object) -> tuple[bool, str]:
    if not isinstance(data, dict):
        return False, "Research JSON root is not an object"
    if data.get("source_policy") != "steam_links_are_leads_not_verified_sales":
        return False, "source_policy must clarify that links are not verified sales evidence"
    if not isinstance(data.get("research_date"), str):
        return False, "Missing research_date"
    try:
        date.fromisoformat(data["research_date"])
    except ValueError:
        return False, "research_date must be YYYY-MM-DD"
    candidates = data.get("candidates")
    if not isinstance(candidates, list) or {c.get("id") for c in candidates if isinstance(c, dict)} != REQUIRED_CANDIDATES or len(candidates) != 3:
        return False, "Expected exactly C01, C04, C08"
    for candidate in candidates:
        cid = candidate["id"]
        status = candidate.get("evidence_status")
        if status not in {"enough_links_for_manual_review", "insufficient_evidence"}:
            return False, f"{cid}: invalid evidence_status"
        comps = candidate.get("comparables")
        if not isinstance(comps, list):
            return False, f"{cid}: comparables must be an array"
        seen_ids = set()
        for comp in comps:
            if not isinstance(comp, dict):
                return False, f"{cid}: invalid comparison entry"
            appid = comp.get("app_id")
            if isinstance(appid, bool) or not isinstance(appid, int) or not ID_PATTERN.fullmatch(str(appid)):
                return False, f"{cid}: invalid Steam app ID"
            if appid in seen_ids:
                return False, f"{cid}: duplicate app ID {appid}"
            seen_ids.add(appid)
            if not valid_steam_url(comp.get("url"), appid):
                return False, f"{cid}: invalid Steam link or inconsistent app ID"
            for key in ("title", "overlap", "evidence_note"):
                if not isinstance(comp.get(key), str) or len(comp[key].strip()) < 5:
                    return False, f"{cid}: missing {key}"
            if comp.get("claim_status") not in {"observed_in_search", "unconfirmed"}:
                return False, f"{cid}: claim_status missing or invalid"
        if status == "enough_links_for_manual_review" and len(comps) < MIN_COMPARABLES:
            return False, f"{cid}: too few comparable games ({len(comps)} < {MIN_COMPARABLES})"
        if status == "insufficient_evidence":
            gaps = candidate.get("evidence_gaps")
            if not isinstance(gaps, list) or not any(isinstance(x, str) and x.strip() for x in gaps):
                return False, f"{cid}: missing evidence_gaps for insufficient evidence"
    return True, "Steam app URL format and JSON evidence schema passed (not factual verification)"


def validate_research(workspace: Path, task: dict, log_text: str) -> tuple[bool, str]:
    if not has_search_event(log_text):
        return False, "No Codex web_search event in log; research cannot be marked complete"
    rel = "projects/first-game/research/steam_competitors.json"
    if rel not in task.get("required_files", []):
        return False, "Research task is missing required structured evidence artifact"
    file = workspace / rel
    try:
        data = json.loads(file.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return False, f"Research evidence JSON unreadable: {exc}"
    return check_json(data)
