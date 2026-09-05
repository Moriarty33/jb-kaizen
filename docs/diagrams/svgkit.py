"""Tiny SVG kit for the JB Kaizen diagrams: groups, cards, pills, diamonds, edges and a
sequence-diagram helper. One palette family with the banner (slate + sky / violet / green /
amber), rendered once per theme so the README can switch with <picture>."""
from xml.sax.saxutils import escape

FONT = "Inter, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
MONO = "'JetBrains Mono', 'SF Mono', Menlo, Consolas, monospace"

THEMES = {
    "light": dict(
        bg="#ffffff", panel="#f8fafc", border="#e2e8f0", text="#0f172a", muted="#64748b",
        node="#ffffff", node_stroke="#cbd5e1", edge="#94a3b8", edge_strong="#475569",
        shadow=("#0f172a", 0.10), lifeline="#cbd5e1",
        accents={"sky": ("#0284c7", "#e0f2fe"), "violet": ("#7c3aed", "#ede9fe"),
                 "green": ("#15803d", "#dcfce7"), "amber": ("#b45309", "#fef3c7"),
                 "rose": ("#be123c", "#ffe4e6"), "slate": ("#475569", "#f1f5f9")},
    ),
    "dark": dict(
        bg="#0b1020", panel="#111827", border="#1e293b", text="#f1f5f9", muted="#94a3b8",
        node="#1e293b", node_stroke="#334155", edge="#64748b", edge_strong="#94a3b8",
        shadow=("#000000", 0.45), lifeline="#334155",
        accents={"sky": ("#7dd3fc", "#0c3d5e"), "violet": ("#c4b5fd", "#33255f"),
                 "green": ("#86efac", "#14432a"), "amber": ("#fcd34d", "#5a3a10"),
                 "rose": ("#fda4af", "#6b1330"), "slate": ("#cbd5e1", "#293548")},
    ),
}


def text_width(s, size):
    """Rough Inter width: enough to size pills and chips with margin to spare."""
    return len(s) * size * 0.56


def rounded_path(pts, r=12):
    """Polyline through pts with rounded corners (quadratic curves at every inner point)."""
    if len(pts) == 2:
        return f"M{pts[0][0]:.1f},{pts[0][1]:.1f} L{pts[1][0]:.1f},{pts[1][1]:.1f}"
    d = [f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"]
    for i in range(1, len(pts) - 1):
        (x0, y0), (x1, y1), (x2, y2) = pts[i - 1], pts[i], pts[i + 1]
        d_in = max(abs(x1 - x0), abs(y1 - y0)); d_out = max(abs(x2 - x1), abs(y2 - y1))
        rr = min(r, d_in / 2, d_out / 2)
        ax = x1 - rr * (1 if x1 > x0 else -1 if x1 < x0 else 0); ay = y1 - rr * (1 if y1 > y0 else -1 if y1 < y0 else 0)
        bx = x1 + rr * (1 if x2 > x1 else -1 if x2 < x1 else 0); by = y1 + rr * (1 if y2 > y1 else -1 if y2 < y1 else 0)
        d.append(f"L{ax:.1f},{ay:.1f} Q{x1:.1f},{y1:.1f} {bx:.1f},{by:.1f}")
    d.append(f"L{pts[-1][0]:.1f},{pts[-1][1]:.1f}")
    return " ".join(d)


def scurve(p0, p1, axis="h"):
    """Smooth S-curve between two anchor points, tangent along the given axis."""
    (x0, y0), (x1, y1) = p0, p1
    if axis == "h":
        mx = (x0 + x1) / 2
        return f"M{x0:.1f},{y0:.1f} C{mx:.1f},{y0:.1f} {mx:.1f},{y1:.1f} {x1:.1f},{y1:.1f}"
    my = (y0 + y1) / 2
    return f"M{x0:.1f},{y0:.1f} C{x0:.1f},{my:.1f} {x1:.1f},{my:.1f} {x1:.1f},{y1:.1f}"


class Canvas:
    def __init__(self, w, h, theme):
        self.w, self.h, self.t = w, h, THEMES[theme]
        self.parts, self.markers = [], {}

    def accent(self, name):
        return self.t["accents"][name]

    def marker(self, color, open_head=False):
        key = (color, open_head)
        if key not in self.markers:
            self.markers[key] = f"m{len(self.markers)}"
        return self.markers[key]

    # ---------- text ----------
    def text(self, x, y, s, size: float = 13, weight=400, color=None, anchor="middle", mono=False, italic=False, spacing=None):
        color = color or self.t["text"]
        style = f"font-family:{MONO if mono else FONT};font-size:{size}px;font-weight:{weight};fill:{color}"
        if italic: style += ";font-style:italic"
        if spacing: style += f";letter-spacing:{spacing}"
        self.parts.append(f'<text x="{x:.1f}" y="{y:.1f}" text-anchor="{anchor}" style="{style}">{escape(s)}</text>')

    def lines(self, cx, cy, lines, size: float = 13, mono=False, color=None, anchor="middle", first_weight=600):
        """Centered block: first line emphasised, the rest muted and a point smaller."""
        lh = size + 5
        y = cy - (len(lines) - 1) * lh / 2 + size * 0.36
        for i, line in enumerate(lines):
            if i == 0:
                self.text(cx, y, line, size=size, weight=first_weight, color=color or self.t["text"], anchor=anchor, mono=mono)
            else:
                self.text(cx, y, line, size=size - 1, weight=400, color=self.t["muted"], anchor=anchor, mono=mono)
            y += lh

    # ---------- shapes ----------
    def chip(self, x, y, s, accent, size: float = 10.5, h=20, upper=True):
        strong, tint = self.accent(accent)
        label = s.upper() if upper else s
        w = text_width(label, size) * (1.12 if upper else 1.0) + 18
        self.parts.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h}" rx="{h/2}" fill="{tint}"/>')
        self.text(x + w / 2, y + h / 2 + size * 0.36, label, size=size, weight=700, color=strong, spacing="0.08em" if upper else None)
        return w

    def group(self, x, y, w, h, label, accent, sub=None):
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="{self.t["panel"]}" stroke="{self.t["border"]}" stroke-width="1"/>')
        self.chip(x + 16, y - 10, label, accent)
        if sub:
            self.text(x + 18, y + 27, sub, size=11, color=self.t["muted"], anchor="start", italic=True)

    def card(self, x, y, w, h, lines, accent=None, mono=False, tone="plain", size: float = 13):
        fill = self.t["node"]; stroke = self.t["node_stroke"]; color = None
        if accent and tone == "tint":
            strong, tint = self.accent(accent); fill, stroke, color = tint, tint, strong
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="11" fill="{fill}" stroke="{stroke}" stroke-width="1" filter="url(#shadow)"/>')
        if accent and tone == "plain":
            strong, _ = self.accent(accent)
            self.parts.append(f'<rect x="{x + 1}" y="{y + 9}" width="4" height="{h - 18}" rx="2" fill="{strong}"/>')
        self.lines(x + w / 2 + (2 if accent and tone == "plain" else 0), y + h / 2, lines, size=size, mono=mono, color=color)

    def pill(self, cx, cy, s, accent, w=None, h=30, size: float = 12.5, weight=600, mono=False):
        strong, tint = self.accent(accent)
        w = w or text_width(s, size) + 26
        self.parts.append(f'<rect x="{cx - w/2:.1f}" y="{cy - h/2:.1f}" width="{w:.1f}" height="{h}" rx="{h/2}" fill="{tint}" stroke="{strong}" stroke-opacity="0.35"/>')
        self.text(cx, cy + size * 0.36, s, size=size, weight=weight, color=strong, mono=mono)
        return w

    def diamond(self, cx, cy, w, h, lines, accent):
        strong, tint = self.accent(accent)
        d = f"M{cx},{cy - h/2} L{cx + w/2},{cy} L{cx},{cy + h/2} L{cx - w/2},{cy} Z"
        self.parts.append(f'<path d="{d}" fill="{tint}" stroke="{strong}" stroke-opacity="0.5" stroke-width="1.2" stroke-linejoin="round" filter="url(#shadow)"/>')
        self.lines(cx, cy, lines, size=12.5, color=strong)

    def badge(self, cx, cy, s, accent, r=9.5):
        strong = self.accent(accent)[0]
        self.parts.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r}" fill="{strong}"/>')
        self.text(cx, cy + 3.6, s, size=10, weight=700, color=self.t["bg"] if self.t is THEMES["light"] else "#0b1020")

    def rotated_text(self, x, y, s, size: float = 11, color=None, weight=600):
        color = color or self.t["text"]
        self.parts.append(f'<text transform="translate({x},{y}) rotate(-90)" text-anchor="middle" style="font-family:{FONT};font-size:{size}px;font-weight:{weight};fill:{color}">{escape(s)}</text>')

    # ---------- edges ----------
    def path(self, d, dashed=False, color=None, arrow=True, width=1.6, open_head=False):
        color = color or self.t["edge"]
        dash = ' stroke-dasharray="5 5"' if dashed else ""
        head = f' marker-end="url(#{self.marker(color, open_head)})"' if arrow else ""
        self.parts.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round"{dash}{head}/>')

    def edge(self, pts, dashed=False, color=None, arrow=True, r=14, width=1.6):
        self.path(rounded_path(pts, r), dashed=dashed, color=color, arrow=arrow, width=width)

    def curve(self, p0, p1, axis="h", dashed=False, color=None, width=1.6):
        self.path(scurve(p0, p1, axis), dashed=dashed, color=color, width=width)

    def edge_label(self, x, y, s, accent=None, size: float = 11):
        """Small label on a plain backing so it stays legible where it crosses lines."""
        w = text_width(s, size) + 12
        color = self.accent(accent)[0] if accent else self.t["muted"]
        self.parts.append(f'<rect x="{x - w/2:.1f}" y="{y - 9}" width="{w:.1f}" height="18" rx="5" fill="{self.t["bg"]}" fill-opacity="0.92"/>')
        self.text(x, y + 4, s, size=size, weight=600, color=color)

    # ---------- output ----------
    def render(self):
        flood, opacity = self.t["shadow"]
        defs = [f'<filter id="shadow" x="-10%" y="-20%" width="120%" height="150%"><feDropShadow dx="0" dy="1.5" stdDeviation="2.2" flood-color="{flood}" flood-opacity="{opacity}"/></filter>']
        for (color, open_head), mid in self.markers.items():
            if open_head:
                shape = f'<path d="M1,1 L8,5 L1,9" fill="none" stroke="{color}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'
            else:
                shape = f'<path d="M0.5,0.5 L8.5,5 L0.5,9.5 Z" fill="{color}"/>'
            defs.append(f'<marker id="{mid}" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">{shape}</marker>')
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" width="{self.w}" height="{self.h}" '
                f'font-family="{FONT}"><defs>{"".join(defs)}</defs>'
                f'<rect width="{self.w}" height="{self.h}" rx="18" fill="{self.t["bg"]}"/>')
        return head + "".join(self.parts) + "</svg>"


class Sequence:
    """Participants as pills, lifelines, numbered messages, self-messages and a loop frame."""

    def __init__(self, c, participants, top=26, row=34, row2=48):
        self.c, self.top, self.row, self.row2 = c, top, row, row2
        self.xs = {}
        self.y = top + 62
        for key, x, label, accent in participants:
            self.xs[key] = x
            lines = label.split("\n")
            h = 34 if len(lines) == 1 else 46
            strong, tint = c.accent(accent)
            w = max(text_width(l, 12.5) for l in lines) + 28
            c.parts.append(f'<rect x="{x - w/2:.1f}" y="{top - 4}" width="{w:.1f}" height="{h}" rx="10" fill="{tint}" stroke="{strong}" stroke-opacity="0.35" filter="url(#shadow)"/>')
            c.lines(x, top - 4 + h / 2, lines, size=12.5, color=strong, first_weight=700)
        self.n = 0
        self.loops = []

    def lifelines(self, bottom):
        for x in self.xs.values():
            self.c.parts.insert(1, f'<line x1="{x}" y1="{self.top + 46}" x2="{x}" y2="{bottom}" stroke="{self.c.t["lifeline"]}" stroke-width="1.2" stroke-dasharray="3 5"/>')

    def msg(self, a, b, label, dashed=False, accent="sky"):
        self.n += 1
        c = self.c
        lines = label.split("\n")
        xa, xb = self.xs[a], self.xs[b]
        color = c.t["edge_strong"]
        if a == b:
            y = self.y + (8 if len(lines) == 1 else 14)
            pts = [(xa, y - 10), (xa + 34, y - 10), (xa + 34, y + 12), (xa + 4, y + 12)]
            c.edge(pts, dashed=dashed, color=color, r=8)
            c.badge(xa, y - 10, str(self.n), accent)
            for i, line in enumerate(lines):
                c.text(xa + 44, y - 8 + i * 15, line, size=11.5, color=c.t["text"], anchor="start")
            self.y += self.row2 + (0 if len(lines) == 1 else 14)
            return
        y = self.y + (14 if len(lines) == 1 else 28)
        direction = 1 if xb > xa else -1
        c.path(f"M{xa + direction * 11},{y} L{xb - direction * 2},{y}", dashed=dashed, color=color, open_head=dashed)
        c.badge(xa, y, str(self.n), accent)
        cx = (xa + xb) / 2
        for i, line in enumerate(lines):
            c.text(cx, y - 7 - (len(lines) - 1 - i) * 15, line, size=11.5, color=c.t["text"], weight=500)
        self.y += self.row if len(lines) == 1 else self.row2 + 6

    def loop_start(self):
        y0 = self.y - 4
        self.y += 24          # room for the loop label above the first message
        return y0

    def loop_end(self, y0, x0, x1, label, accent="violet"):
        y1 = self.y - 4
        strong, tint = self.c.accent(accent)
        self.c.parts.insert(1, f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" rx="12" fill="{tint}" fill-opacity="0.35" stroke="{strong}" stroke-opacity="0.45" stroke-dasharray="6 4"/>')
        self.c.chip(x0 + 10, y0 - 10, label, accent, upper=False)
        self.y += 14
