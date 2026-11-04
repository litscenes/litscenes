#!/usr/bin/env python3
"""Render README figures of the bundled meaning graph from its compiled SQLite cache.

Two figures, each in a light and a dark variant, written as self-contained SVG:

  meaning-graph-overview-{light,dark}.svg      every concept on a ring grouped by kind,
                                               every relationship drawn as a chord
  meaning-graph-neighborhood-{light,dark}.svg  one concept with all of its direct
                                               relationships, labelled and in motion

Standard library only. Usage from the repository root:

  swift build --product MeaningGraphCompiler
  .build/debug/MeaningGraphCompiler Sources/LitScenes/Resources/MeaningGraph/graph.yaml \
      Sources/LitScenes/Resources/MeaningGraph/graph.sqlite
  python3 scripts/render_meaning_graph_figures.py [--focus "Shared Stewardship"]
"""

from __future__ import annotations

import argparse
import json
import math
import sqlite3
from collections import defaultdict
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / "Sources/LitScenes/Resources/MeaningGraph/graph.sqlite"
DEFAULT_OUT = ROOT / "docs/media"

KIND_ORDER = [
    ("theme", "Theme"),
    ("value_tension", "Value tension"),
    ("meaning_claim", "Meaning claim"),
    ("symbol", "Symbol"),
    ("motif", "Motif"),
    ("mood", "Mood"),
    ("archetypal_situation", "Archetypal situation"),
    ("transformation", "Transformation"),
    ("genre_force", "Genre force"),
    ("beat_function", "Beat function"),
    ("scene_role", "Scene role"),
]
KIND_LABEL = dict(KIND_ORDER)
KIND_RANK = {kind: index for index, (kind, _) in enumerate(KIND_ORDER)}

# Relationship families: the colour a relationship wears. Three hues validate as
# distinguishable for every pair, including under colour-vision deficiency; the
# fourth family (turns) is drawn in ink and dashed so it never relies on hue. The
# exact relation type is always written out in the legend or on the edge label.
FAMILIES = [
    ("expresses", "Expresses", ["expresses", "symbolizes", "evokes"]),
    ("orders", "Orders", ["specializes", "is_example_of", "depends_on", "implies"]),
    ("accompanies", "Accompanies", ["co_occurs_with", "intensifies", "foreshadows"]),
    ("turns", "Turns", ["contrasts_with", "transforms_into", "resolves", "corrupts", "inverts"]),
]
FAMILY_OF = {relation: family for family, _, relations in FAMILIES for relation in relations}

THEMES = {
    "light": {
        "bg": "#f7f3ea", "ink": "#1f1b16", "ink2": "#5b554c", "ink3": "#8d867b",
        "line": "#d9d2c4", "family": ["#2a78d6", "#eb6834", "#1baf7a", "#5b554c"],
    },
    "dark": {
        "bg": "#13161a", "ink": "#ede8dd", "ink2": "#b5afa3", "ink3": "#7f7a70",
        "line": "#2c3138", "family": ["#3987e5", "#d95926", "#199e70", "#b5afa3"],
    },
}
SERIF = '"Iowan Old Style","Palatino Linotype",Palatino,"Book Antiqua",Georgia,serif'
SANS = '-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif'


def load_graph(db_path: Path) -> tuple[dict, dict, list]:
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    metadata = json.loads(connection.execute("SELECT payload FROM graph_metadata").fetchone()[0])
    nodes = {row[0]: json.loads(row[1]) for row in connection.execute("SELECT id, payload FROM nodes")}
    edges = [json.loads(row[1]) for row in connection.execute("SELECT id, payload FROM edges")]
    connection.close()
    return metadata, nodes, edges


def polar(cx: float, cy: float, radius: float, degrees: float) -> tuple[float, float]:
    radians = math.radians(degrees)
    return cx + radius * math.cos(radians), cy + radius * math.sin(radians)


def wrap(text: str, width: int, max_lines: int = 3) -> list[str]:
    lines: list[str] = []
    current = ""
    for word in text.split():
        candidate = f"{current} {word}".strip()
        if current and len(candidate) > width:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        lines[-1] = lines[-1].rstrip(".,;") + "…"
    return lines


def tspans(lines: list[str], x: float, first_dy: str, line_height: float) -> str:
    return "".join(
        f'<tspan x="{x:.1f}" dy="{first_dy if index == 0 else f"{line_height:.1f}"}">{escape(line)}</tspan>'
        for index, line in enumerate(lines)
    )


def fmt(number: int) -> str:
    return f"{number:,}"


def style(theme: dict) -> str:
    return (
        "<style>"
        f"text{{font-family:{SANS};fill:{theme['ink']}}}"
        f".serif{{font-family:{SERIF}}}"
        f".muted{{fill:{theme['ink2']}}}"
        f".faint{{fill:{theme['ink3']}}}"
        ".caps{font-size:11px;letter-spacing:.14em;text-transform:uppercase}"
        f".knock{{paint-order:stroke;stroke:{theme['bg']};stroke-width:7px;stroke-linejoin:round}}"
        "</style>"
    )


def render_overview(theme: dict, metadata: dict, nodes: dict, edges: list) -> str:
    width, height = 1340, 800
    cx, cy, ring = 450.0, 400.0, 250.0
    gap = 3.0

    by_kind: dict[str, list[str]] = defaultdict(list)
    for node_id, node in nodes.items():
        by_kind[node["kind"]].append(node_id)
    kinds = [(kind, label) for kind, label in KIND_ORDER if by_kind.get(kind)]
    for kind, _ in kinds:
        by_kind[kind].sort(key=lambda node_id: nodes[node_id]["slug"])
    total = sum(len(by_kind[kind]) for kind, _ in kinds)
    sweep = 360.0 - gap * len(kinds)

    position: dict[str, tuple[float, float, float]] = {}
    arcs = []
    angle = -90.0
    for kind, label in kinds:
        members = by_kind[kind]
        span = sweep * len(members) / total
        for index, node_id in enumerate(members):
            degrees = angle + span * (index + 0.5) / len(members)
            position[node_id] = (degrees, *polar(cx, cy, ring - 6, degrees))
        arcs.append((kind, label, angle, angle + span, len(members)))
        angle += span + gap

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
        f'role="img" aria-labelledby="title desc">',
        f'<title id="title">The LitScenes meaning graph: {fmt(len(nodes))} concepts in {len(kinds)} kinds joined by '
        f'{fmt(len(edges))} relationships</title>',
        '<desc id="desc">Every concept sits on a ring grouped by kind; every relationship is a chord across the ring, '
        'coloured by relationship family.</desc>',
        style(theme),
        f'<rect width="{width}" height="{height}" fill="{theme["bg"]}"/>',
    ]

    # chords, grouped by family so each family can breathe on its own cycle
    chords: dict[str, list[str]] = defaultdict(list)
    pull = 0.22
    for edge in edges:
        source = position.get(edge["source_node_id"])
        target = position.get(edge["target_node_id"])
        if not source or not target:
            continue
        _, x1, y1 = source
        _, x2, y2 = target
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        qx, qy = cx + (mx - cx) * pull, cy + (my - cy) * pull
        chords[FAMILY_OF.get(edge["relation_type"], "orders")].append(
            f"M{x1:.1f} {y1:.1f}Q{qx:.1f} {qy:.1f} {x2:.1f} {y2:.1f}"
        )
    for index, (family, _, _) in enumerate(FAMILIES):
        colour = theme["family"][index]
        dash = ' stroke-dasharray="5 4"' if family == "turns" else ""
        parts.append(f'<g fill="none" stroke="{colour}" stroke-width="0.8" stroke-linecap="round" opacity="0.42"{dash}>')
        parts.append(
            f'<animate attributeName="opacity" values="0.42;0.9;0.42" keyTimes="0;0.5;1" dur="16s" '
            f'begin="{index * 4}s" repeatCount="indefinite"/>'
        )
        parts.append(f'<path d="{"".join(chords[family])}"/>')
        parts.append("</g>")

    # arcs, concept dots and kind labels
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="{ring}" fill="none" stroke="{theme["line"]}" stroke-width="1"/>')
    for kind, label, start, end, count in arcs:
        x1, y1 = polar(cx, cy, ring, start)
        x2, y2 = polar(cx, cy, ring, end)
        large = 1 if end - start > 180 else 0
        parts.append(
            f'<path d="M{x1:.1f} {y1:.1f}A{ring} {ring} 0 {large} 1 {x2:.1f} {y2:.1f}" fill="none" '
            f'stroke="{theme["ink"]}" stroke-width="3" stroke-linecap="butt"/>'
        )
        mid = (start + end) / 2
        lx, ly = polar(cx, cy, ring + 34, mid)
        flip = 90 < (mid % 360) < 270
        rotate = mid + 180 if flip else mid
        anchor = "end" if flip else "start"
        parts.append(
            f'<text transform="translate({lx:.1f} {ly:.1f}) rotate({rotate:.1f})" text-anchor="{anchor}" '
            f'font-size="14" dominant-baseline="middle">{escape(label)} '
            f'<tspan class="faint" font-size="12">{count}</tspan></text>'
        )
    for node_id, (degrees, _, _) in position.items():
        row = (sum(ord(c) for c in nodes[node_id]["slug"]) % 3) * 5
        x, y = polar(cx, cy, ring + 8 + row, degrees)
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="1.6" fill="{theme["ink2"]}"/>')

    # legend
    lx = 880.0
    parts.append(f'<text x="{lx}" y="92" class="serif" font-size="34">{escape(metadata["title"])}</text>')
    parts.append(
        f'<text x="{lx}" y="124" font-size="15" class="muted">{fmt(len(nodes))} concepts · '
        f'{fmt(len(edges))} relationships · {fmt(metadata["counts"]["evidence"])} evidence records</text>'
    )
    parts.append(f'<text x="{lx}" y="190" class="caps muted">Relationships, by family</text>')
    y = 222.0
    family_counts = {family: len(chords[family]) for family, _, _ in FAMILIES}
    for index, (family, label, relations) in enumerate(FAMILIES):
        colour = theme["family"][index]
        if family == "turns":
            parts.append(f'<line x1="{lx}" y1="{y - 10}" x2="{lx + 22}" y2="{y - 10}" stroke="{colour}" stroke-width="4" stroke-dasharray="5 3"/>')
        else:
            parts.append(f'<rect x="{lx}" y="{y - 12}" width="22" height="4" rx="2" fill="{colour}"/>')
        parts.append(
            f'<text x="{lx + 34}" y="{y}" font-size="17">{label} '
            f'<tspan class="faint" font-size="13">{fmt(family_counts[family])}</tspan></text>'
        )
        parts.append(f'<text x="{lx + 34}" y="{y + 20}" font-size="13" class="muted">{escape(", ".join(relations))}</text>')
        y += 58
    parts.append(f'<text x="{lx}" y="{y + 10}" class="caps muted">Concepts, by kind</text>')
    y += 42
    column = 0
    for kind, label in kinds:
        x = lx + column * 210
        parts.append(
            f'<text x="{x}" y="{y}" font-size="15">{escape(label)} '
            f'<tspan class="faint" font-size="13">{len(by_kind[kind])}</tspan></text>'
        )
        column += 1
        if column == 2:
            column = 0
            y += 26
    parts.append(
        f'<text x="{lx}" y="{height - 36}" font-size="11" class="faint">Rendered from the bundled graph · '
        f'{escape(metadata["packId"])} {escape(metadata["version"])}</text>'
    )
    parts.append("</svg>")
    return "\n".join(parts)


def render_neighborhood(theme: dict, nodes: dict, edges: list, focus_id: str) -> str:
    width, height = 1200, 840
    cx, cy, ring, disc = 600.0, 470.0, 232.0, 86.0
    focus = nodes[focus_id]

    incident = []
    for edge in edges:
        if edge["source_node_id"] == focus_id:
            incident.append((edge, nodes[edge["target_node_id"]], True))
        elif edge["target_node_id"] == focus_id:
            incident.append((edge, nodes[edge["source_node_id"]], False))
    incident.sort(key=lambda item: (KIND_RANK.get(item[1]["kind"], 99), item[1]["name"]))
    if not incident:
        raise SystemExit(f"{focus['name']} has no relationships to draw")

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
        f'role="img" aria-labelledby="title desc">',
        f'<title id="title">{escape(focus["name"])} and its {len(incident)} direct relationships in the LitScenes meaning graph</title>',
        f'<desc id="desc">{escape(focus.get("definition", ""))}</desc>',
        style(theme),
        f'<rect width="{width}" height="{height}" fill="{theme["bg"]}"/>',
        "<defs>",
    ]
    for index in range(len(FAMILIES)):
        parts.append(
            f'<marker id="arrow{index}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
            f'orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="{theme["family"][index]}"/></marker>'
        )
    parts.append("</defs>")

    # header: the focus concept as text
    provenance = focus.get("provenance_kind", "").replace("_", " ")
    level = focus.get("abstraction_level", "")
    parts.append(
        f'<text x="60" y="54" class="caps muted">{escape(KIND_LABEL.get(focus["kind"], focus["kind"]))}'
        f'{" · " + escape(provenance) if provenance else ""}{" · " + escape(level) if level else ""}</text>'
    )
    parts.append(f'<text x="60" y="100" class="serif" font-size="40">{escape(focus["name"])}</text>')
    parts.append(
        f'<text x="60" y="130" font-size="17" class="muted">'
        f'{tspans(wrap(focus.get("definition", ""), 96, 2), 60, "0", 24)}</text>'
    )

    # edges, pulses, neighbours
    count = len(incident)
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="{ring}" fill="none" stroke="{theme["line"]}" stroke-width="1" stroke-dasharray="2 6"/>')
    for index, (edge, other, outgoing) in enumerate(incident):
        degrees = -90 + 360 * index / count
        nx, ny = polar(cx, cy, ring, degrees)
        family_index = next(i for i, (family, _, _) in enumerate(FAMILIES) if family == FAMILY_OF.get(edge["relation_type"], "orders"))
        colour = theme["family"][family_index]
        dash = ' stroke-dasharray="7 5"' if FAMILIES[family_index][0] == "turns" else ""
        fx, fy = polar(cx, cy, disc + 4, degrees)
        ex, ey = polar(cx, cy, ring - 12, degrees)
        start, end = ((fx, fy), (ex, ey)) if outgoing else ((ex, ey), (fx, fy))
        parts.append(
            f'<line x1="{start[0]:.1f}" y1="{start[1]:.1f}" x2="{end[0]:.1f}" y2="{end[1]:.1f}" stroke="{colour}" '
            f'stroke-width="2" stroke-linecap="round"{dash} marker-end="url(#arrow{family_index})"/>'
        )
        parts.append(
            f'<circle r="4.5" fill="{colour}" opacity="0"><animateMotion dur="5s" begin="{index * 0.45:.2f}s" '
            f'repeatCount="indefinite" path="M{start[0]:.1f} {start[1]:.1f}L{end[0]:.1f} {end[1]:.1f}"/>'
            f'<animate attributeName="opacity" values="0;1;1;0" keyTimes="0;0.12;0.82;1" dur="5s" '
            f'begin="{index * 0.45:.2f}s" repeatCount="indefinite"/></circle>'
        )
        # relation label along the line, kept upright
        lx, ly = polar(cx, cy, (disc + ring) / 2 + 4, degrees)
        flip = 90 < (degrees % 360) < 270
        rotate = degrees + 180 if flip else degrees
        parts.append(
            f'<text transform="translate({lx:.1f} {ly:.1f}) rotate({rotate:.1f})" text-anchor="middle" '
            f'dominant-baseline="middle" font-size="12" class="knock muted">{escape(edge["relation_type"].replace("_", " "))}</text>'
        )
        parts.append(f'<circle cx="{nx:.1f}" cy="{ny:.1f}" r="7" fill="{theme["bg"]}" stroke="{theme["ink"]}" stroke-width="2"/>')
        # neighbour label block outside the ring
        cos, sin = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
        tx, ty = polar(cx, cy, ring + 22, degrees)
        anchor = "start" if cos > 0.25 else "end" if cos < -0.25 else "middle"
        lines = wrap(other["name"], 26, 3)
        block = 15 + 21 * len(lines)
        top = ty - block / 2 if abs(sin) < 0.3 else (ty - block if sin < 0 else ty)
        parts.append(
            f'<text x="{tx:.1f}" y="{top + 11:.1f}" text-anchor="{anchor}" class="caps faint">'
            f'{escape(KIND_LABEL.get(other["kind"], other["kind"]))}</text>'
        )
        parts.append(
            f'<text x="{tx:.1f}" y="{top + 11:.1f}" text-anchor="{anchor}" font-size="18" class="serif">'
            f'{tspans(lines, tx, "21", 21)}</text>'
        )

    # the focus disc
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="{disc}" fill="{theme["ink"]}"/>')
    lines = wrap(focus["name"], 16, 3)
    parts.append(
        f'<text x="{cx}" y="{cy - 10 * (len(lines) - 1):.1f}" text-anchor="middle" dominant-baseline="middle" '
        f'font-size="19" class="serif" fill="{theme["bg"]}" style="fill:{theme["bg"]}">{tspans(lines, cx, "0", 22)}</text>'
    )
    parts.append(
        f'<text x="{width - 60}" y="{height - 36}" text-anchor="end" font-size="12" class="faint">'
        f'{len(incident)} of {fmt(len(edges))} relationships · rendered from the bundled graph</text>'
    )
    parts.append("</svg>")
    return "\n".join(parts)


def resolve_focus(nodes: dict, wanted: str) -> str:
    lowered = wanted.lower()
    for node_id, node in nodes.items():
        if node["slug"].lower() == lowered or node["name"].lower() == lowered:
            return node_id
    raise SystemExit(f"No concept named or slugged {wanted!r}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="compiled graph.sqlite")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="directory for the SVG files")
    parser.add_argument("--focus", default="Shared Stewardship", help="concept name or slug for the neighbourhood figure")
    args = parser.parse_args()

    metadata, nodes, edges = load_graph(args.db)
    focus_id = resolve_focus(nodes, args.focus)
    args.out.mkdir(parents=True, exist_ok=True)
    for name, theme in THEMES.items():
        overview = args.out / f"meaning-graph-overview-{name}.svg"
        overview.write_text(render_overview(theme, metadata, nodes, edges) + "\n", encoding="utf-8")
        neighborhood = args.out / f"meaning-graph-neighborhood-{name}.svg"
        neighborhood.write_text(render_neighborhood(theme, nodes, edges, focus_id) + "\n", encoding="utf-8")
        print(f"wrote {overview.relative_to(ROOT)} ({overview.stat().st_size // 1024} KB)")
        print(f"wrote {neighborhood.relative_to(ROOT)} ({neighborhood.stat().st_size // 1024} KB)")
    print(f"focus: {nodes[focus_id]['name']} ({nodes[focus_id]['slug']}) · graph {metadata['packId']} {metadata['version']}")


if __name__ == "__main__":
    main()
