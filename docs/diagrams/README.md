# Diagrams

The pictures in the READMEs and in `ARCHITECTURE.md` are hand-laid SVGs generated from Python,
not auto-layouts: `svgkit.py` holds the visual system (one palette family with the banner,
light and dark themes, cards, groups, pills, edges, a sequence helper), `readme_diagrams.py`
and `arch_diagrams.py` hold the pictures with explicit coordinates and the English and
Ukrainian labels.

```bash
python3 docs/diagrams/build.py             # regenerates docs/assets/diagrams/*.svg (16 files)
python3 docs/diagrams/build.py --preview   # plus _preview.html with both themes side by side
```

Each picture is embedded as a `<picture>` pair so GitHub picks the theme:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/diagrams/how-it-works.en.dark.svg">
  <img alt="..." src="docs/assets/diagrams/how-it-works.en.light.svg" width="1000">
</picture>
```

CI regenerates the SVGs and fails if the committed ones differ, so edit the Python, run
`build.py`, and commit both. Fonts are the system stack (Inter, then the platform's sans);
widths are sized with margin so the fallback fonts fit too.
