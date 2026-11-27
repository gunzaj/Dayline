#!/usr/bin/env python3
"""Dayline's Garmin Connect helper.

This is the only part of Dayline that talks to Garmin. It wraps the unofficial
`garminconnect` library (same login the community libraries use). The app starts
this script as a subprocess, passes tokens on stdin and reads one JSON object
from stdout. Tokens never touch the disk: the Swift side keeps them in the
macOS Keychain and hands them back for every sync, and this script only ever
holds them in memory.

Commands:
    login            stdin: {"email", "password"} or {"mfa", "clientState"}
    sync [--days N]  stdin: {"tokens": "<token JSON from a previous login or sync>"}
    status           no input

Output is always a single JSON object with "ok": true|false.
"""

import argparse
import datetime as dt
import json
import sys

BUCKET_MINUTES = 15


def emit(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))
    sys.stdout.write("\n")
    sys.stdout.flush()


def read_input():
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {}


def dump_tokens(client):
    """The session as a JSON string, for the Keychain. Never written to disk."""
    return client.client.dumps()


def bucket_start(moment):
    """Floor a datetime to its 15-minute slot, as an ISO string."""
    floored = moment.replace(minute=(moment.minute // BUCKET_MINUTES) * BUCKET_MINUTES,
                             second=0, microsecond=0)
    return floored.isoformat()


def from_millis(ts):
    if ts is None:
        return None
    try:
        return dt.datetime.fromtimestamp(float(ts) / 1000.0).astimezone()
    except Exception:
        return None


def num(value):
    try:
        return int(round(float(value)))
    except Exception:
        return None


def series(raw, wanted_index=1, minimum=None):
    """Garmin returns arrays like [[timestamp, value, ...], ...].

    Garmin marks "not measured" with negative values; `minimum` drops them.
    """
    out = []
    if not isinstance(raw, list):
        return out
    for row in raw:
        if not isinstance(row, list) or len(row) <= wanted_index:
            continue
        moment = from_millis(row[0])
        v = num(row[wanted_index])
        if moment is None or v is None:
            continue
        if minimum is not None and v < minimum:
            continue
        out.append((moment, v))
    return out


def mean(values):
    return int(round(sum(values) / float(len(values))))


def safe(label, fn, warnings):
    try:
        return fn()
    except Exception as exc:  # noqa: BLE001 - the helper degrades per endpoint
        warnings.append("%s: %s" % (label, str(exc)[:200]))
        return None


def fetch(tokens, days_back=0):
    from garminconnect import Garmin

    warnings = []
    client = Garmin()
    client.login(tokens)  # inline token JSON: nothing is read from or written to disk

    today = dt.date.today()
    dates = [(today - dt.timedelta(days=i)).isoformat() for i in range(days_back, -1, -1)]
    samples = []
    daily_rows = []

    for cdate in dates:
        stats = safe("stats " + cdate, lambda: client.get_stats(cdate), warnings) or {}
        stress_data = safe("stress " + cdate, lambda: client.get_stress_data(cdate), warnings) or {}
        battery = safe("battery " + cdate, lambda: client.get_body_battery(cdate), warnings) or []
        heart = safe("heart " + cdate, lambda: client.get_heart_rates(cdate), warnings) or {}
        steps_data = safe("steps " + cdate, lambda: client.get_steps_data(cdate), warnings) or []
        sleep = safe("sleep " + cdate, lambda: client.get_sleep_data(cdate), warnings) or {}
        hrv = safe("hrv " + cdate, lambda: client.get_hrv_data(cdate), warnings) or {}

        stress_points = series(stress_data.get("stressValuesArray"), minimum=0)
        battery_points = []
        if isinstance(battery, list) and battery:
            day_battery = battery[0] if isinstance(battery[0], dict) else {}
            battery_points = series(day_battery.get("bodyBatteryValuesArray"), minimum=0)
        heart_points = series(heart.get("heartRateValuesArray"), minimum=1)

        # One sample per 15-minute slot: mean stress and heart rate, the last
        # Body Battery reading, and the steps taken in the slot.
        buckets = {}

        def bucket(key):
            stamp = buckets.get(key)
            if stamp is None:
                stamp = {"at": key, "_stress": [], "_heart": []}
                buckets[key] = stamp
            return stamp

        for moment, v in stress_points:
            bucket(bucket_start(moment))["_stress"].append(v)
        for moment, v in battery_points:
            bucket(bucket_start(moment))["bodyBattery"] = v
        for moment, v in heart_points:
            bucket(bucket_start(moment))["_heart"].append(v)

        for row in steps_data if isinstance(steps_data, list) else []:
            try:
                t = row.get("startGMT") or row.get("startTimeGMT")
                if not isinstance(t, str):
                    continue
                parsed = dt.datetime.fromisoformat(t.replace("Z", "+00:00"))
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=dt.timezone.utc)
                bucket(bucket_start(parsed.astimezone()))["steps"] = num(row.get("steps"))
            except Exception:
                continue

        for stamp in sorted(buckets.values(), key=lambda item: item["at"]):
            stress_values = stamp.pop("_stress")
            heart_values = stamp.pop("_heart")
            if stress_values:
                stamp["stress"] = mean(stress_values)
            if heart_values:
                stamp["heartRate"] = mean(heart_values)
            if len(stamp) > 1:
                samples.append(stamp)

        daily_sleep = sleep.get("dailySleepDTO") or {}
        sleep_scores = daily_sleep.get("sleepScores") or {}
        overall = sleep_scores.get("overall") or {}
        sleep_seconds = daily_sleep.get("sleepTimeSeconds")
        hrv_summary = hrv.get("hrvSummary") or {}

        daily_rows.append({
            "dayKey": cdate,
            "sleepScore": num(overall.get("value")),
            "sleepMinutes": num(sleep_seconds / 60.0) if sleep_seconds else None,
            "hrvStatus": hrv_summary.get("status"),
            "bodyBatteryWake": None,
            "restingHeartRate": num(stats.get("restingHeartRate")),
            "stressAverage": num(stats.get("averageStressLevel")),
            "bodyBatteryEnd": num(stats.get("bodyBatteryMostRecentValue")),
            "steps": num(stats.get("totalSteps")),
        })

    last_sync = None
    try:
        last_sync = client.get_sync_timestamp()
    except Exception:
        pass
    return {
        "ok": True,
        "tokens": dump_tokens(client),  # refreshed during the sync, if Garmin rotated them
        "samples": samples,
        "daily": daily_rows,
        "fetchedAt": dt.datetime.now().astimezone().isoformat(),
        "lastDeviceSync": str(last_sync) if last_sync else None,
        "warnings": warnings[:8],
    }


def cmd_login(args):
    payload = read_input()
    email = payload.get("email") or ""
    password = payload.get("password") or ""
    mfa = payload.get("mfa") or ""
    client_state = payload.get("clientState") or None

    resuming = bool(mfa and client_state)
    if not email and not resuming:
        emit({"ok": False, "error": "Enter your Garmin email in Settings.", "errorCode": "missing_email"})
        return 0
    if not password and not resuming:
        emit({"ok": False, "error": "Enter your Garmin password.", "errorCode": "missing_password"})
        return 0

    try:
        from garminconnect import Garmin
    except Exception as exc:  # noqa: BLE001
        emit({
            "ok": False,
            "error": "The Garmin helper is not installed. Run scripts/setup-garmin.sh once.",
            "errorCode": "dependency_missing",
            "detail": str(exc),
        })
        return 0

    try:
        if mfa and client_state:
            client = Garmin()
            client.resume_login(json.loads(client_state), mfa)
        else:
            client = Garmin(email, password, return_on_mfa=True)
            status, state = client.login()
            if status == "needs_mfa":
                # The state holds session cookies. It goes back to the app as an
                # opaque string and is only kept in memory there.
                emit({"ok": False, "needMFA": True, "clientState": json.dumps(state)})
                return 0
        emit({"ok": True, "tokens": dump_tokens(client), "displayName": _display_name(client)})
        return 0
    except Exception as exc:  # noqa: BLE001
        emit({"ok": False, "error": _login_error(exc), "errorCode": "login_failed"})
        return 0


def _display_name(client):
    try:
        return client.get_full_name()
    except Exception:
        return None


def _login_error(exc):
    text = str(exc)
    lowered = text.lower()
    if "mfa" in lowered or "two" in lowered or "verification" in lowered:
        return "Garmin asked for a verification code. Try again and enter the code when asked."
    if "401" in text or "unauthorized" in lowered or "credentials" in lowered:
        return "Garmin rejected the email or password."
    if "429" in text or "rate" in lowered:
        return "Garmin is rate limiting logins. Wait a few minutes and try again."
    return "Garmin login failed: " + text[:240]


def cmd_sync(args):
    payload = read_input()
    tokens = payload.get("tokens") or ""
    try:
        from garminconnect import Garmin  # noqa: F401
    except Exception as exc:  # noqa: BLE001
        emit({
            "ok": False,
            "error": "The Garmin helper is not installed. Run scripts/setup-garmin.sh once.",
            "errorCode": "dependency_missing",
            "detail": str(exc),
        })
        return 0
    if not tokens:
        emit({"ok": False, "error": "Not signed in to Garmin.", "errorCode": "no_tokens"})
        return 0

    try:
        emit(fetch(tokens, days_back=max(0, args.days)))
    except Exception as exc:  # noqa: BLE001
        emit({
            "ok": False,
            "error": "Garmin sync failed: " + str(exc)[:300],
            "errorCode": "sync_failed",
        })
    return 0


def cmd_status(args):
    try:
        import garminconnect  # noqa: F401
        emit({"ok": True, "dependency": "installed", "python": sys.version.split()[0]})
    except Exception as exc:  # noqa: BLE001
        emit({"ok": False, "dependency": "missing", "python": sys.version.split()[0],
              "error": str(exc)})
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["login", "sync", "status"])
    parser.add_argument("--days", type=int, default=0)
    args = parser.parse_args()
    if args.command == "login":
        return cmd_login(args)
    if args.command == "sync":
        return cmd_sync(args)
    return cmd_status(args)


if __name__ == "__main__":
    sys.exit(main())
