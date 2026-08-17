#!/usr/bin/env python3
"""Fetch and normalize football fixtures for the Omatchday Omarchy plugin."""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener
from zoneinfo import ZoneInfo

CONFIG_PATH = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "omarchy" / "omatchday" / "config.json"
API_ROOT = "https://site.api.espn.com/apis/site/v2/sports/soccer"
USER_AGENT = "omatchday/0.1 (+https://github.com/brm-src/omatchday)"
MAX_RESPONSE_BYTES = 12_000_000
DEFAULT_LEAGUE = "eng.1"
DEFAULT_DAYS_BACK = 45
DEFAULT_DAYS_FORWARD = 90
WEEKDAYS = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]


class HTTPSOnlyRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.lower().startswith("https://"):
            raise ValueError("La API redirigió a una conexión no segura")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def json_out(**payload: object) -> None:
    print(json.dumps(payload, ensure_ascii=False))


def fetch_json(url: str) -> dict:
    if not url.lower().startswith("https://"):
        raise ValueError("La fuente de datos debe usar HTTPS")
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    opener = build_opener(HTTPSOnlyRedirectHandler())
    with opener.open(request, timeout=20) as response:
        data = response.read(MAX_RESPONSE_BYTES + 1)
    if len(data) > MAX_RESPONSE_BYTES:
        raise ValueError("La respuesta de la API supera el límite permitido")
    payload = json.loads(data.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("La API devolvió una respuesta inválida")
    return payload


def load_config(path: Path = CONFIG_PATH) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"No se pudo leer {path}: {error}") from error
    if not isinstance(payload, dict):
        raise ValueError("La configuración de Omatchday debe ser un objeto JSON")
    return payload


def normalize_teams(raw: object) -> list[dict[str, str]]:
    if not isinstance(raw, list):
        return []
    result: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in raw:
        if isinstance(item, str):
            team_id = item.strip()
            team = {"id": team_id, "name": team_id, "shortName": team_id, "abbreviation": team_id[:3].upper()}
        elif isinstance(item, dict):
            team_id = str(item.get("id") or "").strip()
            team = {
                "id": team_id,
                "name": str(item.get("name") or item.get("displayName") or team_id),
                "shortName": str(item.get("shortName") or item.get("name") or team_id),
                "abbreviation": str(item.get("abbreviation") or item.get("shortName") or team_id[:3]).upper(),
                "logo": str(item.get("logo") or ""),
                "color": str(item.get("color") or ""),
                "alternateColor": str(item.get("alternateColor") or ""),
            }
        else:
            continue
        if team_id and team_id not in seen:
            result.append(team)
            seen.add(team_id)
    return result


def normalize_leagues(raw: object) -> list[str]:
    if not isinstance(raw, list):
        return [DEFAULT_LEAGUE]
    result = []
    for item in raw:
        value = str(item).strip().lower()
        if value and value not in result:
            result.append(value)
    return result or [DEFAULT_LEAGUE]


def league_teams_payload(payload: dict) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    for sport in payload.get("sports", []):
        for league in sport.get("leagues", []):
            for item in league.get("teams", []):
                team = item.get("team", {}) if isinstance(item, dict) else {}
                logos = team.get("logos", [])
                logo = logos[0].get("href", "") if logos and isinstance(logos[0], dict) else str(team.get("logo") or "")
                result.append({
                    "id": str(team.get("id") or ""),
                    "name": str(team.get("displayName") or team.get("name") or ""),
                    "shortName": str(team.get("shortDisplayName") or team.get("name") or ""),
                    "abbreviation": str(team.get("abbreviation") or "").upper(),
                    "logo": logo,
                    "color": str(team.get("color") or ""),
                    "alternateColor": str(team.get("alternateColor") or ""),
                })
    return [team for team in result if team["id"]]


def teams_for_league(league: str) -> list[dict[str, str]]:
    payload = fetch_json(f"{API_ROOT}/{league}/teams")
    return league_teams_payload(payload)


def event_timestamp(event: dict) -> datetime | None:
    raw = str(event.get("date") or "")
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone()
    except ValueError:
        return None


def team_snapshot(competitor: dict) -> dict[str, object]:
    team = competitor.get("team", {})
    logos = team.get("logos", []) if isinstance(team, dict) else []
    logo = str(team.get("logo") or "") if isinstance(team, dict) else ""
    if not logo and logos and isinstance(logos[0], dict):
        logo = str(logos[0].get("href") or "")
    return {
        "id": str(team.get("id") or competitor.get("id") or ""),
        "name": str(team.get("displayName") or team.get("name") or "Equipo"),
        "shortName": str(team.get("shortDisplayName") or team.get("displayName") or "Equipo"),
        "abbreviation": str(team.get("abbreviation") or "").upper(),
        "logo": logo,
        "color": str(team.get("color") or ""),
        "alternateColor": str(team.get("alternateColor") or ""),
        "homeAway": str(competitor.get("homeAway") or ""),
        "score": str(competitor.get("score") or "—"),
        "winner": bool(competitor.get("winner", False)),
    }


def format_day(timestamp: datetime, now: datetime) -> str:
    local_date = timestamp.date()
    if local_date == now.date():
        return "HOY"
    if local_date == now.date() + timedelta(days=1):
        return "MAÑANA"
    return f"{WEEKDAYS[timestamp.weekday()]} {timestamp.day}"


def normalize_event(event: dict, league: str, selected_ids: set[str], now: datetime) -> dict | None:
    timestamp = event_timestamp(event)
    if timestamp is None:
        return None
    competitors = [team_snapshot(item) for item in event.get("competitions", [{}])[0].get("competitors", [])]
    if len(competitors) < 2 or not selected_ids.intersection({str(item["id"]) for item in competitors}):
        return None
    competition = event.get("competitions", [{}])[0]
    status = competition.get("status", {}).get("type", {})
    state = str(status.get("state") or "pre")
    completed = bool(status.get("completed", False)) or state == "post"
    venue = competition.get("venue", {})
    address = venue.get("address", {}) if isinstance(venue, dict) else {}
    return {
        "id": str(event.get("id") or ""),
        "timestamp": timestamp.isoformat(),
        "date": timestamp.date().isoformat(),
        "day": format_day(timestamp, now),
        "time": timestamp.strftime("%H:%M"),
        "state": state,
        "completed": completed,
        "status": str(status.get("shortDetail") or status.get("detail") or status.get("description") or "Programado"),
        "home": competitors[0],
        "away": competitors[1],
        "league": str(league or event.get("season", {}).get("slug") or "Fútbol"),
        "venue": str(venue.get("fullName") or "") if isinstance(venue, dict) else "",
        "city": str(address.get("city") or "") if isinstance(address, dict) else "",
        "url": f"https://www.espn.com/soccer/match/_/gameId/{event.get('id', '')}",
    }


def scoreboard_url(league: str, start: date, end: date) -> str:
    query = urlencode({"limit": "100", "dates": f"{start:%Y%m%d}-{end:%Y%m%d}"})
    return f"{API_ROOT}/{league}/scoreboard?{query}"


def collect_events(config: dict, now: datetime | None = None, fetcher=fetch_json) -> tuple[list[dict], list[str]]:
    now = now or datetime.now().astimezone()
    back = max(0, int(config.get("daysBack", DEFAULT_DAYS_BACK)))
    forward = max(1, int(config.get("daysForward", DEFAULT_DAYS_FORWARD)))
    start = now.date() - timedelta(days=back)
    end = now.date() + timedelta(days=forward)
    leagues = normalize_leagues(config.get("leagues"))
    teams = normalize_teams(config.get("teams"))
    selected_ids = {team["id"] for team in teams}
    events: dict[str, dict] = {}
    errors: list[str] = []
    if not selected_ids:
        return [], ["No hay equipos configurados"]
    for league in leagues:
        try:
            payload = fetcher(scoreboard_url(league, start, end))
            league_items = payload.get("leagues", [])
            league_label = league
            if league_items and isinstance(league_items[0], dict):
                league_label = str(league_items[0].get("abbreviation") or league_items[0].get("name") or league)
            for raw_event in payload.get("events", []):
                item = normalize_event(raw_event, league_label, selected_ids, now)
                if item:
                    events[item["id"]] = item
        except Exception as error:
            errors.append(f"{league}: {error}")
    return sorted(events.values(), key=lambda item: item["timestamp"]), errors


def write_config(config: dict, path: Path = CONFIG_PATH) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    os.chmod(path, 0o600)


def configure_interactively() -> int:
    print("OMATCHDAY · configuración inicial")
    print("Introduce códigos ESPN de ligas, por ejemplo eng.1, esp.1 o ita.1.")
    league_input = input(f"Ligas [{DEFAULT_LEAGUE}]: ").strip() or DEFAULT_LEAGUE
    leagues = normalize_leagues([piece for piece in league_input.split(",") if piece.strip()])
    selected: list[dict[str, str]] = []
    for league in leagues:
        print(f"\nBuscando equipos en {league}…")
        catalog = teams_for_league(league)
        if not catalog:
            print(f"No encontré equipos para {league}.")
            continue
        for index, team in enumerate(catalog, 1):
            print(f"{index:2}. {team['name']} ({team['abbreviation']})")
        choices = input("Números de equipos separados por coma (Enter para omitir): ").strip()
        for raw_index in choices.split(","):
            if raw_index.strip().isdigit():
                index = int(raw_index) - 1
                if 0 <= index < len(catalog):
                    selected.append(catalog[index])
    if not selected:
        print("No se guardó nada: debes escoger al menos un equipo.", file=sys.stderr)
        return 1
    config = {"leagues": leagues, "teams": normalize_teams(selected), "daysBack": DEFAULT_DAYS_BACK, "daysForward": DEFAULT_DAYS_FORWARD, "refreshMinutes": 15}
    write_config(config)
    print(f"Guardado en {CONFIG_PATH}")
    print("Reinicia el shell o ejecuta: omarchy-shell shell rescanPlugins")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Omatchday football data helper")
    parser.add_argument("--catalog", metavar="LEAGUE", help="print the team catalog for a league")
    parser.add_argument("--configure", action="store_true", help="configure teams interactively")
    parser.add_argument("--save-config", metavar="JSON", help="save a configuration object")
    args = parser.parse_args(argv)
    try:
        if args.configure:
            return configure_interactively()
        if args.save_config:
            config = json.loads(args.save_config)
            if not isinstance(config, dict):
                raise ValueError("La configuración debe ser un objeto JSON")
            config["leagues"] = normalize_leagues(config.get("leagues"))
            config["teams"] = normalize_teams(config.get("teams"))
            config["daysBack"] = max(0, int(config.get("daysBack", DEFAULT_DAYS_BACK)))
            config["daysForward"] = max(1, int(config.get("daysForward", DEFAULT_DAYS_FORWARD)))
            config["refreshMinutes"] = max(5, int(config.get("refreshMinutes", 15)))
            config["notifications"] = bool(config.get("notifications", False))
            write_config(config)
            json_out(saved=True, teams=config["teams"], notifications=config["notifications"])
            return 0
        if args.catalog:
            print(json.dumps(teams_for_league(args.catalog), ensure_ascii=False, indent=2))
            return 0
        config = load_config()
        if not config:
            json_out(error=f"Configura tus equipos con configure-omatchday.sh", events=[], teams=[], source="ESPN")
            return 0
        events, errors = collect_events(config)
        json_out(
            updated=datetime.now().astimezone().isoformat(),
            events=events,
            teams=normalize_teams(config.get("teams")),
            leagues=normalize_leagues(config.get("leagues")),
            notifications=bool(config.get("notifications", False)),
            source="ESPN",
            error=("No se pudo actualizar: " + " · ".join(errors)) if errors and not events else "",
        )
        return 0
    except (OSError, ValueError, json.JSONDecodeError, TimeoutError) as error:
        json_out(error=str(error), events=[], teams=[], source="ESPN")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
