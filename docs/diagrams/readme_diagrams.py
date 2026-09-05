"""The four README diagrams, in English and Ukrainian. Coordinates are explicit on purpose:
these are designed pictures, not auto-layouts."""
from svgkit import Canvas, Sequence

T = {
    "en": dict(
        ev="Evidence", ev_sub="cursors only move forward",
        ev_cards=[("git commits", "oldest → newest, per branch"), ("PR review comments", "human > bot"),
                  ("session transcripts", "incl. nested subagents"), ("per-project memory", "feedback · project · reference")],
        eng="Self-learn engine", eng_sub="one headless turn",
        ingest=("ingest", "two-pass mining"), routing=("routing & intent",), distill=("memory distillation",),
        verify=("propose → verify", "2-of-3 majority · ≤45 agents"), apply=("snapshot → apply", "→ journal"),
        out="What changes",
        out_cards=[("~/.claude/skills/*",), ("~/.claude/agents/*",), ("routing-map.json", "→ UserPromptSubmit hook"), ("journal/<epoch>.md",)],
        next_epoch="next epoch reads",
        parts=[("T", 105, "scheduler\nlaunchd · systemd", "amber"), ("N", 245, "nightly-run.sh", "sky"), ("R", 380, "claude-retry.sh", "sky"),
               ("C", 540, "claude -p (headless)", "violet"), ("S", 765, "private store\n~/.claude/self-learn", "green"), ("G", 920, "private remote", "slate")],
        msgs=[("T", "N", "03:07 local"), ("N", "N", "cd $WORKSPACE (refuses $HOME)"),
              ("N", "R", "prompt + --model + --max-budget-usd\n+ deny-list settings"),
              "loop", ("R", "C", "the whole pipeline in ONE turn"),
              ("C", "S", "Phase 0 · orient: epoch, cursors,\nlearned patterns"), ("C", "S", "Phase 1 · paginate commits + PRs\n→ pending/"),
              ("C", "C", "Phase 2 · mine sessions:\ncorrections, then tool failures"), ("C", "S", "2.6 routing · 2.7 memory compaction\n· 2.8 model balance"),
              ("C", "S", "Phase 3.5 · checkpoint\nEPOCH.partial.md"), ("C", "C", "Phase 4 · Workflow: propose →\n3 verifiers per proposal"),
              ("C", "S", "Phase 5 · snapshot + edit,\nadvance cursors, bump epoch"), ("C", "S", "Phase 6 · journal/EPOCH-DATE.md"),
              ("C", "G", "sync.sh: pull --rebase, commit, push"), ("C", "R", "exit 0", True), "endloop",
              ("R", "N", "RETRY-WRAPPER: OK after n attempt(s)", True), ("N", "N", "COMPLETION OK only if\ntoday's journal exists")],
        loop="loop · up to 3 attempts, 4h wall-clock each",
        g1="Two-phase cursors", g2="Snapshot before edit", g3="Unattended guardrails",
        paginate=("paginate → pending/*.json",), analysis=("analysis",),
        ok=("succeeded", "advance.sh moves", "the cursors"), crash=("crashed", "next run re-reads", "the SAME batch"),
        s1=("snapshot.sh <id> bump",), s2=("snapshots/<id>/<version>/",), s3=("edit the live file",), rollback="rollback",
        guards=[("deny-list settings", "no ~/Documents, ~/.ssh, rm -rf, force-push"), ("--max-budget-usd", "a hard dollar ceiling per run"),
                ("45-agent ceiling", "enforced by a counter in the script"), ("4h wall-clock per attempt", "process-group kill on timeout"),
                ("propose by default", "gated changes wait in the journal")],
        fb=("feedback memory", "“open PR reviews as pending”"), q=("does the owning skill", "already enforce it?"),
        encoded="ENCODED", partial="PARTIAL / MISSING", cross="CROSS-CUTTING",
        learn=("Phase 4 learning", "minimal edit to the skill"), cm=("global CLAUDE.md", "once"), ar=("archive + one-line pointer", "MEMORY.md gets shorter"),
    ),
    "uk": dict(
        ev="Докази", ev_sub="курсори рухаються лише вперед",
        ev_cards=[("git-коміти", "старі → нові, по гілках"), ("коментарі PR-рев'ю", "люди > боти"),
                  ("транскрипти сесій", "разом із сабагентами"), ("memory проєктів", "feedback · project · reference")],
        eng="Двигун self-learn", eng_sub="один headless-хід",
        ingest=("інжест", "два проходи"), routing=("роутинг та інтент",), distill=("дистиляція memory",),
        verify=("propose → verify", "2-з-3 · ≤45 агентів"), apply=("снапшот", "правка · журнал"),
        out="Що змінюється",
        out_cards=[("~/.claude/skills/*",), ("~/.claude/agents/*",), ("routing-map.json", "→ хук UserPromptSubmit"), ("journal/<epoch>.md",)],
        next_epoch="наступна епоха читає",
        parts=[("T", 105, "планувальник\nlaunchd · systemd", "amber"), ("N", 245, "nightly-run.sh", "sky"), ("R", 380, "claude-retry.sh", "sky"),
               ("C", 540, "claude -p (headless)", "violet"), ("S", 765, "приватне сховище\n~/.claude/self-learn", "green"), ("G", 920, "приватний remote", "slate")],
        msgs=[("T", "N", "03:07 за локальним часом"), ("N", "N", "cd $WORKSPACE (ніколи $HOME)"),
              ("N", "R", "промпт + --model + --max-budget-usd\n+ deny-list"),
              "loop", ("R", "C", "увесь пайплайн в ОДНОМУ ході"),
              ("C", "S", "фаза 0 · епоха, курсори,\nlearned patterns"), ("C", "S", "фаза 1 · коміти + PR\n→ pending/"),
              ("C", "C", "фаза 2 · сесії: виправлення,\nпотім падіння tool calls"), ("C", "S", "2.6 роутинг · 2.7 компакція memory\n· 2.8 баланс моделей"),
              ("C", "S", "3.5 · чекпоінт\nEPOCH.partial.md"), ("C", "C", "фаза 4 · Workflow: propose →\n3 верифікатори на пропозицію"),
              ("C", "S", "фаза 5 · снапшот + правка,\nкурсори вперед, епоха++"), ("C", "S", "фаза 6 · journal/EPOCH-DATE.md"),
              ("C", "G", "sync.sh: pull --rebase, commit, push"), ("C", "R", "exit 0", True), "endloop",
              ("R", "N", "RETRY-WRAPPER: OK після n спроб", True), ("N", "N", "COMPLETION OK лише якщо є\nсьогоднішній журнал")],
        loop="loop · до 3 спроб, по 4 год кожна",
    ),
}


def how_it_works(theme, lang):
    L = T[lang]; c = Canvas(1000, 470, theme)
    c.group(20, 28, 230, 414, L["ev"], "sky", L["ev_sub"])
    c.group(270, 28, 490, 414, L["eng"], "violet", L["eng_sub"])
    c.group(780, 28, 200, 414, L["out"], "green")
    ys = [70, 160, 250, 340]
    for y, lines in zip(ys, L["ev_cards"]):
        c.card(37, y, 196, 62, lines, accent="sky")
    c.card(292, 205, 124, 64, L["ingest"], accent="violet")
    c.card(440, 66, 160, 52, L["routing"], accent="violet")
    c.card(440, 205, 160, 64, L["verify"], accent="violet")
    c.card(440, 352, 160, 52, L["distill"], accent="violet")
    c.card(624, 205, 120, 64, L["apply"], accent="violet", tone="tint")
    for y, lines in zip(ys, L["out_cards"]):
        c.card(796, y, 168, 56, lines, accent="green", mono=True, size=12)
    # evidence -> ingest (fan-in), ingest -> the three passes, passes -> apply, apply -> outputs
    for y, ty in zip([101, 191, 281, 371], [216, 230, 244, 258]):
        c.curve((233, y), (292, ty))
    c.curve((416, 237), (440, 92)); c.path("M416,237 L440,237"); c.curve((416, 237), (440, 378))
    c.path("M520,352 L520,270")
    c.edge([(600, 92), (612, 92), (612, 227), (624, 227)])
    c.path("M600,237 L624,247")
    for y in [98, 188, 278, 368]:
        c.curve((744, 237), (796, y))
    c.edge([(880, 396), (880, 424), (354, 424), (354, 270)], dashed=True, r=16)
    c.edge_label(617, 424, L["next_epoch"], accent="violet")
    return c.render()


def nightly_run(theme, lang):
    L = T[lang]; c = Canvas(1000, 900, theme)
    seq = Sequence(c, L["parts"], top=26, row=32, row2=46)
    loop_y = None
    for m in L["msgs"]:
        if m == "loop":
            loop_y = seq.loop_start(); continue
        if m == "endloop":
            seq.loop_end(loop_y, 330, 985, L["loop"]); continue
        a, b, label = m[0], m[1], m[2]
        seq.msg(a, b, label, dashed=len(m) > 3)
    seq.lifelines(seq.y + 4)
    c.h = seq.y + 22
    return c.render()


def guarantees(theme, lang):
    L = T[lang]; c = Canvas(1000, 350, theme)
    c.group(20, 30, 308, 290, L["g1"], "sky")
    c.group(346, 30, 308, 290, L["g2"], "violet")
    c.group(672, 30, 308, 290, L["g3"], "amber")
    # two-phase cursors
    c.card(60, 64, 228, 46, L["paginate"], accent="sky", mono=True, size=12)
    c.card(114, 138, 120, 42, L["analysis"], accent="sky")
    c.card(40, 218, 132, 74, L["ok"], accent="green", tone="tint", size=12)
    c.card(186, 218, 132, 74, L["crash"], accent="amber", tone="tint", size=12)
    c.path("M174,110 L174,136")
    c.curve((174, 180), (106, 218), axis="v"); c.curve((174, 180), (252, 218), axis="v")
    # snapshot before edit
    c.card(390, 64, 200, 46, L["s1"], accent="violet", mono=True, size=12)
    c.card(390, 138, 200, 46, L["s2"], accent="violet", mono=True, size=12)
    c.card(390, 218, 200, 46, L["s3"], accent="violet")
    c.path("M490,110 L490,136"); c.path("M490,184 L490,216")
    c.edge([(590, 241), (618, 241), (618, 161), (592, 161)], dashed=True, r=10)
    c.rotated_text(636, 201, L["rollback"], color=c.accent("violet")[0])
    # guardrails
    for i, lines in enumerate(L["guards"]):
        c.card(690, 60 + i * 52, 272, 44, lines, accent="amber", size=12)
    return c.render()


def feedback_loop(theme, lang):
    L = T[lang]; c = Canvas(1000, 310, theme)
    c.card(24, 124, 210, 66, L["fb"], accent="sky")
    c.diamond(380, 157, 230, 118, L["q"], "slate")
    c.card(560, 128, 190, 58, L["learn"], accent="violet")
    c.card(560, 224, 190, 54, L["cm"], accent="amber")
    c.card(784, 124, 200, 66, L["ar"], accent="green", tone="tint")
    c.path("M234,157 L263,157")
    c.path("M495,157 L558,157"); c.edge_label(527, 114, L["partial"], accent="violet")
    c.edge([(380, 216), (380, 251), (558, 251)], r=16); c.edge_label(470, 251, L["cross"], accent="amber")
    c.edge([(380, 98), (380, 60), (884, 60), (884, 122)], r=16); c.edge_label(632, 60, L["encoded"], accent="green")
    c.path("M750,157 L782,157")
    c.edge([(750, 251), (884, 251), (884, 192)], r=16)
    return c.render()


DIAGRAMS = {
    "how-it-works": (how_it_works, ["en", "uk"]),
    "nightly-run": (nightly_run, ["en", "uk"]),
    "guarantees": (guarantees, ["en"]),
    "feedback-loop": (feedback_loop, ["en"]),
}
