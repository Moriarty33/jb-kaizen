#!/usr/bin/env python3
"""skill-router - conditional UserPromptSubmit hook.

Reads the routing map maintained by the self-learn skill (Phase 2.6) and, when the
user's prompt contains one of the learned keywords, prints a one-line nudge toward
the matching skill. Claude Code appends hook stdout to the model's context, so the
nudge costs ~0 tokens on a miss (nothing is printed) and one short line on a hit.

Behaviour:
  - silent when the prompt starts with "/" (an explicit slash command wins);
  - silent when nothing matches;
  - at most MAX_HINTS hints, in map order, one per skill;
  - keywords are lowercased substrings matched against the whole prompt, so the map
    can hold the user's real phrasings in any language plus speech-to-text mishears.

Map location: $SELF_LEARN_HOME/routing/routing-map.json
              (default ~/.claude/self-learn/routing/routing-map.json)
Map shape:    {"version": 2, "rules": [{"skill": "db", "hint": "...", "keywords": ["..."]}]}

Never raises: any error (missing map, bad JSON, odd stdin) degrades to silence so a
broken map can never block a prompt.
"""
import json
import os
import sys

MAX_HINTS = 3


def load_map():
    home = os.environ.get("SELF_LEARN_HOME") or os.path.join(
        os.path.expanduser("~"), ".claude", "self-learn"
    )
    path = os.path.join(home, "routing", "routing-map.json")
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    rules = data.get("rules") if isinstance(data, dict) else None
    return rules if isinstance(rules, list) else []


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    prompt = payload.get("prompt") if isinstance(payload, dict) else None
    if not isinstance(prompt, str):
        return
    text = prompt.strip()
    if not text or text.startswith("/"):
        return
    lowered = text.lower()

    try:
        rules = load_map()
    except Exception:
        return

    hints = []
    seen = set()
    for rule in rules:
        if not isinstance(rule, dict):
            continue
        skill = rule.get("skill")
        if not skill or skill in seen:
            continue
        keywords = rule.get("keywords") or []
        if any(isinstance(k, str) and k and k.lower() in lowered for k in keywords):
            hint = rule.get("hint") or f"consider /{skill}"
            hints.append(f"- {hint}")
            seen.add(skill)
            if len(hints) >= MAX_HINTS:
                break

    if hints:
        sys.stdout.write("Routing hint (learned from your past sessions):\n" + "\n".join(hints) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
