# Factory art (PLAYTEST_FEEDBACK_2 / WP3): every factory piece, item and deposit tile.
# Same flat-industrial look as _gen_svg_pc.py: INK outlines, lit top-left faces, drop shadow.
# 64 px per footprint cell; directional pieces are drawn FACING EAST (the view rotates them).
# Run: python3 art/_gen_svg_factory.py
import os
from math import cos, sin, pi
OUT = os.path.dirname(os.path.abspath(__file__))
INK = '#0d1014'; SL = '#1b2027'; SL2 = '#2a313b'; SL3 = '#3a4350'
CY = '#3fd8e8'; AM = '#f2a93b'; GR = '#6bd46b'; RD = '#e8434f'; MG = '#e04bc0'; WH = '#eef2f5'; RU = '#d9773a'; GD = '#ffd447'
VI = '#8f7cf2'; GY = '#9aa4b0'


def sh(c, f):
    c = c.lstrip('#'); r, g, b = [int(c[i:i + 2], 16) for i in (0, 2, 4)]
    if f > 0: r, g, b = [int(v + (255 - v) * f) for v in (r, g, b)]
    else: r, g, b = [int(v * (1 + f)) for v in (r, g, b)]
    return '#%02x%02x%02x' % (r, g, b)


S = f'stroke="{INK}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"'
S2 = f'stroke="{INK}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"'
OUTS = {}


def svg(W, H, body): return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{body}</svg>\n'
def put(n, s): OUTS[n] = s
def poly(pts): return ' '.join(f'{x:.1f},{y:.1f}' for x, y in pts)
def ngon(cx, cy, r, n, rot=0): return [(cx + r * cos(rot + 2 * pi * i / n), cy + r * sin(rot + 2 * pi * i / n)) for i in range(n)]
def star(cx, cy, r1, r2, n, rot=-pi / 2): return [(cx + (r1 if i % 2 == 0 else r2) * cos(rot + pi * i / n), cy + (r1 if i % 2 == 0 else r2) * sin(rot + pi * i / n)) for i in range(2 * n)]


def block(x, y, w, h, c, r=5):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{sh(c, -0.38)}" {S}/>'
            f'<rect x="{x + 2.5}" y="{y + 2.5}" width="{w - 7}" height="{h - 7}" rx="{max(r - 2, 1)}" fill="{c}"/>'
            f'<path d="M{x + 4} {y + h - 9} V{y + 5} Q{x + 4} {y + 4} {x + 6} {y + 4} H{x + w - 9}" fill="none" stroke="{sh(c, 0.45)}" stroke-width="2"/>')


def disc(cx, cy, r, c):
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{sh(c, -0.38)}" {S}/><circle cx="{cx - 1}" cy="{cy - 1}" r="{r - 2.5}" fill="{c}"/>'
            f'<path d="M{cx - r * 0.6:.1f} {cy + r * 0.1:.1f} A{r * 0.62:.1f} {r * 0.62:.1f} 0 0 1 {cx + r * 0.1:.1f} {cy - r * 0.6:.1f}" fill="none" stroke="{sh(c, 0.5)}" stroke-width="2"/>')


def base(W, H, c, inset=4):
    """Building foundation: shadow, steel plate, accent trim, corner bolts."""
    return (f'<rect x="{inset + 2}" y="{inset + 4}" width="{W - 2 * inset}" height="{H - 2 * inset}" rx="9" fill="{INK}" opacity="0.45"/>'
            f'<rect x="{inset}" y="{inset}" width="{W - 2 * inset}" height="{H - 2 * inset}" rx="9" fill="{SL2}" {S}/>'
            f'<rect x="{inset + 5}" y="{inset + 5}" width="{W - 2 * inset - 10}" height="{H - 2 * inset - 10}" rx="6" fill="{SL}" stroke="{c}" stroke-width="2.5"/>'
            + ''.join(f'<rect x="{a}" y="{b}" width="5" height="5" fill="{SL3}"/>' for a, b in ((inset + 8, inset + 8), (W - inset - 13, inset + 8), (inset + 8, H - inset - 13), (W - inset - 13, H - inset - 13))))


def arrow_e(x, y, s, c):  # small east-pointing arrow (output marker)
    return f'<path d="M{x} {y - s} L{x + s * 1.3} {y} L{x} {y + s}Z" fill="{c}" {S2}/>'


# ------------------------------------------------------------------ logistics (64 per cell)
def belt(rail):
    rails = (f'<rect x="0" y="6" width="64" height="9" fill="{sh(rail, -0.3)}" {S2}/><rect x="0" y="49" width="64" height="9" fill="{sh(rail, -0.3)}" {S2}/>'
             f'<rect x="0" y="7.5" width="64" height="4" fill="{rail}"/><rect x="0" y="50.5" width="64" height="4" fill="{rail}"/>')
    surf = f'<rect x="0" y="15" width="64" height="34" fill="#22272e"/>' + ''.join(f'<rect x="{x}" y="15" width="2" height="34" fill="#2c323a"/>' for x in range(4, 64, 8))
    return svg(64, 64, surf + rails)


put('fy_belt', belt(AM))
put('fy_belt2', belt(RD))


def ug(entry):
    body = belt(AM).split('>', 1)[1].rsplit('</svg>', 1)[0]
    hx = 24 if entry else 0
    hood = (f'<path d="M{hx} 4 H{hx + 40} V60 H{hx}Z" fill="{sh(AM, -0.45)}" {S}/>'
            f'<path d="M{hx + 4} 8 H{hx + 36} V56 H{hx + 4}Z" fill="{SL2}"/>'
            f'<path d="M{hx + 8} 14 H{hx + 32} M{hx + 8} 24 H{hx + 32} M{hx + 8} 40 H{hx + 32} M{hx + 8} 50 H{hx + 32}" stroke="{AM}" stroke-width="3"/>')
    mouth = (f'<rect x="{hx + (0 if entry else 30)}" y="18" width="10" height="28" fill="{INK}"/>')
    arr = arrow_e(10 if entry else 46, 32, 7, WH)
    return svg(64, 64, body + hood + mouth + arr)


put('fy_ug_in', ug(True))
put('fy_ug_out', ug(False))

sp_lanes = ''.join(belt(AM).split('>', 1)[1].rsplit('</svg>', 1)[0].replace('<rect', f'<rect transform="translate(0 {dy})"', 99) for dy in (0, 64))
put('fy_splitter', svg(64, 128, sp_lanes + block(18, 10, 28, 108, sh(AM, -0.1), 6)
    + f'<path d="M24 64 L40 40 M24 64 L40 88" stroke="{INK}" stroke-width="6" stroke-linecap="round"/><path d="M24 64 L40 40 M24 64 L40 88" stroke="{WH}" stroke-width="3" stroke-linecap="round"/>'
    + arrow_e(44, 32, 6, GD) + arrow_e(44, 96, 6, GD)))

put('fy_inserter', svg(64, 64,
    f'<rect x="8" y="10" width="48" height="44" rx="8" fill="{INK}" opacity="0.35"/>' + disc(22, 32, 14, SL3)
    + f'<path d="M22 32 L50 32" stroke="{INK}" stroke-width="10" stroke-linecap="round"/><path d="M22 32 L50 32" stroke="{GD}" stroke-width="5.5" stroke-linecap="round"/>'
    + f'<path d="M50 22 L58 22 L58 26 M50 42 L58 42 L58 38" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round"/><path d="M50 22 L58 22 L58 26 M50 42 L58 42 L58 38" fill="none" stroke="{SL3}" stroke-width="3" stroke-linecap="round"/>'
    + f'<path d="M50 22 V42" stroke="{INK}" stroke-width="5"/>' + f'<circle cx="22" cy="32" r="5" fill="{GD}" {S2}/>'
    + f'<path d="M6 32 L12 27 V37Z" fill="{GY}" {S2}/>'))


# ------------------------------------------------------------------ production
def miner(c, deep):
    b = base(128, 128, c)
    drill = disc(56, 70, 34, sh(c, -0.15))
    bit = f'<polygon points="{poly(star(56, 70, 22, 12, 6))}" fill="{SL3}" {S}/><circle cx="56" cy="70" r="7" fill="{GD if deep else WH}" {S2}/>'
    tower = block(80, 12, 34, 54, sh(c, 0.1), 5) + f'<path d="M86 26 H108 M86 38 H108 M86 50 H108" stroke="{INK}" stroke-width="3"/>'
    chute = f'<path d="M108 20 H124 V44 H108Z" fill="{sh(c, -0.4)}" {S}/>' + arrow_e(112, 32, 7, GD)
    lamp = f'<circle cx="22" cy="22" r="6" fill="{GR}" {S2}/>'
    return svg(128, 128, b + drill + bit + tower + chute + lamp)


put('fy_miner', miner(AM, False))
put('fy_miner2', miner(RU, True))

put('fy_smelter', svg(128, 128, base(128, 128, RU)
    + block(16, 20, 96, 92, '#8a5a3c', 10)
    + ''.join(f'<path d="M{20} {y} H108" stroke="{sh("#8a5a3c", -0.45)}" stroke-width="2"/>' for y in (40, 60, 80))
    + ''.join(f'<path d="M{x} {y} V{y + 20}" stroke="{sh("#8a5a3c", -0.45)}" stroke-width="2"/>' for x, y in ((44, 40), (84, 40), (64, 60), (36, 80), (92, 80)))
    + f'<path d="M40 112 V86 A24 24 0 0 1 88 86 V112Z" fill="{INK}"/><path d="M46 112 V88 A18 18 0 0 1 82 88 V112Z" fill="#ff7a2e"/><path d="M54 112 V94 A10 10 0 0 1 74 94 V112Z" fill="{GD}"/>'
    + block(84, 6, 22, 30, SL3, 3) + f'<ellipse cx="95" cy="8" rx="8" ry="3" fill="{INK}"/>'))

put('fy_assembler', svg(192, 192, base(192, 192, CY)
    + block(20, 20, 152, 152, '#3b5566', 10)
    + f'<rect x="44" y="44" width="104" height="104" rx="12" fill="{INK}"/><rect x="50" y="50" width="92" height="92" rx="8" fill="#1d2d36" stroke="{CY}" stroke-width="2.5"/>'
    + f'<polygon points="{poly(star(96, 96, 36, 28, 10, 0))}" fill="{GY}" {S}/><circle cx="96" cy="96" r="14" fill="{SL2}" {S}/><circle cx="96" cy="96" r="5" fill="{CY}"/>'
    + ''.join(f'<rect x="{x}" y="{y}" width="14" height="14" rx="3" fill="{GD}" {S2}/>' for x, y in ((26, 26), (152, 26), (26, 152), (152, 152)))
    + ''.join(f'<rect x="{x}" y="28" width="6" height="10" fill="{CY}" opacity="0.8"/>' for x in (70, 82, 94, 106, 118))))

# ------------------------------------------------------------------ storage
put('fy_chest', svg(64, 64, f'<rect x="7" y="11" width="52" height="48" rx="6" fill="{INK}" opacity="0.4"/>'
    + block(5, 14, 54, 42, '#8a6a3c', 5) + f'<path d="M5 28 H59" stroke="{INK}" stroke-width="3"/><rect x="5" y="8" width="54" height="16" rx="5" fill="#a07c45" {S}/>'
    + f'<rect x="27" y="22" width="10" height="12" rx="2" fill="{GD}" {S2}/><path d="M14 36 V50 M50 36 V50" stroke="{sh("#8a6a3c", -0.4)}" stroke-width="3"/>'))
put('fy_vault', svg(128, 128, base(128, 128, GD) + block(14, 14, 100, 100, '#56606c', 10)
    + disc(64, 64, 30, SL3) + f'<circle cx="64" cy="64" r="20" fill="{SL2}" {S}/>'
    + ''.join(f'<path d="M{64 + 18 * cos(a):.1f} {64 + 18 * sin(a):.1f} L{64 + 30 * cos(a):.1f} {64 + 30 * sin(a):.1f}" stroke="{GD}" stroke-width="4" stroke-linecap="round"/>' for a in [i * pi / 3 for i in range(6)])
    + f'<circle cx="64" cy="64" r="6" fill="{GD}" {S2}/><rect x="96" y="40" width="10" height="48" rx="3" fill="{GY}" {S2}/>'))

# ------------------------------------------------------------------ power
put('fy_windmill', svg(128, 128, base(128, 128, GR)
    + f'<path d="M56 112 L60 60 H68 L72 112Z" fill="{GY}" {S}/>'
    + ''.join(f'<path d="M64 58 L{64 + 48 * cos(a + 0.2):.1f} {58 + 48 * sin(a + 0.2):.1f} L{64 + 50 * cos(a):.1f} {58 + 50 * sin(a):.1f}Z" fill="{WH}" {S}/>' for a in (-pi / 2, -pi / 2 + 2 * pi / 3, -pi / 2 + 4 * pi / 3))
    + disc(64, 58, 9, GR)))
put('fy_coal_gen', svg(128, 128, base(128, 128, RD)
    + block(14, 36, 76, 80, '#5b4a44', 8) + f'<rect x="26" y="70" width="52" height="30" rx="4" fill="{INK}"/><rect x="31" y="75" width="42" height="20" rx="3" fill="#ff7a2e"/>'
    + block(94, 10, 22, 106, SL3, 4) + f'<ellipse cx="105" cy="12" rx="9" ry="3.5" fill="{INK}"/>'
    + f'<path d="M30 52 L42 46 L36 58 L50 52" fill="none" stroke="{GD}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'
    + f'<circle cx="68" cy="52" r="7" fill="{GD}" {S2}/>'))
put('fy_pole', svg(64, 64, f'<ellipse cx="34" cy="56" rx="12" ry="5" fill="{INK}" opacity="0.4"/>'
    + f'<rect x="29" y="12" width="7" height="44" rx="2" fill="#8a6a3c" {S}/><rect x="14" y="12" width="36" height="7" rx="2" fill="#8a6a3c" {S}/>'
    + ''.join(f'<circle cx="{x}" cy="11" r="4" fill="{CY}" {S2}/>' for x in (18, 46))
    + f'<path d="M18 11 Q32 22 46 11" fill="none" stroke="{GD}" stroke-width="2"/>'))


# ------------------------------------------------------------------ hubs (3x3 = 192)
def hub(c, body):
    return svg(192, 192, base(192, 192, c, 6) + body)


put('fy_relay', hub(GD, block(26, 26, 140, 140, '#3a4655', 14)
    + f'<polygon points="{poly(ngon(96, 96, 52, 6, pi / 6))}" fill="{SL2}" {S}/>'
    + f'<polygon points="{poly(ngon(96, 96, 36, 6, pi / 6))}" fill="{sh(CY, -0.4)}" {S}/>'
    + f'<polygon points="{poly([(96, 66), (118, 96), (96, 126), (74, 96)])}" fill="{CY}" {S}/><polygon points="{poly([(96, 72), (108, 92), (96, 92)])}" fill="{WH}" opacity="0.8"/>'
    + ''.join(f'<rect x="{x}" y="{y}" width="20" height="20" rx="3" fill="{INK}" stroke="{GD}" stroke-width="2.5"/>' for x, y in ((86, 10), (86, 162), (10, 86), (162, 86)))
    + ''.join(arrow_e(0, 0, 0, GD) for _ in ())))
put('fy_bay', hub(CY, block(22, 30, 148, 132, '#34505a', 12)
    + f'<rect x="46" y="54" width="100" height="84" rx="10" fill="{INK}"/>' + disc(96, 96, 30, sh(CY, -0.2))
    + f'<polygon points="{poly(ngon(96, 96, 16, 6, pi / 6))}" fill="{CY}" {S2}/>'
    + f'<path d="M30 46 H62 M130 46 H162" stroke="{GD}" stroke-width="5" stroke-linecap="round"/>'
    + ''.join(f'<rect x="{x}" y="146" width="22" height="10" rx="2" fill="{GY}" {S2}/>' for x in (44, 86, 128))))
put('fy_crates', hub(AM, ''.join(block(x, y, w, h, c, 5) for x, y, w, h, c in ((24, 96, 70, 70, '#a07c45'), (98, 96, 70, 70, '#8a6a3c'), (60, 30, 72, 66, '#b58a4c')))
    + ''.join(f'<path d="M{x + 6} {y + h / 2} H{x + w - 8}" stroke="{INK}" stroke-width="3"/><rect x="{x + w / 2 - 7}" y="{y + 6}" width="14" height="{h - 14}" fill="{GD}" {S2}/>' for x, y, w, h in ((24, 96, 70, 70), (98, 96, 70, 70), (60, 30, 72, 66)))))
put('fy_research', hub(VI, block(24, 76, 144, 92, '#3d3a5c', 10)
    + f'<path d="M36 80 A60 60 0 0 1 156 80Z" fill="{sh(VI, -0.35)}" {S}/><path d="M48 80 A48 48 0 0 1 144 80" fill="none" stroke="{VI}" stroke-width="3"/>'
    + f'<rect x="88" y="26" width="16" height="40" rx="3" fill="{SL3}" {S2} transform="rotate(-30 96 46)"/>'
    + ''.join(f'<rect x="{x}" y="100" width="20" height="40" rx="3" fill="{INK}" stroke="{VI}" stroke-width="2"/>' for x in (44, 86, 128))
    + f'<circle cx="54" cy="118" r="5" fill="{CY}"/><circle cx="96" cy="112" r="5" fill="{GD}"/><circle cx="138" cy="124" r="5" fill="{GR}"/>'))
put('fy_cards', hub(MG, block(22, 40, 148, 128, '#4f3550', 10)
    + f'<path d="M14 48 L96 14 L178 48Z" fill="{sh(MG, -0.35)}" {S}/>'
    + ''.join(f'<rect x="{x}" y="{y}" width="40" height="56" rx="5" fill="{c}" {S} transform="rotate({r} {x + 20} {y + 28})"/>' for x, y, c, r in ((46, 78, '#d0d6de', -12), (76, 70, GD, 0), (106, 78, MG, 12)))
    + f'<polygon points="{poly(star(96, 98, 12, 5, 5))}" fill="{WH}" {S2}/>'))

# ------------------------------------------------------------------ deposit tiles + rock (64)
DEP = {'iron_ore': '#6f86a8', 'copper_ore': '#c9783f', 'coal': '#2a2d33', 'crystal': '#59d6e8', 'scrap': '#8b8f7a'}
for k, c in DEP.items():
    specks = ''.join(f'<polygon points="{poly(ngon(x, y, r, 5, x * 0.7))}" fill="{c}" stroke="{sh(c, -0.5)}" stroke-width="1.5"/><polygon points="{poly(ngon(x - 1, y - 1, r * 0.45, 5, x))}" fill="{sh(c, 0.4)}"/>'
                     for x, y, r in ((14, 16, 7), (40, 12, 5), (50, 36, 8), (22, 44, 6), (36, 54, 4), (10, 34, 3.5), (54, 56, 3.5)))
    if k == 'crystal':
        specks = ''.join(f'<polygon points="{poly([(x, y - 9), (x + 4, y), (x, y + 6), (x - 4, y)])}" fill="{c}" stroke="{sh(c, -0.55)}" stroke-width="1.5"/>' for x, y in ((14, 18), (42, 14), (50, 42), (22, 46), (34, 32)))
    put('dep_' + k, svg(64, 64, specks))
put('fy_rock', svg(64, 64, f'<polygon points="{poly([(8, 50), (14, 22), (30, 10), (50, 16), (58, 40), (46, 56), (20, 58)])}" fill="#4a4f57" {S}/><polygon points="{poly([(16, 24), (30, 14), (46, 18), (32, 30)])}" fill="#6a717b"/>'))


# ------------------------------------------------------------------ items (32)
def item(body): return svg(32, 32, body)


def ore(c): return item(f'<polygon points="{poly([(5, 20), (9, 9), (20, 5), (28, 13), (27, 24), (16, 28)])}" fill="{c}" stroke="{INK}" stroke-width="2"/><polygon points="{poly([(10, 11), (19, 8), (16, 16)])}" fill="{sh(c, 0.45)}"/>')
def plate_i(c): return item(f'<rect x="4" y="9" width="24" height="15" rx="2" fill="{sh(c, -0.3)}" stroke="{INK}" stroke-width="2"/><rect x="6" y="11" width="18" height="6" fill="{sh(c, 0.35)}"/>')


put('it_iron_ore', ore('#6f86a8'))
put('it_copper_ore', ore('#c9783f'))
put('it_coal', ore('#33363d'))
put('it_crystal', item(f'<polygon points="16,3 24,14 16,29 8,14" fill="#59d6e8" stroke="{INK}" stroke-width="2"/><polygon points="16,6 20,14 16,14" fill="{WH}" opacity="0.8"/>'))
put('it_scrap', item(f'<path d="M5 24 L9 12 L15 16 L18 6 L27 14 L24 26Z" fill="#8b8f7a" stroke="{INK}" stroke-width="2"/><path d="M10 20 L20 12" stroke="{RU}" stroke-width="2.5"/>'))
put('it_iron_plate', plate_i('#b9c6d6'))
put('it_copper_plate', plate_i('#e89a5c'))
put('it_alloy', item(f'<path d="M4 22 L9 11 H23 L28 22Z" fill="#a6ab8f" stroke="{INK}" stroke-width="2"/><path d="M10 13 H21" stroke="{WH}" stroke-width="2"/>'))
put('it_shard', item(f'<polygon points="16,2 22,12 18,30 10,22 9,10" fill="#8ff0ff" stroke="{INK}" stroke-width="2"/><polygon points="16,6 19,12 15,18" fill="{WH}"/>'))
put('it_gear', item(f'<polygon points="{poly(star(16, 16, 13, 9.5, 8, 0))}" fill="#9aa4b0" stroke="{INK}" stroke-width="2"/><circle cx="16" cy="16" r="4" fill="{INK}"/>'))
put('it_wire', item(f'<ellipse cx="16" cy="16" rx="11" ry="9" fill="none" stroke="{INK}" stroke-width="6"/><ellipse cx="16" cy="16" rx="11" ry="9" fill="none" stroke="#f2b46b" stroke-width="3"/><circle cx="16" cy="16" r="4" fill="{SL3}" stroke="{INK}" stroke-width="1.5"/>'))
put('it_circuit', item(f'<rect x="5" y="5" width="22" height="22" rx="3" fill="#2f7d3a" stroke="{INK}" stroke-width="2"/><rect x="11" y="11" width="10" height="10" fill="{INK}"/><path d="M8 9 H11 M8 23 H11 M21 9 H24 M21 23 H24 M16 6 V11" stroke="{GD}" stroke-width="2"/>'))
put('it_key_blank', item(f'<circle cx="11" cy="16" r="7" fill="{GD}" stroke="{INK}" stroke-width="2"/><circle cx="11" cy="16" r="2.5" fill="{INK}"/><path d="M17 14 H28 V18 H25 V21 H22 V18 H17Z" fill="{GD}" stroke="{INK}" stroke-width="2"/>'))
put('it_data_card', item(f'<rect x="6" y="4" width="20" height="25" rx="3" fill="{VI}" stroke="{INK}" stroke-width="2"/><rect x="10" y="8" width="12" height="7" fill="{INK}"/><path d="M10 19 H22 M10 23 H18" stroke="{WH}" stroke-width="2"/>'))
put('it_part_kit', item(f'<rect x="4" y="9" width="24" height="18" rx="3" fill="#e05a7a" stroke="{INK}" stroke-width="2"/><path d="M4 15 H28" stroke="{INK}" stroke-width="2"/><rect x="13" y="5" width="6" height="8" rx="1" fill="{SL3}" stroke="{INK}" stroke-width="1.5"/>'))

for n, s in OUTS.items():
    open(os.path.join(OUT, n + '.svg'), 'w').write(s)
print(len(OUTS))
