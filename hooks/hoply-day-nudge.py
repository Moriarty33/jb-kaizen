#!/usr/bin/env python3
"""hoply-day-nudge - offer the Hoply day review once per workday after 17:15 (Europe/Kyiv).

Hook mode (SessionStart / UserPromptSubmit): prints one JSON object - a visible
systemMessage plus additionalContext asking Claude to offer the review - and writes
the `offered` stamp. Silent otherwise.

Channel mode (`--channel notified`, used by the OS reminder): exits 0 and prints the
command when a notification is due (weekday, 17:15-21:00, no stamp), writing the
`notified` stamp; exits 1 otherwise.

Fires only when all hold: Hoply is connected (config `hoply.connected`, set by browser
sign-in, or the CI token file exists), config `hoply.reminder` is not false, it is Mon-Fri at or after `hoply.time` in `hoply.timezone`, and today carries
neither this channel's stamp nor `done` (written by the hoply-day skill).

Stamps: $SELF_LEARN_HOME/hoply-day/<YYYY-MM-DD>.<offered|notified|done>.
Never raises and never touches the network: any error degrades to silence.
"""
import json
import os
import sys
from datetime import datetime, timezone

DEFAULT_TIME = "17:15"
DEFAULT_TZ = "Europe/Kyiv"
NOTIFY_UNTIL = "21:00"
CHANNELS = ("offered", "notified")


def store_home():
    claude = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    return os.environ.get("SELF_LEARN_HOME") or os.path.join(claude, "self-learn")


def token_path():
    base = os.environ.get("HOPLY_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".config", "hoply")
    return os.path.join(base, "token")


def load_settings():
    try:
        with open(os.path.join(store_home(), "config.json"), encoding="utf-8") as fh:
            data = json.load(fh)
        hoply = data.get("hoply") if isinstance(data, dict) else None
        return hoply if isinstance(hoply, dict) else {}
    except Exception:
        return {}


def zone(name):
    from zoneinfo import ZoneInfo

    for candidate in (name, "Europe/Kiev" if name == DEFAULT_TZ else None):
        if not candidate:
            continue
        try:
            return ZoneInfo(candidate)
        except Exception:
            continue
    raise ValueError("unknown timezone")


def now_in(tz):
    fake = os.environ.get("KAIZEN_NOW") if os.environ.get("KAIZEN_TEST_MODE") == "1" else None
    if fake:
        return datetime.fromisoformat(fake).astimezone(tz)
    return datetime.now(timezone.utc).astimezone(tz)


def minutes(hhmm):
    hour, minute = hhmm.split(":")
    return int(hour) * 60 + int(minute)


def stamp_dir():
    return os.path.join(store_home(), "hoply-day")


def has_stamp(day, kind):
    return os.path.exists(os.path.join(stamp_dir(), f"{day}.{kind}"))


def write_stamp(day, kind):
    folder = stamp_dir()
    os.makedirs(folder, exist_ok=True)
    for name in os.listdir(folder):
        if not name.startswith(day):
            os.remove(os.path.join(folder, name))
    with open(os.path.join(folder, f"{day}.{kind}"), "w", encoding="utf-8") as fh:
        fh.write("")


def due(channel, settings):
    connected = settings.get("connected") is True or os.path.isfile(token_path())
    if settings.get("reminder") is False or not connected:
        return None
    local = now_in(zone(str(settings.get("timezone") or DEFAULT_TZ)))
    if local.isoweekday() > 5:
        return None
    current = local.hour * 60 + local.minute
    if current < minutes(str(settings.get("time") or DEFAULT_TIME)):
        return None
    if channel == "notified" and current >= minutes(NOTIFY_UNTIL):
        return None
    day = local.strftime("%Y-%m-%d")
    if has_stamp(day, "done") or has_stamp(day, channel):
        return None
    return day


def command_name(argv):
    return "/kaizen:hoply-day" if "--plugin" in argv else "/hoply-day"


def hook(argv):
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    event = payload.get("hook_event_name") or "UserPromptSubmit"
    prompt = payload.get("prompt")
    if isinstance(prompt, str) and "hoply-day" in prompt:
        return
    day = due("offered", load_settings())
    if not day:
        return
    command = command_name(argv)
    write_stamp(day, "offered")
    sys.stdout.write(json.dumps({
        "systemMessage": f"Hoply: your day is ready to review - type {command}",
        "hookSpecificOutput": {
            "hookEventName": event,
            "additionalContext": (
                f"It is past the end of the workday. At the end of your next answer, offer once to review "
                f"today's time in Hoply with {command}. Run it only if the user says yes."
            ),
        },
    }) + "\n")


def channel(argv):
    day = due("notified", load_settings())
    if not day:
        return 1
    write_stamp(day, "notified")
    sys.stdout.write(command_name(argv) + "\n")
    return 0


def main():
    argv = sys.argv[1:]
    if "--channel" in argv:
        try:
            return channel(argv)
        except Exception:
            return 1
    try:
        hook(argv)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
