"""The two ARCHITECTURE.md diagrams: what lands where, and the life of a commit cursor."""
from svgkit import Canvas


def components(theme):
    c = Canvas(1000, 560, theme)
    c.group(20, 48, 170, 170, "Scheduler", "amber")
    c.group(220, 48, 330, 470, "~/.claude", "violet", "Claude Code")
    c.group(580, 48, 400, 470, "~/.claude/self-learn", "green", "private store, a git repo")
    c.card(36, 84, 138, 44, ("launchd plist",), accent="amber", mono=True, size=12)
    c.card(36, 148, 138, 44, ("systemd timer",), accent="amber", mono=True, size=12)
    c.card(240, 84, 290, 44, ("lib/claude-retry.sh",), accent="violet", mono=True, size=12)
    c.card(240, 158, 290, 64, ("skills/self-learn", "SKILL.md · scripts/ · references/"), accent="violet", mono=True, size=12)
    c.card(240, 252, 142, 44, ("skills/model-balance",), accent="violet", mono=True, size=11)
    c.card(388, 252, 142, 44, ("skills/loop-audit",), accent="violet", mono=True, size=11)
    c.card(240, 326, 290, 44, ("hooks/skill-router.py",), accent="violet", mono=True, size=12)
    c.card(240, 400, 290, 44, ("settings.json", "hooks.UserPromptSubmit → skill-router.py"), accent="violet", mono=True, size=12)
    c.card(240, 460, 290, 44, ("night-guard-settings.json", "deny-list for the nightly run"), accent="violet", mono=True, size=12)
    c.card(600, 84, 360, 50, ("scripts/nightly-run.sh", "nightly-prompt.txt · logs/ (gitignored)"), accent="green", tone="tint", mono=True, size=12)
    grid = ["registry.json", "state.json", "pagination.json", "versions.json", "snapshots/<id>/<v>/", "memory-snapshots/",
            "journal/", "config.json", "routing-map.json", "intent-lexicon.md", "pending/ (gitignored)"]
    for i, name in enumerate(grid):
        x = 600 + (i % 2) * 186; y = 158 + (i // 2) * 52
        c.card(x, y, 174, 40, (name,), accent="green", mono=True, size=11.5)
    # scheduler -> nightly-run.sh (over the top), nightly-run.sh -> retry lib -> skill -> store
    c.edge([(174, 106), (200, 106), (200, 24), (592, 24), (592, 92), (600, 92)], r=14)
    c.edge([(174, 170), (200, 170), (200, 24)], r=14, arrow=False)
    c.path("M600,116 L534,116")
    c.path("M385,128 L385,156")
    c.curve((530, 190), (600, 178)); c.edge_label(578, 168, "reads / writes", accent="green")
    c.edge([(385, 222), (385, 238), (309, 238), (309, 250)], dashed=True, r=10); c.edge_label(347, 238, "Phase 2.8", accent="violet")
    c.curve((530, 348), (600, 386)); c.edge_label(565, 362, "reads", accent="violet")
    c.path("M385,400 L385,372")
    return c.render()


def cursor_states(theme):
    c = Canvas(1000, 300, theme)
    strong = c.t["edge_strong"]
    c.parts.append(f'<circle cx="60" cy="150" r="7" fill="{strong}"/>')
    c.path("M70,150 L123,150"); c.text(96, 132, "repo registered", size=11, color=c.t["muted"])
    for cx, name, accent in [(200, "Unread", "slate"), (440, "Pending", "amber"), (680, "Analyzed", "violet"), (900, "Advanced", "green")]:
        c.pill(cx, 150, name, accent, w=150, h=44, size=14, weight=700)
    c.path("M277,150 L363,150"); c.text(320, 102, "paginate.sh · oldest-first per branch,", size=11, color=c.t["muted"]); c.text(320, 117, "global seen[] dedups shared history", size=11, color=c.t["muted"])
    c.path("M517,150 L603,150"); c.text(560, 117, "Phase 4 completes", size=11, color=c.t["muted"])
    c.path("M757,150 L823,150"); c.text(790, 102, "advance.sh moves lastHash,", size=11, color=c.t["muted"]); c.text(790, 117, "extends seen[]", size=11, color=c.t["muted"])
    c.edge([(900, 172), (900, 240), (200, 240), (200, 174)], r=18); c.edge_label(550, 240, "new commits land", accent="green")
    c.edge([(440, 128), (440, 64), (200, 64), (200, 126)], r=18, dashed=True)
    c.edge_label(320, 64, "run dies: the pending file stays, the next run re-reads the same batch", accent="amber")
    return c.render()


DIAGRAMS = {
    "components": (components, ["en"]),
    "cursor-states": (cursor_states, ["en"]),
}
