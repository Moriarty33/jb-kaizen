#!/usr/bin/env python3
"""Render every diagram to docs/assets/diagrams/<name>[.<lang>].<theme>.svg.

    python3 docs/diagrams/build.py             # write the SVGs
    python3 docs/diagrams/build.py --preview   # also write docs/assets/diagrams/_preview.html
                                               # (light + dark side by side; gitignored)

The READMEs embed each pair with <picture> so GitHub picks the theme automatically."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import readme_diagrams  # noqa: E402
import arch_diagrams  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parents[1] / "assets" / "diagrams"
ALL = {**readme_diagrams.DIAGRAMS, **arch_diagrams.DIAGRAMS}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    written = []
    for name, (fn, langs) in ALL.items():
        for lang in langs:
            for theme in ("light", "dark"):
                svg = fn(theme, lang) if len(langs) > 1 or fn.__code__.co_argcount == 2 else fn(theme)
                stem = f"{name}.{lang}" if len(langs) > 1 else name
                path = OUT / f"{stem}.{theme}.svg"
                path.write_text(svg)
                written.append(path)
    print(f"wrote {len(written)} files to {OUT}")
    if "--preview" in sys.argv:
        blocks = []
        for p in written:
            if p.name.endswith(".light.svg"):
                dark = p.name.replace(".light.svg", ".dark.svg")
                blocks.append(f'<h2>{p.name.replace(".light.svg", "")}</h2><div class="pair"><img src="{p.name}"><div class="dark"><img src="{dark}"></div></div>')
        html = ('<meta charset="utf-8"><style>body{margin:24px;font:14px Inter,sans-serif;background:#fff}'
                '.pair img{width:100%;display:block;margin:12px 0}.dark{background:#0d1117;padding:16px;border-radius:12px}'
                'h2{margin:28px 0 4px}</style>' + "".join(blocks))
        (OUT / "_preview.html").write_text(html)
        print(f"preview: {OUT / '_preview.html'}")


if __name__ == "__main__":
    main()
