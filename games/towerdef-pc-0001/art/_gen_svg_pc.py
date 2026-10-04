import os
OUT='/home/user/Game/games/towerdef-pc-0001/art'
INK='#0d1014'; SL='#1b2027'; SL2='#2a313b'; SL3='#3a4350'
CY='#3fd8e8'; AM='#f2a93b'; GR='#6bd46b'; RD='#e8434f'; MG='#e04bc0'; WH='#eef2f5'; RU='#d9773a'; GD='#ffd447'
def sh(c,f):
    c=c.lstrip('#'); r,g,b=[int(c[i:i+2],16) for i in (0,2,4)]
    if f>0: r,g,b=[int(v+(255-v)*f) for v in (r,g,b)]
    else: r,g,b=[int(v*(1+f)) for v in (r,g,b)]
    return '#%02x%02x%02x'%(r,g,b)
S=f'stroke="{INK}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"'
S2=f'stroke="{INK}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"'
def svg(vb,body): return f'<svg xmlns="http://www.w3.org/2000/svg" width="{vb}" height="{vb}" viewBox="0 0 {vb} {vb}">{body}</svg>\n'
def w(n,s): open(f'{OUT}/{n}.svg','w').write(s)
def block(x,y,ww,hh,c,r=4):  # lit block: base, highlight top-left, shadow bottom-right
    return (f'<rect x="{x}" y="{y}" width="{ww}" height="{hh}" rx="{r}" fill="{sh(c,-0.35)}" {S}/>'
            f'<rect x="{x+2}" y="{y+2}" width="{ww-6}" height="{hh-6}" rx="{max(r-2,1)}" fill="{c}"/>'
            f'<path d="M{x+3} {y+hh-8} V{y+4} Q{y and x+3 or x+3} {y+3} {x+5} {y+3} H{x+ww-8}" fill="none" stroke="{sh(c,0.45)}" stroke-width="2"/>')
def disc(cx,cy,r,c):
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{sh(c,-0.35)}" {S}/><circle cx="{cx-1}" cy="{cy-1}" r="{r-2.5}" fill="{c}"/>'
            f'<path d="M{cx-r*0.6} {cy+r*0.1} A{r*0.62} {r*0.62} 0 0 1 {cx+r*0.1} {cy-r*0.6}" fill="none" stroke="{sh(c,0.5)}" stroke-width="2"/>')
def plate(c): # 64 tile base
    return (f'<rect x="4" y="6" width="58" height="56" rx="8" fill="{INK}" opacity="0.45"/>'
            f'<rect x="3" y="3" width="56" height="56" rx="8" fill="{SL2}" {S}/>'
            f'<rect x="7" y="7" width="48" height="48" rx="5" fill="{SL}" stroke="{c}" stroke-width="2" opacity="0.9"/>'
            + ''.join(f'<circle cx="{a}" cy="{b}" r="1.6" fill="{SL3}"/>' for a,b in ((10,10),(52,10),(10,52),(52,52))))
def ibg(c,shape='round'):  # badge frame
    return (f'<rect x="4" y="5" width="41" height="41" rx="9" fill="{INK}" opacity="0.4"/><rect x="3" y="3" width="41" height="41" rx="9" fill="{sh(c,-0.55)}" {S}/>'
            f'<rect x="6" y="6" width="35" height="35" rx="6" fill="{SL}" stroke="{c}" stroke-width="2"/>')
G={}  # glyphs centered at 24,24 approx 26 size

B={}
B['railgun']=plate(CY)+block(14,26,34,22,sh(CY,-0.2),4)+f'<rect x="28" y="6" width="7" height="32" rx="1" fill="{SL3}" {S}/><rect x="26" y="14" width="11" height="4" fill="{CY}"/><rect x="26" y="22" width="11" height="4" fill="{CY}"/><circle cx="31.5" cy="38" r="5" fill="{INK}"/><circle cx="31.5" cy="38" r="2" fill="{WH}"/>'
B['flak']=plate(CY)+disc(31,36,14,sh(CY,-0.1))+''.join(f'<rect x="{x}" y="9" width="5" height="20" rx="1" fill="{SL3}" {S2}/>' for x in (21,29,37))+f'<circle cx="31" cy="37" r="5" fill="{INK}"/><circle cx="14" cy="14" r="3" fill="{GD}"/><circle cx="48" cy="12" r="2.5" fill="{GD}"/>'
B['beacon']=plate(GR)+f'<path d="M24 52 L31 18 L38 52Z" fill="{SL3}" {S}/>'+disc(31,17,7,GD)+f'<path d="M14 10 A22 22 0 0 0 14 26 M48 10 A22 22 0 0 1 48 26" fill="none" stroke="{GR}" stroke-width="3"/><path d="M26 38 h10" stroke="{INK}" stroke-width="2.5"/>'
B['refinery']=plate(AM)+block(10,28,30,24,AM,3)+f'<rect x="42" y="14" width="8" height="38" rx="2" fill="{sh(AM,-0.3)}" {S}/><circle cx="25" cy="22" r="8" fill="{SL3}" {S}/><path d="M25 17 v10 M20 22 h10" stroke="{GD}" stroke-width="2.5"/><circle cx="25" cy="41" r="6" fill="{GD}" {S2}/><path d="M25 38 v6" stroke="{INK}" stroke-width="2"/>'
B['barricade']=plate(GR)+''.join(block(x,y,14,12,sh(GR,-0.1),2) for x,y in ((10,38),(24,38),(38,38),(17,26),(31,26),(24,14)))+f'<path d="M8 52 H54" stroke="{INK}" stroke-width="3"/>'
I={}
I['icon_stats']=ibg(CY)+f'<rect x="12" y="26" width="6" height="11" fill="{CY}" {S2}/><rect x="21" y="18" width="6" height="19" fill="{GR}" {S2}/><rect x="30" y="12" width="6" height="25" fill="{AM}" {S2}/>'
I['icon_history']=ibg(AM)+f'<circle cx="24" cy="24" r="12" fill="{SL3}" {S2}/><path d="M24 16 V24 L30 28" fill="none" stroke="{WH}" stroke-width="3"/><path d="M10 14 L13 20 L18 16" fill="none" stroke="{AM}" stroke-width="2.5"/>'
I['icon_trophy']=ibg(GD)+f'<path d="M16 12 H32 V20 C32 26 28 29 24 29 C20 29 16 26 16 20Z" fill="{GD}" {S2}/><path d="M16 15 H11 C11 21 14 23 17 23 M32 15 H37 C37 21 34 23 31 23" fill="none" stroke="{INK}" stroke-width="2.5"/><rect x="21" y="29" width="6" height="5" fill="{GD}" {S2}/><rect x="16" y="34" width="16" height="4" rx="1" fill="{SL3}" {S2}/>'
I['icon_menu']=ibg(WH)+''.join(f'<rect x="13" y="{y}" width="22" height="4" rx="2" fill="{WH}"/>' for y in (15,22,29))
I['icon_save']=ibg(GR)+f'<rect x="13" y="12" width="22" height="24" rx="2" fill="{SL3}" {S2}/><rect x="17" y="12" width="14" height="8" fill="{GR}"/><rect x="17" y="26" width="14" height="10" fill="{WH}"/>'
I['icon_mod']=ibg(RD)+f'<path d="M24 11 L37 34 H11Z" fill="{RD}" {S2}/><path d="M24 19 v8" stroke="{WH}" stroke-width="3"/><circle cx="24" cy="31" r="1.8" fill="{WH}"/>'
I['icon_endless']=ibg(MG)+f'<path d="M14 24 C14 17 22 17 24 24 C26 31 34 31 34 24 C34 17 26 17 24 24 C22 31 14 31 14 24Z" fill="none" stroke="{MG}" stroke-width="4"/>'
I['icon_info']=ibg(CY)+f'<circle cx="24" cy="15" r="2.5" fill="{WH}"/><rect x="21.5" y="20" width="5" height="15" rx="2" fill="{WH}"/>'
I['lane_arrow']=f'<path d="M6 24 H28 V12 L44 24 L28 36 V24" fill="{RD}" {S}/>'
for k,v in B.items(): w(k,svg(64,v))
for k,v in I.items(): w(k,svg(48,v))
