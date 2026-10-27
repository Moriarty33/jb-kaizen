# Routing & Intent analysis (self-learn Phase 2.6)

Goal: make Claude understand THIS user's phrasing and pick the right skill - the dimension
the efficiency rubric (tokens/cycles/quality) does not cover. Output is maintained in the
private store under `routing/`:

- `routing/routing-map.json` - machine map consumed by `~/.claude/hooks/skill-router.py`
  (a conditional UserPromptSubmit hook that nudges toward a skill only on keyword match).
- `routing/intent-lexicon.md` - human rationale + observed phrasings + STT-mishear table.

## What to mine from sessions (in addition to the Phase 2 behavior corrections)

For every processed transcript, look for routing signal:

1. **Misroute** - the wrong skill fired for the user's intent. Symptom: user interrupts,
   says "no, I meant...", or corrects the skill chosen. Fix: remove/repair the offending
   keyword and/or tighten the competing skills' `description`.
2. **Missed route** - a skill SHOULD have fired but the model did the work manually. Symptom:
   a multi-step manual sequence that a skill already covers. Fix: add the user's phrasing as a
   keyword; if the gap is real, tighten the skill `description`.
3. **Rephrase loop** - the user repeated or reworded a request because the first phrasing was
   not understood. Each rephrase pair is a labeled training example: garbled/first form ->
   intent. Add the first form as a keyword.
4. **STT mishears** - dictation artifacts (e.g. "Solf learn" -> self-learn). Add both the
   garbled token and correction to the lexicon table AND as a keyword.
5. **New-intent candidate** - a repeated manual workflow with NO skill. Do not just add a
   keyword; flag it as a skill candidate for the normal proposal flow.

## Rules for editing the map

- Keywords are lowercased substrings matched against the whole prompt. Make them distinctive
  (prefer multi-word phrases); a keyword that fires on unrelated prompts is worse than a miss.
- Cap nudges at MAX_HINTS (3) - the hook already enforces this; keep the map from bloating.
- The hook is silent when the prompt starts with `/` (explicit command) - never add keywords
  that try to override an explicit slash command.
- Every keyword addition must cite the session that motivates it (evidence-or-it-doesn't-ship,
  same as the rest of self-learn).
- When tuning a skill `description`, snapshot the skill first (Phase 5 discipline) - the
  description IS the native auto-trigger surface, so changes there are real behavior changes.

## Verify before advancing

> **Resolve the hook, never hardcode `~/.claude/hooks/`.** On a plugin install it ships as
> `plugins/cache/*/kaizen/*/hooks/skill-router.py`; the `~/.claude/hooks/` path does not exist and the
> check silently passes over nothing. Resolve it first:
> ```bash
> SKILL_ROUTER="$(ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/skill-router.py \
>   "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/kaizen/*/hooks/skill-router.py 2>/dev/null | head -1)"
> ```
> Likewise the dangling-target audit globs `~/workspace/*/…`; read the roots from
> `registry.json -> .roots[]` instead, or project-scoped skills read as dangling.


After editing `routing-map.json`, sanity-check the hook still parses and behaves:

```bash
for p in "learn from the last sessions" "solf learn in a loop" "/self-learn status" "thanks"; do
  echo "$p ->"; echo "{\"prompt\":\"$p\"}" | python3 "$SKILL_ROUTER"; echo
done
```
Expect: self-learn hint, self-learn hint (STT variant), silence (slash), silence (no match).
Swap in your own phrasings - the map is keyed to YOUR language, including dictation mishears.

**Then audit for dangling targets** - a rule whose `skill` no longer exists on disk is a
silent misroute that nudges toward a skill nobody can invoke. Typical causes: a skill was
absorbed into another one, archived, or the rule named a skill that never existed (a
singular where the real skill is plural):

```bash
python3 - <<'EOF'
import json, os, glob
d = json.load(open(os.path.expanduser('~/.claude/self-learn/routing/routing-map.json')))
cfg = os.environ.get('CLAUDE_CONFIG_DIR') or os.path.expanduser('~/.claude')
p = os.path.join(cfg, 'skills')
sk = set(os.listdir(p)) if os.path.isdir(p) else set()
# kaizen plugin cache only - not every third-party plugin's skills
sk.update(os.path.basename(g) for g in glob.glob(os.path.join(cfg, 'plugins/cache/*/kaizen/*/skills/*')))
for g in glob.glob(os.path.expanduser('~/workspace/*/*/.claude/skills/*')) + \
         glob.glob(os.path.expanduser('~/workspace/*/.claude/skills/*')):
    sk.add(os.path.basename(g))          # project-scoped skills are legitimate targets
print('dangling:', [r['skill'] for r in d['rules'] if r['skill'] not in sk] or 'NONE')
EOF
```

Expect `NONE`. Retarget a dangling rule's keywords to the live skill that inherited the
intent rather than deleting them, then drop the dead rule - the user's phrasings are still
evidence.

## Journal

Record in the epoch journal: new keywords added (with evidence), misroutes fixed, STT
mishears captured, skill-candidate flags, and any `description` edits. Routing quality is now
a first-class metric of each run alongside token/cycle savings.
