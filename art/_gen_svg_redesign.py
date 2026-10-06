# Redesign art pass (REDESIGN_SPEC §4). Reuses the palette/outline/light helpers of _gen_svg_pc.py
# so every new id shares the flat-industrial look: INK 3px outline, top-left highlight, drop shadow.
import os
_here = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(_here, '_gen_svg_pc.py')).read().split('B={}')[0])
exec('\n'.join(l for l in open(os.path.join(_here, '_gen_svg.py')).read().splitlines() if l.startswith("G['")))
from math import cos, sin, pi
VI = '#8f7cf2'   # violet (storm / insight accent), muted to sit beside MG
GY = '#9aa4b0'   # common rarity grey
RAR = {'C': GY, 'R': CY, 'E': MG, 'L': GD}
def svgwh(W, H, body): return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{body}</svg>\n'
OUTS = {}
def put(n, s): OUTS[n] = s
def poly(pts): return ' '.join(f'{x:.1f},{y:.1f}' for x, y in pts)
def ngon(cx, cy, r, n, rot=0): return [(cx + r*cos(rot + 2*pi*i/n), cy + r*sin(rot + 2*pi*i/n)) for i in range(n)]
def star(cx, cy, r1, r2, n, rot=-pi/2): return [(cx + (r1 if i % 2 == 0 else r2)*cos(rot + pi*i/n), cy + (r1 if i % 2 == 0 else r2)*sin(rot + pi*i/n)) for i in range(2*n)]
def litpoly(pts, c):  # outlined polygon + inner lit face
    cx = sum(p[0] for p in pts)/len(pts); cy = sum(p[1] for p in pts)/len(pts)
    inner = [(cx + (x-cx)*0.84 - 0.8, cy + (y-cy)*0.84 - 0.8) for x, y in pts]
    return f'<polygon points="{poly(pts)}" fill="{sh(c,-0.35)}" {S}/><polygon points="{poly(inner)}" fill="{c}"/>'
def shadow64(r=27): return f'<circle cx="33" cy="35" r="{r}" fill="{INK}" opacity="0.4"/>'

# ---------------- extra glyphs (48 space, centred ~24,24) ----------------
G['shield'] = lambda c: f'<path d="M24 10 L36 14 V24 C36 31 30 36 24 38 C18 36 12 31 12 24 V14Z" fill="{c}" {S2}/><path d="M24 13 V35 C19 33 15 29 15 24 V16Z" fill="{sh(c,0.35)}"/>'
G['barrel'] = lambda c: f'<rect x="9" y="19" width="22" height="10" rx="2" fill="{SL3}" {S2}/><rect x="29" y="17" width="10" height="14" rx="2" fill="{c}" {S2}/><path d="M14 22 h12" stroke="{sh(SL3,0.4)}" stroke-width="2"/>'
G['battery'] = lambda c: f'<rect x="13" y="13" width="22" height="25" rx="3" fill="{SL3}" {S2}/><rect x="20" y="9" width="8" height="5" fill="{SL3}" {S2}/><path d="M26 16 L19 27 H24 L22 35 L30 23 H25Z" fill="{c}" stroke="{INK}" stroke-width="1.5"/>'
G['gear'] = lambda c: f'<polygon points="{poly(star(24,24,13,10,8,0))}" fill="{c}" {S2}/><circle cx="24" cy="24" r="5" fill="{INK}"/><circle cx="23" cy="23" r="2" fill="{sh(c,0.5)}"/>'
G['star5'] = lambda c: f'<polygon points="{poly(star(24,25,13,6,5))}" fill="{c}" {S2}/>'
G['spear'] = lambda c: f'<path d="M12 36 L30 18" stroke="{INK}" stroke-width="6" stroke-linecap="round"/><path d="M12 36 L30 18" stroke="{SL3}" stroke-width="3" stroke-linecap="round"/><path d="M27 15 L38 10 L33 21Z" fill="{c}" {S2}/>'
G['bolt'] = lambda c: f'<path d="M27 9 L14 27 H23 L20 39 L35 20 H26Z" fill="{c}" {S2}/>'
G['hex3'] = lambda c: ''.join(f'<polygon points="{poly(ngon(x,y,6.5,6,pi/6))}" fill="{c}" {S2}/>' for x, y in ((18,20),(30,20),(24,31)))
G['eye'] = lambda c: f'<path d="M9 24 C15 14 33 14 39 24 C33 34 15 34 9 24Z" fill="{WH}" {S2}/><circle cx="24" cy="24" r="6" fill="{c}" stroke="{INK}" stroke-width="2"/><circle cx="24" cy="24" r="2.5" fill="{INK}"/>'
G['clover'] = lambda c: ''.join(f'<circle cx="{x}" cy="{y}" r="5.5" fill="{c}" {S2}/>' for x, y in ((24,16),(17,23),(31,23),(24,30))) + f'<path d="M24 30 L26 38" stroke="{INK}" stroke-width="3"/>'
G['drop'] = lambda c: f'<path d="M24 10 L34 22 L24 38 L14 22Z" fill="{c}" {S2}/><path d="M24 14 L18 22 L24 33Z" fill="{sh(c,0.4)}"/>'
G['box'] = lambda c: f'<rect x="12" y="18" width="24" height="18" rx="2" fill="{sh(AM,-0.25)}" {S2}/><path d="M10 13 H38 V19 H10Z" fill="{AM}" {S2}/><rect x="21" y="13" width="6" height="23" fill="{c}" stroke="{INK}" stroke-width="2"/>'
G['plus'] = lambda c: f'<path d="M24 12 V36 M12 24 H36" stroke="{INK}" stroke-width="9" stroke-linecap="round"/><path d="M24 12 V36 M12 24 H36" stroke="{c}" stroke-width="5" stroke-linecap="round"/>'
G['magnet'] = lambda c: f'<path d="M14 12 V25 A10 10 0 0 0 34 25 V12 H28 V25 A4 4 0 0 1 20 25 V12Z" fill="{c}" {S2}/><rect x="14" y="12" width="6" height="5" fill="{WH}" stroke="{INK}" stroke-width="2"/><rect x="28" y="12" width="6" height="5" fill="{WH}" stroke="{INK}" stroke-width="2"/>'
G['hourglass'] = lambda c: f'<path d="M15 10 H33 M15 38 H33 M17 10 C17 20 24 22 24 24 C24 26 17 28 17 38 H31 C31 28 24 26 24 24 C24 22 31 20 31 10Z" fill="{WH}" {S2}/><path d="M20 34 H28 L24 29Z" fill="{c}"/>'
G['wrench'] = lambda c: f'<path d="M14 34 L27 21" stroke="{INK}" stroke-width="7" stroke-linecap="round"/><path d="M14 34 L27 21" stroke="{c}" stroke-width="3.5" stroke-linecap="round"/><path d="M26 14 A7 7 0 1 0 34 22 L30 22 L26 18Z" fill="{SL3}" {S2}/>'
G['orbital'] = lambda c: f'<path d="M24 6 V30" stroke="{INK}" stroke-width="7"/><path d="M24 6 V30" stroke="{c}" stroke-width="3.5"/><circle cx="24" cy="33" r="7" fill="{GD}" {S2}/><path d="M14 38 L10 42 M34 38 L38 42 M24 41 V45" stroke="{GD}" stroke-width="2.5" stroke-linecap="round"/>'
G['emp'] = lambda c: f'<circle cx="24" cy="24" r="13" fill="none" stroke="{INK}" stroke-width="5"/><circle cx="24" cy="24" r="13" fill="none" stroke="{c}" stroke-width="2.5" stroke-dasharray="5 3"/><path d="M26 15 L19 25 H24 L22 33 L29 23 H24Z" fill="{WH}" stroke="{INK}" stroke-width="1.5"/>'
G['dice'] = lambda c: f'<rect x="12" y="12" width="24" height="24" rx="4" fill="{WH}" {S2} transform="rotate(10 24 24)"/>' + ''.join(f'<circle cx="{x}" cy="{y}" r="2.3" fill="{c}"/>' for x, y in ((18,18),(24,24),(30,30),(30,18),(18,30)))
G['lens'] = lambda c: f'<circle cx="21" cy="21" r="9" fill="{sh(CY,0.4)}" {S2}/><path d="M28 28 L37 37" stroke="{INK}" stroke-width="6" stroke-linecap="round"/><path d="M28 28 L37 37" stroke="{c}" stroke-width="3" stroke-linecap="round"/><path d="M16 19 A5 5 0 0 1 20 15" stroke="#fff" stroke-width="2" fill="none"/>'
G['truck'] = lambda c: f'<rect x="9" y="17" width="20" height="13" rx="2" fill="{c}" {S2}/><path d="M29 21 H35 L39 26 V30 H29Z" fill="{SL3}" {S2}/><circle cx="16" cy="33" r="3.5" fill="{INK}"/><circle cx="33" cy="33" r="3.5" fill="{INK}"/>'
G['helmet'] = lambda c: f'<path d="M11 30 C11 16 37 16 37 30Z" fill="{c}" {S2}/><rect x="9" y="29" width="30" height="5" rx="2" fill="{SL3}" {S2}/><path d="M24 18 V29" stroke="{sh(c,-0.4)}" stroke-width="2"/>'
G['corechip'] = lambda c: ''.join(f'<rect x="22" y="7" width="4" height="7" fill="{RU}" stroke="{INK}" stroke-width="1.5" transform="rotate({a} 24 24)"/>' for a in range(0, 360, 60)) + f'<circle cx="24" cy="24" r="10" fill="{sh(WH,-0.15)}" {S2}/><circle cx="24" cy="24" r="5" fill="{c}"/>'
G['mirror'] = lambda c: f'<rect x="13" y="10" width="22" height="28" rx="11" fill="{sh(CY,0.5)}" {S2}/><path d="M18 18 L24 14 M18 25 L28 17" stroke="#fff" stroke-width="2"/>'
G['comb'] = G['hex3']
G['queen'] = lambda c: f'<path d="M14 22 L12 13 L19 17 L24 10 L29 17 L36 13 L34 22Z" fill="{GD}" {S2}/><ellipse cx="24" cy="30" rx="9" ry="8" fill="{c}" {S2}/><path d="M17 30 H31 M18 34 H30" stroke="{INK}" stroke-width="2"/>'
G['turbine'] = lambda c: f'<circle cx="24" cy="24" r="13" fill="{SL3}" {S2}/>' + ''.join(f'<path d="M24 24 L{24+11*cos(a):.1f} {24+11*sin(a):.1f} A11 11 0 0 1 {24+11*cos(a+0.8):.1f} {24+11*sin(a+0.8):.1f}Z" fill="{c}" stroke="{INK}" stroke-width="1.5"/>' for a in (0, 2.09, 4.19)) + f'<circle cx="24" cy="24" r="3" fill="{INK}"/>'
G['reactor'] = lambda c: f'<circle cx="24" cy="24" r="13" fill="{SL3}" {S2}/>' + ''.join(f'<path d="M24 24 L{24+11*cos(a):.1f} {24+11*sin(a):.1f} A11 11 0 0 1 {24+11*cos(a+1.05):.1f} {24+11*sin(a+1.05):.1f}Z" fill="{c}"/>' for a in (-1.57, 0.52, 2.62)) + f'<circle cx="24" cy="24" r="4" fill="{GD}" stroke="{INK}" stroke-width="2"/>'
G['press'] = lambda c: f'<rect x="14" y="10" width="20" height="8" rx="1" fill="{SL3}" {S2}/><rect x="22" y="18" width="4" height="8" fill="{SL3}" stroke="{INK}" stroke-width="2"/><circle cx="24" cy="31" r="7" fill="{GD}" {S2}/><path d="M24 27 v8" stroke="{INK}" stroke-width="2"/>'
G['rail'] = lambda c: f'<rect x="8" y="20" width="32" height="8" rx="2" fill="{SL3}" {S2}/>' + ''.join(f'<rect x="{x}" y="17" width="3" height="14" fill="{c}" stroke="{INK}" stroke-width="1.2"/>' for x in (13, 19, 25, 31))
G['scatter'] = lambda c: f'<rect x="8" y="20" width="12" height="8" rx="2" fill="{SL3}" {S2}/>' + ''.join(f'<circle cx="{x}" cy="{y}" r="3" fill="{c}" stroke="{INK}" stroke-width="1.5"/>' for x, y in ((28,16),(34,24),(28,32),(38,14),(39,33)))
G['ring'] = lambda c: f'<circle cx="24" cy="24" r="13" fill="none" stroke="{INK}" stroke-width="6"/><circle cx="24" cy="24" r="13" fill="none" stroke="{c}" stroke-width="3"/><circle cx="24" cy="24" r="6" fill="none" stroke="{INK}" stroke-width="5"/><circle cx="24" cy="24" r="6" fill="none" stroke="{c}" stroke-width="2.5"/>'
G['bone'] = lambda c: f'<rect x="10" y="22" width="28" height="5" rx="2" fill="{SL3}" {S2}/><path d="M10 14 V34 M38 14 V34" stroke="{INK}" stroke-width="5"/><path d="M10 14 V34 M38 14 V34" stroke="{c}" stroke-width="2.5"/>'
G['chain'] = lambda c: f'<path d="M10 30 L18 18 L24 28 L32 14 L38 22" fill="none" stroke="{INK}" stroke-width="6" stroke-linejoin="round"/><path d="M10 30 L18 18 L24 28 L32 14 L38 22" fill="none" stroke="{c}" stroke-width="3" stroke-linejoin="round"/>' + ''.join(f'<circle cx="{x}" cy="{y}" r="3" fill="{WH}" stroke="{INK}" stroke-width="1.5"/>' for x, y in ((10,30),(24,28),(38,22)))
G['coinstack'] = lambda c: ''.join(f'<ellipse cx="24" cy="{y}" rx="10" ry="4" fill="{GD}" {S2}/>' for y in (34, 28, 22, 16))
G['gauge'] = lambda c: f'<path d="M10 32 A14 14 0 0 1 38 32Z" fill="{SL3}" {S2}/><path d="M24 32 L32 20" stroke="{c}" stroke-width="3" stroke-linecap="round"/><circle cx="24" cy="32" r="3" fill="{INK}"/>'
G['speedup'] = lambda c: f'<path d="M11 32 L20 23 L26 28 L37 16" fill="none" stroke="{INK}" stroke-width="6" stroke-linejoin="round"/><path d="M11 32 L20 23 L26 28 L37 16" fill="none" stroke="{c}" stroke-width="3" stroke-linejoin="round"/><path d="M30 15 H38 V23Z" fill="{c}" {S2}/>'
G['rotate'] = lambda c: f'<path d="M14 26 A10 10 0 1 1 24 34" fill="none" stroke="{INK}" stroke-width="6"/><path d="M14 26 A10 10 0 1 1 24 34" fill="none" stroke="{c}" stroke-width="3"/><path d="M9 24 L14 31 L19 24Z" fill="{c}" {S2}/>'
G['ban'] = lambda c: f'<circle cx="24" cy="24" r="12" fill="none" stroke="{INK}" stroke-width="7"/><circle cx="24" cy="24" r="12" fill="none" stroke="{c}" stroke-width="3.5"/><path d="M16 32 L32 16" stroke="{INK}" stroke-width="7"/><path d="M16 32 L32 16" stroke="{c}" stroke-width="3.5"/>'
G['hammer'] = lambda c: f'<path d="M15 36 L27 22" stroke="{INK}" stroke-width="6" stroke-linecap="round"/><path d="M15 36 L27 22" stroke="{AM}" stroke-width="3" stroke-linecap="round"/><rect x="21" y="9" width="16" height="9" rx="1" fill="{c}" {S2} transform="rotate(40 29 14)"/>'
G['move'] = lambda c: ''.join(f'<path d="M24 24 L24 11 M20 15 L24 10 L28 15" fill="none" stroke="{INK}" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round" transform="rotate({a} 24 24)"/><path d="M24 24 L24 11 M20 15 L24 10 L28 15" fill="none" stroke="{c}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" transform="rotate({a} 24 24)"/>' for a in (0, 90, 180, 270))
G['blueprint'] = lambda c: f'<rect x="10" y="12" width="28" height="24" rx="2" fill="{sh(CY,-0.45)}" {S2}/><path d="M14 18 H24 V30 H34 M28 18 H34 V24" fill="none" stroke="{WH}" stroke-width="1.8"/><path d="M14 24 H20" stroke="{WH}" stroke-width="1.8" stroke-dasharray="2 2"/>'
G['collect'] = lambda c: f'<path d="M24 10 V27 M17 21 L24 28 L31 21" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/><path d="M24 10 V27 M17 21 L24 28 L31 21" fill="none" stroke="{c}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><rect x="11" y="31" width="26" height="6" rx="2" fill="{SL3}" {S2}/>'

def badge(c, g, gc=None): return ibg(c) + G[g](gc or c)
def roundbadge(c, g, gc=None):  # specials: circular frame reads "castable"
    return (f'<circle cx="25" cy="26" r="21" fill="{INK}" opacity="0.4"/><circle cx="24" cy="24" r="21" fill="{sh(c,-0.55)}" {S}/>'
            f'<circle cx="24" cy="24" r="17.5" fill="{SL}" stroke="{c}" stroke-width="2"/>' + G[g](gc or c))

# ---------------- Cores (64): five distinct silhouettes ----------------
def core_center(c, r=9):
    return f'<circle cx="32" cy="32" r="{r}" fill="{c}" {S}/><circle cx="32" cy="32" r="{r*0.5:.1f}" fill="{WH}"/><circle cx="{32-r*0.2:.1f}" cy="{32-r*0.2:.1f}" r="{r*0.2:.1f}" fill="#ffffff"/>'
# Bastion: octagonal fortress with crenels (green, sturdy)
put('core_bastion', svg(64, shadow64(28) + ''.join(f'<rect x="27" y="2" width="10" height="9" rx="1" fill="{sh(GR,-0.2)}" {S2} transform="rotate({a} 32 32)"/>' for a in range(22, 382, 45))
    + litpoly(ngon(32, 32, 25, 8, pi/8), sh(WH, -0.2)) + litpoly(ngon(32, 32, 16, 8, pi/8), GR) + core_center(RU, 8)))
# Foundry: square furnace with 2 stacks + gear ring (amber/rust)
put('core_foundry', svg(64, shadow64(28) + f'<polygon points="{poly(star(32,33,28,23,12,0))}" fill="{sh(AM,-0.4)}" {S}/>'
    + block(12, 13, 40, 40, sh(WH, -0.25), 6) + block(8, 6, 10, 18, sh(RU, -0.1), 2) + block(46, 6, 10, 18, sh(RU, -0.1), 2)
    + f'<rect x="10" y="4" width="6" height="4" fill="{INK}"/><rect x="48" y="4" width="6" height="4" fill="{INK}"/>' + core_center(AM, 10)
    + f'<path d="M20 46 h24" stroke="{INK}" stroke-width="3"/><path d="M22 46 h20" stroke="{GD}" stroke-width="1.5"/>'))
# Lance: elongated diamond hull with a long forward barrel (cyan, precise)
put('core_lance', svg(64, shadow64(26) + f'<rect x="28.5" y="1" width="7" height="30" rx="1" fill="{SL3}" {S}/><rect x="27" y="5" width="10" height="3" fill="{CY}"/><rect x="27" y="11" width="10" height="3" fill="{CY}"/>'
    + litpoly([(32, 14), (54, 36), (32, 60), (10, 36)], sh(WH, -0.2)) + litpoly([(32, 24), (44, 36), (32, 49), (20, 36)], CY) + f'<circle cx="32" cy="36" r="5" fill="{INK}"/><circle cx="32" cy="36" r="2.4" fill="{WH}"/>'))
# Tempest: ringed orb with three emitter prongs + arcs (violet/cyan, volatile)
put('core_tempest', svg(64, shadow64(27) + ''.join(f'<path d="M32 4 L36 14 H28Z" fill="{VI}" {S2} transform="rotate({a} 32 32)"/>' for a in (0, 120, 240))
    + f'<circle cx="32" cy="32" r="24" fill="none" stroke="{INK}" stroke-width="7"/><circle cx="32" cy="32" r="24" fill="none" stroke="{VI}" stroke-width="3.5"/>'
    + disc(32, 32, 16, sh(WH, -0.2)) + core_center(VI, 9)
    + f'<path d="M8 20 L13 24 L9 28 M56 20 L51 24 L55 28 M26 58 L32 53 L38 58" fill="none" stroke="{CY}" stroke-width="2.5" stroke-linejoin="round"/>'))
# Hive (deferred core, art ready): cluster of hex cells (gold, organic)
put('core_hive', svg(64, shadow64(27) + ''.join(litpoly(ngon(32 + 15*cos(a), 32 + 15*sin(a), 10, 6, pi/6), sh(AM, -0.05)) for a in [i*pi/3 + pi/6 for i in range(6)])
    + litpoly(ngon(32, 32, 13, 6, pi/6), sh(WH, -0.2)) + core_center(GD, 8)
    + ''.join(f'<circle cx="{32 + 15*cos(a):.1f}" cy="{32 + 15*sin(a):.1f}" r="2.5" fill="{INK}"/>' for a in [i*pi/3 + pi/6 for i in range(6)])))
put('core_locked', svg(64, shadow64(27) + f'<polygon points="{poly(ngon(32,32,25,8,pi/8))}" fill="{SL2}" {S}/><polygon points="{poly(ngon(32,32,19,8,pi/8))}" fill="{SL}" stroke="{SL3}" stroke-width="2" stroke-dasharray="4 3"/>'
    + f'<g transform="translate(8 9)">{G["lock"](GD)}</g>'))
# Exploded Core (Bay view): two shell halves pulled apart, 4 slot sockets revealed around a glowing heart
put('core_open', svgwh(128, 128, f'<circle cx="66" cy="68" r="44" fill="{INK}" opacity="0.35"/>'
    + f'<path d="M14 54 A50 50 0 0 1 114 54 L100 54 A36 36 0 0 0 28 54Z" fill="{sh(WH,-0.45)}" {S}/><path d="M18 50 A46 46 0 0 1 64 8" fill="none" stroke="{sh(WH,0.1)}" stroke-width="2"/>'
    + f'<path d="M14 80 A50 50 0 0 0 114 80 L100 80 A36 36 0 0 1 28 80Z" fill="{sh(WH,-0.55)}" {S}/>'
    + ''.join(f'<rect x="{x-9}" y="{y-9}" width="18" height="18" rx="4" fill="{SL}" stroke="{c}" stroke-width="3"/><rect x="{x-9}" y="{y-9}" width="18" height="18" rx="4" fill="none" {S2} opacity="0.6"/>' for x, y, c in ((40, 67, GY), (88, 67, CY), (64, 43, MG), (64, 91, GD)))
    + f'<circle cx="64" cy="67" r="11" fill="{RU}" {S}/><circle cx="64" cy="67" r="6" fill="{WH}"/><circle cx="64" cy="67" r="20" fill="none" stroke="{GD}" stroke-width="1.5" stroke-dasharray="3 4"/>'
    + f'<path d="M64 4 V0 M8 67 H2 M120 67 H126" stroke="{GD}" stroke-width="3"/>'))

# ---------------- Core attack FX (64) ----------------
put('fx_cannon', svg(64, f'<circle cx="32" cy="32" r="12" fill="{RU}" {S}/><circle cx="29" cy="29" r="5" fill="{GD}"/><path d="M6 32 H18" stroke="{GD}" stroke-width="4" stroke-linecap="round" opacity="0.7"/>'))
put('fx_slag', svg(64, f'<path d="M32 12 C44 22 48 30 46 40 C44 50 20 50 18 40 C16 30 22 22 32 12Z" fill="{RU}" {S}/><path d="M32 22 C38 28 40 33 39 38 C37 44 27 44 25 38 C24 33 27 28 32 22Z" fill="{GD}"/><circle cx="14" cy="52" r="3" fill="{AM}"/><circle cx="52" cy="50" r="2.5" fill="{AM}"/>'))
put('fx_beam', svgwh(128, 32, f'<rect x="0" y="9" width="128" height="14" rx="7" fill="{CY}" opacity="0.35"/><rect x="0" y="12" width="128" height="8" rx="4" fill="{CY}"/><rect x="0" y="14.5" width="128" height="3" fill="#ffffff"/>'))
put('fx_pulse_ring', svg(64, f'<circle cx="32" cy="32" r="27" fill="none" stroke="{VI}" stroke-width="6" opacity="0.5"/><circle cx="32" cy="32" r="27" fill="none" stroke="{WH}" stroke-width="2"/>'))
put('fx_chain', svgwh(128, 32, f'<path d="M2 16 L20 6 L34 24 L54 4 L70 26 L90 8 L104 22 L126 14" fill="none" stroke="{CY}" stroke-width="6" opacity="0.4" stroke-linejoin="round"/><path d="M2 16 L20 6 L34 24 L54 4 L70 26 L90 8 L104 22 L126 14" fill="none" stroke="#ffffff" stroke-width="2" stroke-linejoin="round"/>'))
put('fx_splash', svg(64, f'<polygon points="{poly(star(32,32,28,14,10))}" fill="{AM}" opacity="0.6"/><polygon points="{poly(star(32,32,18,9,10,0))}" fill="{GD}"/><circle cx="32" cy="32" r="6" fill="#ffffff"/>'))
put('fx_orbital', svgwh(64, 128, f'<rect x="20" y="0" width="24" height="112" fill="{GD}" opacity="0.25"/><rect x="27" y="0" width="10" height="112" fill="{GD}"/><rect x="30" y="0" width="4" height="112" fill="#ffffff"/><ellipse cx="32" cy="112" rx="28" ry="10" fill="{GD}" opacity="0.6"/><ellipse cx="32" cy="112" rx="14" ry="5" fill="#ffffff"/>'))
put('fx_emp', svg(64, f'<circle cx="32" cy="32" r="28" fill="{CY}" opacity="0.15"/><circle cx="32" cy="32" r="28" fill="none" stroke="{CY}" stroke-width="3" stroke-dasharray="8 5"/><circle cx="32" cy="32" r="18" fill="none" stroke="{WH}" stroke-width="2" stroke-dasharray="4 6"/><path d="M34 18 L24 34 H31 L28 46 L40 30 H33Z" fill="{WH}" stroke="{INK}" stroke-width="2"/>'))

# ---------------- New in-run buildings, huts, troops (64) ----------------
put('frost', svg(64, plate(CY) + disc(31, 33, 15, sh(CY, 0.25)) + ''.join(f'<path d="M31 33 L31 15" stroke="{INK}" stroke-width="5" stroke-linecap="round" transform="rotate({a} 31 33)"/><path d="M31 33 L31 15 M27 19 L31 22 L35 19" fill="none" stroke="{WH}" stroke-width="2.5" stroke-linecap="round" transform="rotate({a} 31 33)"/>' for a in range(0, 360, 60)) + f'<circle cx="31" cy="33" r="4" fill="{CY}" {S2}/>'))
put('obelisk', svg(64, plate(MG) + f'<rect x="16" y="44" width="30" height="8" rx="2" fill="{SL3}" {S}/><path d="M24 44 L28 12 L34 12 L38 44Z" fill="{sh(MG,-0.35)}" {S}/><path d="M26 42 L29 14 L31 14 L31 42Z" fill="{sh(MG,0.3)}"/><path d="M28 12 L31 6 L34 12Z" fill="{GD}" {S2}/><path d="M28 26 h6 M27 34 h8" stroke="{INK}" stroke-width="2"/>'))
def hut(c, emblem):
    return plate(RD) + block(12, 24, 38, 27, sh(WH, -0.3), 3) + f'<path d="M9 27 L31 10 L53 27Z" fill="{c}" {S}/><path d="M13 26 L31 12" stroke="{sh(c,0.45)}" stroke-width="2"/><rect x="25" y="36" width="12" height="15" rx="1" fill="{INK}"/>' + emblem
put('hut_infantry', svg(64, hut(sh(RD, -0.1), f'<circle cx="31" cy="21" r="4" fill="{WH}" stroke="{INK}" stroke-width="2"/><path d="M17 33 h5 M40 33 h5" stroke="{INK}" stroke-width="3"/>')))
put('hut_sapper', svg(64, hut(AM, f'<circle cx="31" cy="22" r="4.5" fill="{INK}"/><path d="M33 18 l3 -3" stroke="{GD}" stroke-width="2"/><path d="M17 33 h5 M40 33 h5" stroke="{INK}" stroke-width="3"/>')))
put('hut_drone', svg(64, hut(CY, f'<path d="M25 21 h12 M27 19 v4 M35 19 v4" stroke="{INK}" stroke-width="2.5"/><circle cx="31" cy="21" r="2.5" fill="{WH}"/>') + f'<rect x="40" y="38" width="8" height="8" rx="1" fill="{CY}" {S2}/>'))
def tshadow(): return f'<ellipse cx="33" cy="54" rx="14" ry="4" fill="{INK}" opacity="0.4"/>'
put('troop_rifleman', svg(64, tshadow() + f'<rect x="36" y="14" width="5" height="26" rx="1" fill="{SL3}" {S2}/>' + disc(30, 36, 12, sh(GR, -0.1)) + f'<path d="M18 30 C18 18 42 18 42 30Z" fill="{sh(GR,-0.35)}" {S}/><rect x="16" y="28" width="28" height="4" rx="2" fill="{SL3}" {S2}/><rect x="24" y="36" width="12" height="4" rx="1" fill="{INK}"/>'))
put('troop_sapper', svg(64, tshadow() + disc(30, 36, 13, AM) + f'<rect x="20" y="30" width="20" height="6" rx="2" fill="{INK}"/><rect x="22" y="31.5" width="5" height="3" fill="{GD}"/><rect x="33" y="31.5" width="5" height="3" fill="{GD}"/><circle cx="44" cy="22" r="6" fill="{INK}" {S2}/><path d="M47 17 L50 13" stroke="{GD}" stroke-width="2.5" stroke-linecap="round"/>'))
put('troop_drone', svg(64, f'<ellipse cx="33" cy="56" rx="12" ry="3.5" fill="{INK}" opacity="0.3"/>' + ''.join(f'<path d="M32 30 L{32+17*cos(a):.1f} {30+17*sin(a):.1f}" stroke="{INK}" stroke-width="4"/><circle cx="{32+17*cos(a):.1f}" cy="{30+17*sin(a):.1f}" r="6" fill="{sh(CY,0.4)}" {S2} opacity="0.9"/>' for a in (0.785, 2.356, 3.927, 5.498)) + disc(32, 30, 9, CY) + f'<circle cx="32" cy="30" r="3" fill="{INK}"/><circle cx="31" cy="29" r="1.2" fill="{WH}"/>'))
put('courier', svg(64, f'<ellipse cx="34" cy="56" rx="20" ry="5" fill="{INK}" opacity="0.4"/>' + block(10, 18, 40, 30, sh(RD, -0.05), 8) + f'<rect x="18" y="12" width="24" height="12" rx="3" fill="{GD}" {S}/><path d="M30 12 V24 M18 18 H42" stroke="{INK}" stroke-width="2"/><circle cx="22" cy="36" r="3" fill="{WH}"/><circle cx="38" cy="36" r="3" fill="{WH}"/><path d="M50 30 h8 M50 38 h6" stroke="{RD}" stroke-width="3" opacity="0.6"/>'))

# ---------------- Packs, specials, insight (48) ----------------
for k, (c, g) in {'arsenal': (CY, 'sword'), 'overclock': (CY, 'gauge'), 'fort': (GR, 'fort'), 'ledger': (AM, 'coinstack'), 'optics': (CY, 'lens'),
                  'crit': (RD, 'target'), 'logistics': (AM, 'truck'), 'core': (RU, 'corechip'), 'barracks': (RD, 'helmet'), 'gambit': (MG, 'dice')}.items():
    put('pk_' + k, svg(48, badge(c, g) + f'<rect x="31" y="31" width="10" height="10" rx="2" fill="{c}" {S2}/><path d="M36 33 v6 M33 36 h6" stroke="{INK}" stroke-width="2"/>'))
for k, (c, g) in {'orbital': (GD, 'orbital'), 'emp': (CY, 'emp'), 'repair': (GR, 'wrench'), 'overdrive': (RD, 'speedup'), 'magnet': (AM, 'magnet'), 'timewarp': (VI, 'hourglass')}.items():
    put('sp_' + k, svg(48, roundbadge(c, g)))
INS = '#fff4c8'
def insight_frame(): return (f'<rect x="1" y="1" width="46" height="46" rx="11" fill="{GD}" opacity="0.25"/><rect x="3" y="3" width="41" height="41" rx="9" fill="{sh(GD,-0.5)}" {S}/>'
                             f'<rect x="6" y="6" width="35" height="35" rx="6" fill="{SL}" stroke="{INS}" stroke-width="2"/>')
put('insight', svg(48, insight_frame() + G['eye'](GD) + ''.join(f'<path d="M24 {y1} V{y2}" stroke="{INS}" stroke-width="2" stroke-linecap="round" transform="rotate({a} 24 24)"/>' for a in (0, 90, 180, 270) for y1, y2 in ((1, 4),))))
for k, g in {'dmg': 'sword', 'hp': 'heart', 'cash': 'cash', 'rate': 'rate', 'luck': 'clover', 'drop': 'drop', 'crate': 'box'}.items():
    put('in_' + k, svg(48, insight_frame() + G[g]({'hp': RD, 'luck': GR}.get(k, GD)) + f'<circle cx="38" cy="10" r="5" fill="{INS}" {S2}/><circle cx="38" cy="10" r="1.8" fill="{INK}"/>'))

# ---------------- Draft frames + tag chips ----------------
def cardframe(c, glow=False):
    g = f'<rect x="1" y="0" width="46" height="48" rx="8" fill="{c}" opacity="0.28"/>' if glow else ''
    return svg(48, g + f'<rect x="6" y="4" width="38" height="43" rx="6" fill="{INK}" opacity="0.4"/><rect x="4" y="2" width="38" height="43" rx="6" fill="{sh(c,-0.5)}" {S}/>'
               f'<rect x="7" y="5" width="32" height="37" rx="4" fill="{SL}" stroke="{c}" stroke-width="2.5"/><path d="M15 5 H31 L28 9 H18Z" fill="{c}"/><rect x="13" y="37" width="20" height="2.5" rx="1" fill="{c}"/>')
for k, c in (('common', GY), ('rare', CY), ('epic', MG), ('legendary', GD)): put('card_' + k, cardframe(c, k == 'legendary'))
put('card_insight', cardframe(INS, True).replace('</svg>', f'{G["eye"](GD)}</svg>'))
for k, (c, g) in {'eco': (AM, 'coin'), 'dps': (RD, 'sword'), 'aoe': (AM, 'scatter'), 'control': (CY, 'hourglass'), 'troop': (RD, 'helmet'), 'special': (GD, 'star5'), 'sustain': (GR, 'heart')}.items():
    put('tag_' + k, svg(48, f'<rect x="2" y="9" width="44" height="30" rx="15" fill="{sh(c,-0.55)}" {S}/><rect x="5" y="12" width="38" height="24" rx="12" fill="{SL}" stroke="{c}" stroke-width="2"/><g transform="translate(12 12) scale(0.5)">{G[g](c)}</g><circle cx="35" cy="24" r="3.5" fill="{c}"/>'))

# ---------------- Parts: slots, 32 parts, set specials, set badges ----------------
SLOTG = {'F': 'shield', 'B': 'barrel', 'C': 'battery', 'E': 'gear'}
SLOTC = {'F': GR, 'B': RD, 'C': CY, 'E': AM}
SETC = {'bulwark': GR, 'mint': GD, 'lancer': RD, 'storm': VI, 'swarm': AM}
SETG = {'bulwark': 'shield', 'mint': 'coin', 'lancer': 'spear', 'storm': 'bolt', 'swarm': 'hex3'}
def slotglyph(s, c): return svg(48, f'<rect x="4" y="4" width="40" height="40" rx="8" fill="{SL}" stroke="{c}" stroke-width="3" stroke-dasharray="7 4"/><g opacity="0.85">{G[s](c)}</g>')
for k, s in {'frame': 'F', 'barrel': 'B', 'capacitor': 'C', 'engine': 'E'}.items(): put('slot_' + k, slotglyph(SLOTG[s], SLOTC[s]))
put('slot_set', slotglyph('star5', GD))
put('slot_locked', svg(48, f'<rect x="4" y="4" width="40" height="40" rx="8" fill="{INK}" stroke="{SL3}" stroke-width="3"/>' + G['lock'](GD)))
def partframe(rar, slot, glyph, gc, setk=None, special=False):
    c = RAR[rar]
    halo = f'<rect x="0" y="0" width="48" height="48" rx="11" fill="{c}" opacity="0.3"/>' if (rar == 'L' or special) else ''
    corner = f'<polygon points="3,3 17,3 3,17" fill="{SLOTC[slot]}" stroke="{INK}" stroke-width="2" stroke-linejoin="round"/>'
    pip = f'<polygon points="{poly(ngon(38,38,6,6,pi/6))}" fill="{SETC[setk]}" {S2}/>' if setk else ''
    gems = ''.join(f'<circle cx="{18+i*4}" cy="42" r="1.6" fill="{c}"/>' for i in range({'C': 1, 'R': 2, 'E': 3, 'L': 4}[rar]))
    return svg(48, halo + f'<rect x="4" y="5" width="41" height="41" rx="9" fill="{INK}" opacity="0.4"/><rect x="3" y="3" width="41" height="41" rx="9" fill="{sh(c,-0.55)}" {S}/>'
               f'<rect x="6" y="6" width="35" height="35" rx="6" fill="{SL}" stroke="{c}" stroke-width="2.5"/><g transform="translate(24 23) scale(0.86) translate(-24 -24)">{G[glyph](gc)}</g>' + corner + gems + pip
               + (f'<polygon points="{poly(star(41,8,6,2.6,4))}" fill="{WH}" stroke="{INK}" stroke-width="1.2"/>' if special else ''))
PARTS = [('f_plating', 'F', 'C', 'shield', SL3, None), ('f_lightweave', 'F', 'C', 'wind', CY, None), ('f_bulkhead', 'F', 'R', 'fort', GR, 'bulwark'),
         ('f_regenmesh', 'F', 'R', 'heart', GR, 'bulwark'), ('f_mirror', 'F', 'E', 'mirror', CY, 'bulwark'), ('f_ledgerframe', 'F', 'R', 'list', GD, 'mint'),
         ('f_hivecomb', 'F', 'E', 'hex3', AM, 'swarm'), ('f_glass', 'F', 'L', 'glass', CY, None),
         ('b_longbore', 'B', 'C', 'range', CY, None), ('b_shortbore', 'B', 'C', 'rate', CY, None), ('b_hollow', 'B', 'R', 'barrel', RD, 'lancer'),
         ('b_focuslens', 'B', 'E', 'lens', RD, 'lancer'), ('b_scatter', 'B', 'R', 'scatter', VI, 'storm'), ('b_ringcaster', 'B', 'E', 'ring', VI, 'storm'),
         ('b_crit', 'B', 'R', 'target', RD, None), ('b_bounty', 'B', 'R', 'greed', GD, 'mint'), ('b_droneport', 'B', 'R', 'helmet', AM, 'swarm'),
         ('c_overcharge', 'C', 'C', 'frenzy', GD, None), ('c_quickcap', 'C', 'R', 'clock', CY, None), ('c_battery', 'C', 'R', 'battery', VI, 'storm'),
         ('c_capacitor_arc', 'C', 'E', 'chain', VI, 'storm'), ('c_interest', 'C', 'R', 'coinstack', GD, 'mint'), ('c_scope', 'C', 'E', 'eye', RD, 'lancer'),
         ('c_pheromone', 'C', 'R', 'flask', AM, 'swarm'), ('c_luckchip', 'C', 'E', 'clover', GR, None),
         ('e_turbine', 'E', 'C', 'turbine', AM, None), ('e_reactor', 'E', 'R', 'reactor', RD, None), ('e_dynamo', 'E', 'R', 'gear', CY, None),
         ('e_mintpress', 'E', 'E', 'press', GD, 'mint'), ('e_bastionheart', 'E', 'E', 'corechip', GR, 'bulwark'), ('e_railcore', 'E', 'L', 'rail', RD, 'lancer'),
         ('e_queen', 'E', 'L', 'queen', AM, 'swarm')]
assert len(PARTS) == 32
for pid, s, r, g, gc, st in PARTS: put(pid, partframe(r, s, g, gc, st))
for pid, s, st, g in (('citadel_heart', 'E', 'bulwark', 'heart'), ('golden_ratio', 'C', 'mint', 'coinstack'), ('singularity_lens', 'B', 'lancer', 'lens'),
                      ('eye_of_storm', 'F', 'storm', 'eye'), ('brood_mother', 'E', 'swarm', 'queen')):
    put(pid, partframe('L', s, g, SETC[st], st, special=True))
for k, c in SETC.items():
    put('set_' + k, svg(48, f'<polygon points="{poly(ngon(25,26,21,6,pi/6))}" fill="{INK}" opacity="0.4"/>' + litpoly(ngon(24, 24, 21, 6, pi/6), sh(c, -0.45))
        + f'<polygon points="{poly(ngon(24,24,15.5,6,pi/6))}" fill="{SL}" stroke="{c}" stroke-width="2"/><g transform="translate(24 24) scale(0.72) translate(-24 -24)">{G[SETG[k]](c)}</g>'))

# ---------------- Crates (64): field / supply / vault, closed + open ----------------
CR = {'field': (SL3, AM), 'supply': (sh(GR, -0.35), GR), 'vault': (sh(MG, -0.45), GD)}
def crate(k, opened):
    body, trim = CR[k]
    base = f'<ellipse cx="33" cy="56" rx="26" ry="5" fill="{INK}" opacity="0.4"/>' + block(8, 26, 48, 28, body, 4) + f'<rect x="8" y="34" width="48" height="5" fill="{trim}" stroke="{INK}" stroke-width="2"/><rect x="27" y="28" width="10" height="24" fill="{trim}" stroke="{INK}" stroke-width="2"/>'
    if k == 'vault': base += f'<circle cx="32" cy="42" r="5" fill="{SL}" {S2}/><circle cx="32" cy="42" r="2" fill="{GD}"/>'
    if k == 'supply': base += f'<path d="M14 46 h8 M42 46 h8" stroke="{INK}" stroke-width="2.5"/>'
    if not opened:
        lid = block(6, 16, 52, 13, sh(body, 0.12), 3) + f'<rect x="27" y="16" width="10" height="13" fill="{trim}" stroke="{INK}" stroke-width="2"/>'
        return svg(64, base + lid)
    glow = f'<path d="M12 28 L4 4 M32 26 V0 M52 28 L60 4" stroke="{trim}" stroke-width="5" opacity="0.5" stroke-linecap="round"/><ellipse cx="32" cy="27" rx="22" ry="5" fill="{GD}"/><ellipse cx="32" cy="27" rx="13" ry="2.5" fill="#ffffff"/>'
    lid = f'<g transform="rotate(-24 8 20)">{block(6, 8, 52, 13, sh(body, 0.12), 3)}<rect x="27" y="8" width="10" height="13" fill="{trim}" stroke="{INK}" stroke-width="2"/></g>'
    return svg(64, lid + base + glow)
for k in CR:
    put('crate_' + k, crate(k, False)); put('crate_' + k + '_open', crate(k, True))
put('crate_open_fx', svg(64, f'<polygon points="{poly(star(32,32,31,12,12))}" fill="{GD}" opacity="0.35"/><polygon points="{poly(star(32,32,22,9,8,0))}" fill="{GD}" opacity="0.8"/><circle cx="32" cy="32" r="8" fill="#ffffff"/>'))

# ---------------- Currencies (48) ----------------
put('cur_coin', svg(48, G['coin'](GD))); put('cur_gem', svg(48, G['gem'](MG))); put('cur_cash', svg(48, G['cash'](GR)))
put('cur_scrap', svg(48, f'<polygon points="{poly(star(18,28,10,7,7,0.2))}" fill="{SL3}" {S2}/><circle cx="18" cy="28" r="3" fill="{INK}"/><rect x="24" y="12" width="14" height="8" rx="1" fill="{RU}" {S2} transform="rotate(20 31 16)"/><path d="M27 30 L38 26 L40 34 L30 38Z" fill="{sh(WH,-0.3)}" {S2}/><circle cx="34" cy="32" r="1.5" fill="{INK}"/>'))
put('cur_key', svg(48, f'<circle cx="16" cy="24" r="8" fill="{GD}" {S2}/><circle cx="16" cy="24" r="3" fill="{SL}"/><rect x="22" y="21" width="18" height="6" rx="1" fill="{GD}" {S2}/><path d="M33 27 v5 M38 27 v4" stroke="{INK}" stroke-width="3"/><path d="M33 27 v4 M38 27 v3" stroke="{GD}" stroke-width="1.5"/>'))
put('cur_corecore', svg(48, G['corechip'](RU)))
put('cur_shard', svg(48, f'<path d="M24 6 L33 20 L27 42 L17 22Z" fill="{sh(CY,-0.3)}" {S2}/><path d="M24 6 L27 42 L17 22Z" fill="{sh(CY,0.2)}"/><path d="M33 20 L27 42 L24 6" fill="{CY}"/><path d="M12 30 L16 38 L10 38Z M36 32 L40 38 L34 39Z" fill="{RU}" {S2}/>'))

# ---------------- Outpost: terrain, network, misc (64) ----------------
def tile(c, extra=''): return svg(64, f'<rect x="0" y="0" width="64" height="64" fill="{c}"/>' + extra)
put('tile_ash', tile('#2b2a2e', ''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#353439"/>' for x, y, r in ((10, 12, 3), (40, 8, 2), (52, 36, 4), (20, 48, 2.5), (34, 30, 1.5), (58, 58, 2)))
                     + f'<path d="M4 30 q6 -3 12 0 M36 52 q6 -3 12 0" stroke="#24232a" stroke-width="2" fill="none"/>'))
put('tile_rock', tile('#2e333b', f'<polygon points="6,40 14,26 28,22 34,36 24,48" fill="{SL3}" {S2}/><polygon points="14,28 28,24 26,32 16,36" fill="#4d5868"/><polygon points="38,14 50,10 58,22 46,28" fill="{SL3}" {S2}/><polygon points="40,14 50,12 48,18" fill="#4d5868"/><circle cx="48" cy="48" r="4" fill="{SL3}" {S2}/>'))
put('tile_water', tile('#163a4a', f'<path d="M4 18 q6 -4 12 0 t12 0 M30 38 q6 -4 12 0 t12 0 M8 52 q6 -4 12 0" stroke="#2b6d84" stroke-width="2.5" fill="none" stroke-linecap="round"/><path d="M40 12 q4 -2 8 0" stroke="#5ab4cc" stroke-width="2" fill="none"/>'))
PW = GD
def conduit_core(): return f'<rect x="22" y="22" width="20" height="20" rx="4" fill="{SL3}" {S}/><circle cx="32" cy="32" r="4.5" fill="{PW}" stroke="{INK}" stroke-width="2"/>'
put('op_conduit', svg(64, conduit_core()))
STUB = {'n': (27, 0, 10, 26), 's': (27, 38, 10, 26), 'w': (0, 27, 26, 10), 'e': (38, 27, 26, 10)}
for d, (x, y, ww, hh) in STUB.items():
    lx = f'M32 {y} V{y+hh}' if d in 'ns' else f'M{x} 32 H{x+ww}'
    put('op_conduit_' + d, svg(64, f'<rect x="{x}" y="{y}" width="{ww}" height="{hh}" fill="{SL3}" {S}/><path d="{lx}" stroke="{PW}" stroke-width="2.5" stroke-dasharray="5 3"/>'))
put('op_plug', svg(64, f'<circle cx="32" cy="32" r="14" fill="{SL}" stroke="{RD}" stroke-width="3" stroke-dasharray="5 3"/><path d="M26 22 V30 M38 22 V30" stroke="{INK}" stroke-width="5"/><path d="M26 22 V30 M38 22 V30" stroke="{RD}" stroke-width="2.5"/><path d="M24 30 H40 V36 A8 8 0 0 1 24 36Z" fill="{RD}" {S2}/>'))
put('op_vein', svg(64, f'<path d="M4 50 L18 36 L26 40 L40 22 L60 14" fill="none" stroke="{INK}" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/><path d="M4 50 L18 36 L26 40 L40 22 L60 14" fill="none" stroke="{sh(MG,-0.2)}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>'
                    + ''.join(f'<path d="M{x} {y-5} L{x+4} {y} L{x} {y+5} L{x-4} {y}Z" fill="{MG}" stroke="{INK}" stroke-width="1.5"/>' for x, y in ((18, 36), (40, 22), (54, 16)))))
put('op_plot_locked', svg(64, f'<rect x="3" y="3" width="58" height="58" rx="6" fill="{INK}" opacity="0.55"/><rect x="3" y="3" width="58" height="58" rx="6" fill="none" stroke="{SL3}" stroke-width="3" stroke-dasharray="8 5"/><g transform="translate(8 8)">{G["lock"](GD)}</g>'))
put('op_builder', svg(64, f'<ellipse cx="33" cy="56" rx="14" ry="4" fill="{INK}" opacity="0.4"/>' + disc(32, 32, 14, AM) + f'<path d="M18 28 C18 14 46 14 46 28Z" fill="{GD}" {S}/><rect x="16" y="26" width="32" height="4" rx="2" fill="{SL3}" {S2}/><rect x="24" y="34" width="16" height="5" rx="2" fill="{INK}"/><circle cx="28" cy="36.5" r="1.5" fill="{CY}"/><circle cx="36" cy="36.5" r="1.5" fill="{CY}"/><g transform="translate(30 26) scale(0.6)">{G["hammer"](SL3)}</g>'))
put('op_timer', svg(48, badge(CY, 'hourglass', CY)))

# ---------------- Outpost buildings: top-down, multi-tile footprints, 3 level bands ----------------
# footprint (w,h) in 64px tiles; category colour on the trim stripe.
OPB = {'relay': ((1, 1), GD), 'mill': ((2, 2), AM), 'refinery': ((2, 2), AM), 'gemmine': ((2, 2), MG), 'keyforge': ((2, 1), GD),
       'research': ((2, 2), GR), 'barracks': ((2, 2), RD), 'archive': ((1, 2), CY), 'warehouse': ((2, 1), SL3), 'scrapyard': ((2, 2), RU), 'beacon': ((1, 1), CY)}
def pad(W, H, c, lvl):
    trim = GD if lvl == 3 else c
    s = (f'<rect x="5" y="7" width="{W-8}" height="{H-8}" rx="8" fill="{INK}" opacity="0.45"/>'
         f'<rect x="3" y="3" width="{W-6}" height="{H-6}" rx="8" fill="#3a3f47" {S}/>'
         f'<rect x="7" y="7" width="{W-14}" height="{H-14}" rx="5" fill="{SL2}" stroke="{trim}" stroke-width="{2 + (lvl-1)}"/>')
    s += ''.join(f'<rect x="{x}" y="{y}" width="5" height="5" fill="{SL3}"/>' for x, y in ((10, 10), (W-15, 10), (10, H-15), (W-15, H-15)))
    return s
def lights(W, H, lvl, c):  # level 3 gets amber running lights on the pad edge
    if lvl < 3: return ''
    return ''.join(f'<circle cx="{x}" cy="{H-5}" r="2" fill="{GD}" stroke="{INK}" stroke-width="1"/>' for x in range(16, W-10, 16))
def roof(x, y, ww, hh, c, r=4): return block(x, y, ww, hh, c, r)
def vents(x, y, n): return ''.join(f'<rect x="{x+i*7}" y="{y}" width="4" height="10" rx="1" fill="{INK}"/>' for i in range(n))
def b_relay(l):
    W = H = 64; s = pad(W, H, GD, l) + disc(32, 32, 12 + l, SL3) + f'<circle cx="32" cy="32" r="{5+l}" fill="{GD}" {S2}/><circle cx="31" cy="31" r="2" fill="#fff"/>'
    s += ''.join(f'<rect x="29" y="5" width="6" height="10" fill="{SL3}" {S2} transform="rotate({a} 32 32)"/>' for a in range(0, 360, 90 if l < 3 else 45)[: 2 + 2*l])
    return W, H, s
def b_mill(l):
    W = H = 128; s = pad(W, H, AM, l) + roof(16, 20, 64, 60, sh(AM, -0.15), 5) + f'<path d="M20 50 H76" stroke="{INK}" stroke-width="3"/>' + vents(26, 30, 5)
    s += disc(96, 40, 14, SL3) + f'<path d="M96 40 L96 28 M96 40 L106 46 M96 40 L86 46" stroke="{AM}" stroke-width="4" stroke-linecap="round"/><circle cx="96" cy="40" r="3" fill="{INK}"/>'
    s += ''.join(f'<rect x="{18+i*20}" y="88" width="16" height="22" rx="2" fill="{GR}" {S2}/><circle cx="{26+i*20}" cy="99" r="4" fill="{sh(GR,-0.4)}"/>' for i in range(1 + l))
    if l >= 2: s += roof(84, 64, 30, 26, sh(WH, -0.35), 3) + f'<circle cx="99" cy="77" r="5" fill="{GD}" {S2}/>'
    return W, H, s + lights(W, H, l, AM)
def b_refinery(l):
    W = H = 128; s = pad(W, H, AM, l)
    s += ''.join(disc(x, y, 18, sh(WH, -0.3)) + f'<circle cx="{x}" cy="{y}" r="8" fill="{GD}" {S2}/>' for x, y in ((38, 40), (90, 40), (38, 90))[: 1 + l])
    s += f'<path d="M38 58 V72 H90 V58" fill="none" stroke="{INK}" stroke-width="7"/><path d="M38 58 V72 H90 V58" fill="none" stroke="{AM}" stroke-width="3"/>'
    s += roof(70, 74, 42, 38, sh(AM, -0.2), 4) + vents(78, 84, 4)
    return W, H, s + lights(W, H, l, AM)
def b_gemmine(l):
    W = H = 128; s = pad(W, H, MG, l)
    s += f'<polygon points="{poly(ngon(64,62,38,8,pi/8))}" fill="{INK}" {S}/><polygon points="{poly(ngon(64,62,28,8,pi/8))}" fill="#25182a" stroke="{sh(MG,-0.3)}" stroke-width="3"/>'
    s += ''.join(f'<path d="M{x} {y-7} L{x+5} {y} L{x} {y+7} L{x-5} {y}Z" fill="{MG}" stroke="{INK}" stroke-width="2"/>' for x, y in ((56, 58), (72, 66), (62, 74), (70, 52))[: 1 + l])
    s += f'<path d="M30 20 L64 38 L98 20" fill="none" stroke="{INK}" stroke-width="7"/><path d="M30 20 L64 38 L98 20" fill="none" stroke="{SL3}" stroke-width="3"/>' + disc(64, 30, 9, SL3) + f'<rect x="61" y="30" width="6" height="22" fill="{GD}" {S2}/>'
    if l >= 2: s += roof(14, 92, 30, 24, sh(MG, -0.3), 3) + f'<path d="M20 104 h18" stroke="{GD}" stroke-width="3"/>'
    if l >= 3: s += roof(84, 92, 30, 24, sh(MG, -0.3), 3) + f'<path d="M90 104 h18" stroke="{GD}" stroke-width="3"/>'
    return W, H, s + lights(W, H, l, MG)
def b_keyforge(l):
    W, H = 128, 64; s = pad(W, H, GD, l) + roof(12, 12, 56, 40, sh(RU, -0.1), 4) + f'<circle cx="40" cy="32" r="10" fill="{GD}" {S}/><circle cx="40" cy="32" r="5" fill="#fff4c8"/>'
    s += disc(92, 32, 16, SL3) + f'<g transform="translate(70 10) scale(0.9)">{G["hammer"](sh(WH,-0.2))}</g>'
    if l >= 2: s += f'<rect x="16" y="14" width="10" height="10" rx="2" fill="{INK}"/><rect x="18" y="16" width="6" height="6" fill="{AM}"/>'
    if l >= 3: s += f'<rect x="54" y="14" width="10" height="10" rx="2" fill="{INK}"/><rect x="56" y="16" width="6" height="6" fill="{AM}"/>'
    return W, H, s + lights(W, H, l, GD)
def b_research(l):
    W = H = 128; s = pad(W, H, GR, l) + roof(14, 46, 100, 66, sh(WH, -0.35), 6)
    s += disc(64, 46, 26, sh(GR, -0.1)) + f'<path d="M48 46 A16 16 0 0 1 80 46" fill="none" stroke="{INK}" stroke-width="5"/><rect x="60" y="20" width="8" height="22" rx="2" fill="{SL3}" {S2} transform="rotate(30 64 46)"/>'
    s += ''.join(f'<rect x="{22+i*22}" y="84" width="14" height="18" rx="2" fill="{CY}" {S2}/>' for i in range(1 + l))
    return W, H, s + lights(W, H, l, GR)
def b_barracks(l):
    W = H = 128; s = pad(W, H, RD, l) + roof(14, 14, 62, 44, sh(RD, -0.15), 4) + f'<path d="M14 36 H76" stroke="{INK}" stroke-width="3"/>'
    s += f'<rect x="16" y="66" width="96" height="46" rx="4" fill="#47403a" {S}/>' + ''.join(f'<circle cx="{28+i*14}" cy="{80+(i%2)*14}" r="5" fill="{GR}" {S2}/>' for i in range(2 + 2*l))
    s += f'<rect x="88" y="14" width="4" height="40" fill="{SL3}" {S2}/><path d="M92 16 H112 L106 24 L112 32 H92Z" fill="{RD}" {S2}/>'
    return W, H, s + lights(W, H, l, RD)
def b_archive(l):
    W, H = 64, 128; s = pad(W, H, CY, l) + roof(12, 12, 40, 104, sh(CY, -0.45), 5)
    s += ''.join(f'<rect x="18" y="{22+i*18}" width="28" height="10" rx="2" fill="{SL}" stroke="{CY}" stroke-width="2"/>' for i in range(2 + l))
    s += disc(32, 100, 8, GD)
    return W, H, s + lights(W, H, l, CY)
def b_warehouse(l):
    W, H = 128, 64; s = pad(W, H, SL3, l) + roof(10, 10, 108, 44, sh(WH, -0.4), 4)
    s += ''.join(f'<path d="M{14+i*14} 14 V50" stroke="{INK}" stroke-width="2" opacity="0.6"/>' for i in range(8))
    s += ''.join(block(16 + i*22, 20, 18, 24, AM if i % 2 == 0 else GR, 2) for i in range(1 + l))
    return W, H, s + lights(W, H, l, SL3)
def b_scrapyard(l):
    W = H = 128; s = pad(W, H, RU, l)
    piles = ((40, 44), (84, 40), (44, 88), (90, 86))
    for i, (x, y) in enumerate(piles[: 1 + l]):
        s += f'<polygon points="{poly(star(x,y,20,13,7,i))}" fill="{sh(RU,-0.35)}" {S}/><polygon points="{poly(star(x-1,y-1,12,8,7,i+0.3))}" fill="{RU}"/>' + f'<rect x="{x-5}" y="{y-3}" width="10" height="5" fill="{SL3}" stroke="{INK}" stroke-width="1.5"/>'
    s += f'<path d="M100 110 L112 72 L118 72" fill="none" stroke="{INK}" stroke-width="6"/><path d="M100 110 L112 72 L118 72" fill="none" stroke="{GD}" stroke-width="3"/><circle cx="118" cy="78" r="5" fill="{SL3}" {S2}/>'
    return W, H, s + lights(W, H, l, RU)
def b_beacon(l):
    W = H = 64; s = pad(W, H, CY, l) + f'<path d="M22 50 L32 14 L42 50Z" fill="{SL3}" {S}/>' + disc(32, 18, 6 + l, CY)
    s += ''.join(f'<circle cx="32" cy="18" r="{12+i*6}" fill="none" stroke="{CY}" stroke-width="2" opacity="{0.8-i*0.25}"/>' for i in range(l))
    return W, H, s
FN = {'relay': b_relay, 'mill': b_mill, 'refinery': b_refinery, 'gemmine': b_gemmine, 'keyforge': b_keyforge, 'research': b_research,
      'barracks': b_barracks, 'archive': b_archive, 'warehouse': b_warehouse, 'scrapyard': b_scrapyard, 'beacon': b_beacon}
for k, f in FN.items():
    for l in (1, 2, 3):
        W, H, body = f(l); assert (W // 64, H // 64) == OPB[k][0], k
        put(f'op_{k}_{l}', svgwh(W, H, body))

# ---------------- Decor (64) ----------------
def dsh(rx=20): return f'<ellipse cx="34" cy="54" rx="{rx}" ry="5" fill="{INK}" opacity="0.4"/>'
D = {}
D['smelter'] = dsh() + block(14, 22, 36, 30, sh(RU, -0.1), 4) + f'<rect x="38" y="6" width="8" height="18" fill="{SL3}" {S2}/><path d="M22 34 h20 v10 h-20z" fill="{GD}" {S2}/>'
D['crates'] = dsh(24) + block(8, 30, 22, 22, AM, 2) + block(30, 34, 20, 18, sh(AM, -0.2), 2) + block(18, 12, 20, 20, sh(AM, 0.1), 2)
D['bookshelf'] = dsh() + block(12, 10, 40, 42, sh(RU, -0.4), 3) + ''.join(f'<rect x="{16+i*6}" y="{y}" width="4" height="12" fill="{(CY,GR,MG,AM,GD,RD)[i]}" stroke="{INK}" stroke-width="1"/>' for y in (14, 32) for i in range(6))
D['orrery'] = dsh() + f'<circle cx="32" cy="30" r="20" fill="none" stroke="{SL3}" stroke-width="3"/><ellipse cx="32" cy="30" rx="20" ry="8" fill="none" stroke="{GD}" stroke-width="2"/>' + disc(32, 30, 7, GD) + f'<circle cx="52" cy="30" r="4" fill="{CY}" {S2}/><circle cx="18" cy="16" r="3" fill="{MG}" {S2}/><rect x="28" y="48" width="8" height="6" fill="{SL3}" {S2}/>'
D['yard'] = dsh(26) + f'<rect x="6" y="14" width="52" height="38" rx="3" fill="#3d4a3a" {S}/>' + ''.join(f'<path d="M{x} 18 V48" stroke="{sh(WH,-0.3)}" stroke-width="2"/>' for x in (16, 32, 48)) + f'<circle cx="32" cy="33" r="7" fill="none" stroke="{sh(WH,-0.3)}" stroke-width="2"/>'
D['dummy'] = dsh(12) + f'<rect x="30" y="34" width="4" height="18" fill="{RU}" {S2}/><path d="M18 30 H46" stroke="{INK}" stroke-width="6"/><path d="M18 30 H46" stroke="{AM}" stroke-width="3"/>' + disc(32, 22, 9, sh(AM, 0.2)) + f'<circle cx="32" cy="22" r="3" fill="{RD}"/>'
D['lamp'] = f'<circle cx="32" cy="16" r="16" fill="{GD}" opacity="0.18"/>' + dsh(8) + f'<rect x="30" y="20" width="4" height="32" fill="{SL3}" {S2}/>' + disc(32, 16, 7, GD)
D['brazier'] = f'<circle cx="32" cy="24" r="20" fill="{AM}" opacity="0.18"/>' + dsh(12) + f'<path d="M20 30 H44 L38 46 H26Z" fill="{SL3}" {S}/><path d="M32 8 C38 16 42 20 40 26 C38 31 26 31 24 26 C22 20 28 18 32 8Z" fill="{RU}" {S2}/><path d="M32 16 C35 20 36 23 35 26 C33 28 30 28 29 26 C28 23 30 21 32 16Z" fill="{GD}"/><path d="M28 46 L24 54 M36 46 L40 54" stroke="{INK}" stroke-width="3"/>'
D['tree'] = dsh(18) + f'<rect x="29" y="40" width="6" height="12" fill="{RU}" {S2}/>' + disc(32, 28, 18, sh(GR, -0.25)) + f'<circle cx="26" cy="22" r="7" fill="{GR}"/><circle cx="38" cy="30" r="5" fill="{sh(GR,-0.1)}"/>'
D['shrub'] = dsh(16) + disc(24, 40, 10, sh(GR, -0.3)) + disc(40, 40, 10, sh(GR, -0.2)) + disc(32, 32, 11, GR)
D['pond'] = f'<ellipse cx="32" cy="34" rx="28" ry="20" fill="{sh(SL3,-0.2)}" {S}/><ellipse cx="32" cy="34" rx="22" ry="15" fill="#1d5468"/><path d="M18 30 q5 -3 10 0 M34 40 q5 -3 10 0" stroke="#5ab4cc" stroke-width="2" fill="none"/><circle cx="44" cy="28" r="4" fill="{GR}" {S2}/>'
D['banner'] = dsh(10) + f'<rect x="20" y="6" width="4" height="46" fill="{SL3}" {S2}/><path d="M24 8 H48 L42 18 L48 28 H24Z" fill="{RU}" {S2}/><circle cx="34" cy="18" r="4" fill="{GD}" stroke="{INK}" stroke-width="1.5"/>'
D['trophy'] = dsh(14) + f'<rect x="18" y="42" width="28" height="10" rx="2" fill="{SL3}" {S}/><g transform="translate(8 2)">{G["crown"](GD)}</g><path d="M22 22 H42 V30 C42 36 37 39 32 39 C27 39 22 36 22 30Z" fill="{GD}" {S2}/><rect x="29" y="38" width="6" height="5" fill="{GD}" {S2}/>'
for k, v in D.items(): put('dc_' + k, svg(64, v))

# ---------------- Reforge tree nodes (64) ----------------
def rfnode(c, inner, glow=True):
    g = f'<polygon points="{poly(ngon(32,32,31,6))}" fill="{c}" opacity="0.25"/>' if glow else ''
    return svg(64, g + f'<polygon points="{poly(ngon(33,34,27,6))}" fill="{INK}" opacity="0.4"/>' + litpoly(ngon(32, 32, 27, 6), sh(c, -0.4))
               + f'<polygon points="{poly(ngon(32,32,20,6))}" fill="{SL}" stroke="{c}" stroke-width="2.5"/><g transform="translate(8 8)">{inner}</g>')
put('rf_root', rfnode(RU, G['corechip'](CY)))
put('rf_power', rfnode(RD, G['sword'](RD)))
put('rf_economy', rfnode(GD, G['coin'](GD)))
put('rf_mastery', rfnode(VI, G['star5'](VI)))
put('rf_node_locked', svg(64, f'<polygon points="{poly(ngon(32,32,27,6))}" fill="{SL2}" {S}/><polygon points="{poly(ngon(32,32,20,6))}" fill="{INK}" stroke="{SL3}" stroke-width="2" stroke-dasharray="4 3"/><g transform="translate(8 8)">{G["lock"](GD)}</g>'))
put('rf_node_owned', svg(64, f'<polygon points="{poly(ngon(32,32,31,6))}" fill="{GD}" opacity="0.3"/>' + litpoly(ngon(32, 32, 27, 6), sh(GD, -0.3)) + f'<polygon points="{poly(ngon(32,32,20,6))}" fill="{SL}" stroke="{GD}" stroke-width="2.5"/><path d="M22 32 L29 39 L42 25" fill="none" stroke="{INK}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/><path d="M22 32 L29 39 L42 25" fill="none" stroke="{GR}" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>'))

# ---------------- UI glyphs (48) ----------------
put('ui_hotkey_frame', svg(48, f'<rect x="4" y="6" width="40" height="38" rx="7" fill="{INK}" opacity="0.4"/><rect x="3" y="3" width="40" height="38" rx="7" fill="{SL2}" {S}/><rect x="7" y="6" width="32" height="28" rx="4" fill="{SL3}"/><path d="M9 8 H37" stroke="{sh(SL3,0.4)}" stroke-width="2"/>'))
put('ui_cooldown', svg(48, f'<circle cx="24" cy="24" r="20" fill="{INK}" opacity="0.6"/><path d="M24 24 L24 4 A20 20 0 0 1 43 30Z" fill="{SL3}" opacity="0.9"/><circle cx="24" cy="24" r="20" fill="none" stroke="{CY}" stroke-width="2"/>'))
for k, (c, g) in {'reroll': (GR, 'reroll'), 'banish': (RD, 'ban'), 'collect': (GD, 'collect'), 'rotate': (CY, 'rotate'), 'demolish': (RD, 'hammer'), 'move': (CY, 'move'), 'blueprint': (CY, 'blueprint')}.items():
    put('ui_' + k, svg(48, badge(c, g)))

for n, s in OUTS.items(): w(n, s)
print(len(OUTS))
