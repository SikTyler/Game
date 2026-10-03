import os
OUT='/home/user/Game/games/towerdef-0001/art'
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
B={}
B['gun']=plate(CY)+disc(31,33,13,CY)+block(28,10,7,20,sh(CY,-0.1),2)+f'<rect x="27" y="8" width="9" height="5" rx="1" fill="{INK}"/>'+f'<circle cx="31" cy="34" r="4" fill="{INK}"/>'
B['mortar']=plate(CY)+block(14,16,34,34,CY,6)+f'<circle cx="31" cy="33" r="10" fill="{INK}"/><circle cx="31" cy="33" r="6" fill="{sh(CY,-0.5)}"/><circle cx="29" cy="31" r="2" fill="{sh(CY,0.5)}"/>'
B['tesla']=plate(CY)+f'<rect x="22" y="40" width="18" height="12" rx="2" fill="{SL3}" {S}/>'+block(26,18,10,24,sh(CY,-0.15),2)+disc(31,17,8,CY)+f'<path d="M14 14 L20 20 L16 22 L23 28" fill="none" stroke="{WH}" stroke-width="2.5"/><path d="M48 14 L42 20 L46 22 L39 28" fill="none" stroke="{WH}" stroke-width="2.5"/>'
B['armory']=plate(GR)+block(12,22,38,28,GR,3)+f'<path d="M10 24 L31 11 L52 24 Z" fill="{sh(GR,-0.3)}" {S}/><rect x="25" y="34" width="12" height="16" fill="{INK}"/><path d="M20 30 h4 M38 30 h4" stroke="{INK}" stroke-width="3"/><path d="M31 15 l2 4 h4 l-3 3 1 4 -4 -2 -4 2 1 -4 -3 -3 h4z" fill="{WH}"/>'
B['bulwark']=plate(GR)+f'<path d="M31 10 L49 16 V30 C49 42 40 49 31 53 C22 49 13 42 13 30 V16 Z" fill="{sh(GR,-0.35)}" {S}/><path d="M31 14 L45 19 V30 C45 40 38 46 31 49 Z" fill="{GR}"/><path d="M31 14 L17 19 V30 C17 40 24 46 31 49 Z" fill="{sh(GR,0.3)}"/><path d="M31 22 v18 M22 31 h18" stroke="{WH}" stroke-width="5" stroke-linecap="round"/>'
B['mine']=plate(AM)+block(12,30,38,20,sh(AM,-0.2),3)+f'<path d="M18 30 L26 12 L36 12 L44 30" fill="{SL3}" {S}/><path d="M24 22 h14" stroke="{INK}" stroke-width="2.5"/><path d="M20 40 l5 -5 5 5 -5 5z M33 41 l4 -4 4 4 -4 4z" fill="{GD}" {S2}/>'
B['oilmill']=plate(AM)+block(10,26,26,26,AM,3)+f'<rect x="38" y="12" width="10" height="40" rx="2" fill="{sh(AM,-0.3)}" {S}/><rect x="40" y="9" width="6" height="5" fill="{INK}"/><path d="M23 32 C18 39 18 44 23 46 C28 44 28 39 23 32Z" fill="{INK}"/><circle cx="21" cy="42" r="1.5" fill="{WH}"/><path d="M13 22 h20" stroke="{INK}" stroke-width="3"/>'
B['bounty']=plate(AM)+block(11,18,40,32,AM,4)+f'<path d="M11 26 h40" stroke="{INK}" stroke-width="3"/><circle cx="31" cy="38" r="8" fill="{GD}" {S2}/><path d="M31 33 v10 M28.5 35 h5 M28.5 41 h5" stroke="{INK}" stroke-width="2"/><rect x="25" y="12" width="12" height="7" rx="2" fill="{SL3}" {S2}/>'
B['vault']=plate(AM)+block(12,12,38,38,sh(AM,-0.15),5)+f'<circle cx="31" cy="31" r="11" fill="{SL3}" {S}/><circle cx="31" cy="31" r="4" fill="{GD}" {S2}/><path d="M31 20 v4 M31 38 v4 M20 31 h4 M38 31 h4" stroke="{INK}" stroke-width="2.5"/><rect x="45" y="22" width="4" height="18" fill="{INK}"/>'
B['aegis']=plate(GR)+disc(31,32,18,sh(GR,-0.1))+f'<circle cx="31" cy="32" r="11" fill="none" stroke="{WH}" stroke-width="3" stroke-dasharray="6 4"/><path d="M31 25 l6 4 v6 l-6 4 -6 -4 v-6z" fill="{WH}" {S2}/>'
B['core']=(f'<circle cx="33" cy="34" r="27" fill="{INK}" opacity="0.4"/>'+''.join(f'<rect x="28" y="2" width="8" height="12" rx="2" fill="{RU}" {S2} transform="rotate({a} 32 32)"/>' for a in range(0,360,45))
    +disc(32,32,21,sh(WH,-0.15))+f'<circle cx="32" cy="32" r="12" fill="{RU}" {S}/><circle cx="32" cy="32" r="6" fill="{WH}"/><circle cx="30" cy="30" r="2.5" fill="#ffffff"/>')
# enemies 64
def eshadow(): return f'<ellipse cx="34" cy="56" rx="20" ry="5" fill="{INK}" opacity="0.4"/>'
E={}
E['drone']=eshadow()+f'<path d="M32 10 L52 32 L32 52 L12 32Z" fill="{sh(RD,-0.35)}" {S}/><path d="M32 14 L32 48 L15 32Z" fill="{sh(RD,0.2)}"/><path d="M32 14 L49 32 L32 48Z" fill="{RD}"/><circle cx="32" cy="31" r="5" fill="{INK}"/><circle cx="31" cy="30" r="2" fill="{WH}"/>'
E['skitter']=eshadow()+''.join(f'<path d="M{a} {b} L{c} {d}" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>' for a,b,c,d in ((24,26,10,18),(24,34,8,38),(40,26,54,18),(40,34,56,38)))+f'<ellipse cx="32" cy="31" rx="12" ry="15" fill="{sh(RD,-0.35)}" {S}/><ellipse cx="30" cy="28" rx="8" ry="10" fill="{sh(RD,0.15)}"/><circle cx="28" cy="22" r="2.5" fill="{WH}"/><circle cx="36" cy="22" r="2.5" fill="{WH}"/>'
E['hauler']=eshadow()+block(8,12,48,40,sh(RD,-0.15),6)+f'<rect x="16" y="20" width="32" height="10" rx="2" fill="{INK}"/><rect x="18" y="22" width="8" height="6" fill="{GD}"/><rect x="38" y="22" width="8" height="6" fill="{GD}"/><path d="M14 40 h36 M14 46 h36" stroke="{INK}" stroke-width="3"/>'
E['boss']=(f'<ellipse cx="34" cy="58" rx="26" ry="5" fill="{INK}" opacity="0.4"/><path d="M32 3 L40 14 L56 10 L52 26 L61 34 L50 42 L52 58 L32 50 L12 58 L14 42 L3 34 L12 26 L8 10 L24 14Z" fill="{sh(MG,-0.4)}" {S}/>'
    +f'<path d="M32 9 L38 18 L51 15 L48 27 L55 33 L46 39 L47 51 L32 45 L17 51 L18 39 L9 33 L16 27 L13 15 L26 18Z" fill="{MG}"/><circle cx="32" cy="31" r="10" fill="{INK}"/><circle cx="32" cy="31" r="5" fill="{RD}"/><circle cx="30" cy="29" r="2" fill="{WH}"/><path d="M20 22 l6 4 M44 22 l-6 4" stroke="{INK}" stroke-width="3"/>')
E['ranged']=eshadow()+f'<rect x="28" y="4" width="8" height="18" rx="2" fill="{SL3}" {S}/>'+disc(32,34,17,RD)+f'<rect x="22" y="28" width="20" height="10" rx="3" fill="{INK}"/><circle cx="32" cy="33" r="3" fill="{GD}"/>'
E['elite']=eshadow()+f'<path d="M32 6 L54 18 V44 L32 58 L10 44 V18Z" fill="{sh(MG,-0.4)}" {S}/><path d="M32 11 L32 52 L14 41 V21Z" fill="{sh(MG,0.2)}"/><path d="M32 11 L50 21 V41 L32 52Z" fill="{MG}"/><path d="M24 28 L32 34 L40 28" fill="none" stroke="{INK}" stroke-width="4"/><circle cx="32" cy="42" r="3" fill="{WH}"/>'
E['elite_shield']=f'<circle cx="32" cy="32" r="28" fill="{CY}" opacity="0.12"/><circle cx="32" cy="32" r="27" fill="none" stroke="{INK}" stroke-width="6"/><circle cx="32" cy="32" r="27" fill="none" stroke="{CY}" stroke-width="3" stroke-dasharray="14 6"/><path d="M14 18 A24 24 0 0 1 30 8" fill="none" stroke="#ffffff" stroke-width="2"/>'
E['splitter']=eshadow()+disc(24,30,15,RD)+disc(40,34,14,MG)+f'<path d="M32 16 L30 26 L34 32 L30 44" fill="none" stroke="{INK}" stroke-width="3"/><circle cx="22" cy="28" r="3" fill="{WH}"/><circle cx="42" cy="32" r="3" fill="{WH}"/>'
E['mite']=f'<ellipse cx="33" cy="48" rx="12" ry="4" fill="{INK}" opacity="0.4"/>'+disc(32,34,11,sh(MG,0.1))+f'<circle cx="29" cy="31" r="2.5" fill="{WH}"/><circle cx="36" cy="31" r="2.5" fill="{WH}"/><path d="M26 22 L22 16 M38 22 L42 16" stroke="{INK}" stroke-width="3"/>'
E['bolt']=f'<path d="M10 32 L36 22 L56 32 L36 42Z" fill="{sh(RD,-0.3)}" {S}/><path d="M16 32 L36 26 L50 32Z" fill="{GD}"/><path d="M4 32 h8" stroke="{RD}" stroke-width="3" opacity="0.6"/>'
for k,v in {**B,**E}.items(): w(k,svg(64,v))
# icons 48
def ibg(c,shape='round'):  # badge frame
    return (f'<rect x="4" y="5" width="41" height="41" rx="9" fill="{INK}" opacity="0.4"/><rect x="3" y="3" width="41" height="41" rx="9" fill="{sh(c,-0.55)}" {S}/>'
            f'<rect x="6" y="6" width="35" height="35" rx="6" fill="{SL}" stroke="{c}" stroke-width="2"/>')
G={}  # glyphs centered at 24,24 approx 26 size
G['sword']=lambda c: f'<path d="M15 30 L31 12 L37 11 L36 17 L18 33Z" fill="{WH}" {S2}/><path d="M17 30 L33 14" stroke="{c}" stroke-width="2"/><path d="M12 27 L21 36" stroke="{INK}" stroke-width="6" stroke-linecap="round"/><path d="M12 27 L21 36" stroke="{c}" stroke-width="3" stroke-linecap="round"/><path d="M16 32 L10 38" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>'
G['heart']=lambda c: f'<path d="M24 36 C12 28 11 20 16 16 C20 13 23 15 24 18 C25 15 28 13 32 16 C37 20 36 28 24 36Z" fill="{c}" {S2}/><circle cx="18" cy="19" r="2" fill="#fff"/>'
G['cash']=lambda c: f'<rect x="11" y="16" width="26" height="16" rx="2" fill="{GR}" {S2}/><circle cx="24" cy="24" r="4.5" fill="{sh(GR,-0.4)}"/><path d="M24 21 v6" stroke="{WH}" stroke-width="2"/>'
G['coin']=lambda c: f'<circle cx="24" cy="24" r="11" fill="{sh(GD,-0.3)}" {S2}/><circle cx="23" cy="23" r="8" fill="{GD}"/><path d="M23 18 v10" stroke="{sh(GD,-0.5)}" stroke-width="3"/>'
G['gem']=lambda c: f'<path d="M15 19 L20 13 H28 L33 19 L24 36Z" fill="{sh(MG,-0.2)}" {S2}/><path d="M15 19 H33 L24 36Z" fill="{MG}"/><path d="M20 13 L24 19 L28 13" fill="none" stroke="{sh(MG,0.5)}" stroke-width="1.5"/><path d="M17 19 L24 34" stroke="{sh(MG,0.5)}" stroke-width="1.5"/>'
G['xp']=lambda c: f'<path d="M24 12 L27.5 20 L36 21 L29.5 27 L31.5 35 L24 31 L16.5 35 L18.5 27 L12 21 L20.5 20Z" fill="{c}" {S2}/><path d="M24 16 L22 22" stroke="#fff" stroke-width="2"/>'
G['rate']=lambda c: f'<path d="M12 16 L22 24 L12 32Z M24 16 L34 24 L24 32Z" fill="{c}" {S2}/>'
G['range']=lambda c: f'<circle cx="24" cy="24" r="11" fill="none" stroke="{INK}" stroke-width="5"/><circle cx="24" cy="24" r="11" fill="none" stroke="{c}" stroke-width="2.5"/><circle cx="24" cy="24" r="3.5" fill="{c}" {S2}/><path d="M24 9 v6 M24 33 v6 M9 24 h6 M33 24 h6" stroke="{c}" stroke-width="2.5"/>'
G['glass']=lambda c: f'<path d="M16 12 H32 L28 26 V34 H32 V37 H16 V34 H20 V26Z" fill="{sh(CY,0.3)}" {S2}/><path d="M22 18 L26 22 L23 26" stroke="{RD}" stroke-width="2" fill="none"/>'
G['greed']=lambda c: f'<path d="M14 22 C14 14 34 14 34 22 L32 36 H16Z" fill="{sh(AM,-0.2)}" {S2}/><path d="M17 15 L24 20 L31 15" fill="none" stroke="{INK}" stroke-width="2.5"/><circle cx="24" cy="28" r="4" fill="{GD}" {S2}/>'
G['fort']=lambda c: f'<path d="M12 36 V18 H16 V22 H20 V18 H28 V22 H32 V18 H36 V36Z" fill="{c}" {S2}/><rect x="21" y="27" width="6" height="9" fill="{INK}"/>'
G['frenzy']=lambda c: f'<path d="M26 10 L14 27 H23 L20 38 L34 20 H25Z" fill="{c}" {S2}/>'
G['miser']=lambda c: f'<rect x="12" y="20" width="24" height="16" rx="3" fill="{SL3}" {S2}/><path d="M17 20 V15 C17 9 31 9 31 15 V20" fill="none" stroke="{INK}" stroke-width="3"/><circle cx="24" cy="28" r="3.5" fill="{GD}"/>'
G['moon']=lambda c: f'<circle cx="24" cy="24" r="12" fill="{RD}" {S2}/><circle cx="30" cy="19" r="9" fill="{SL}"/><circle cx="19" cy="28" r="2" fill="{sh(RD,-0.4)}"/>'
G['reroll']=lambda c: f'<path d="M34 22 A10 10 0 1 0 31 31" fill="none" stroke="{INK}" stroke-width="6"/><path d="M34 22 A10 10 0 1 0 31 31" fill="none" stroke="{c}" stroke-width="3"/><path d="M29 20 L36 22 L37 15Z" fill="{c}" {S2}/>'
G['wind']=lambda c: f'<path d="M10 18 H28 A4 4 0 1 0 24 14 M10 25 H34 A4 4 0 1 1 30 29 M12 32 H24" fill="none" stroke="{INK}" stroke-width="5.5" stroke-linecap="round"/><path d="M10 18 H28 A4 4 0 1 0 24 14 M10 25 H34 A4 4 0 1 1 30 29 M12 32 H24" fill="none" stroke="{c}" stroke-width="2.5" stroke-linecap="round"/>'
G['skip']=lambda c: f'<path d="M12 16 L22 24 L12 32Z M22 16 L32 24 L22 32Z" fill="{c}" {S2}/><rect x="32" y="15" width="4" height="18" fill="{c}" {S2}/>'
G['clock']=lambda c: f'<circle cx="24" cy="24" r="12" fill="{WH}" {S2}/><path d="M24 16 V24 L29 28" fill="none" stroke="{INK}" stroke-width="3"/>'
G['flask']=lambda c: f'<path d="M20 11 H28 M21 11 V20 L13 34 C12 36 13 37 15 37 H33 C35 37 36 36 35 34 L27 20 V11" fill="{WH}" {S2}/><path d="M16 30 H32 L34.5 35 H13.5Z" fill="{c}"/>'
G['lock']=lambda c: f'<path d="M17 22 V17 C17 9 31 9 31 17 V22" fill="none" stroke="{INK}" stroke-width="6"/><path d="M17 22 V17 C17 9 31 9 31 17 V22" fill="none" stroke="{SL3}" stroke-width="2.5"/><rect x="13" y="21" width="22" height="16" rx="3" fill="{GD}" {S2}/><rect x="22.5" y="26" width="3" height="6" fill="{INK}"/>'
G['flame']=lambda c: f'<path d="M24 10 C30 18 35 22 34 29 C33 35 28 38 24 38 C19 38 14 35 14 29 C14 23 19 22 20 16 C22 19 23 20 24 10Z" fill="{RU}" {S2}/><path d="M24 24 C27 28 29 30 28 33 C27 35 21 35 20 33 C19 30 22 28 24 24Z" fill="{GD}"/>'
G['tier']=lambda c: f'<path d="M12 36 L18 30 L24 36 L30 30 L36 36" fill="none" stroke="{INK}" stroke-width="6"/><path d="M12 28 L18 22 L24 28 L30 22 L36 28 M12 20 L24 10 L36 20" fill="none" stroke="{INK}" stroke-width="6"/><path d="M12 36 L18 30 L24 36 L30 30 L36 36 M12 28 L18 22 L24 28 L30 22 L36 28 M12 20 L24 10 L36 20" fill="none" stroke="{c}" stroke-width="3"/>'
G['grid']=lambda c: ''.join(f'<rect x="{x}" y="{y}" width="9" height="9" rx="1.5" fill="{c if (x+y)%14 else WH}" {S2}/>' for x in (12,23) for y in (12,23))+'' 
G['card']=lambda c: f'<rect x="15" y="10" width="18" height="26" rx="3" fill="{sh(c,-0.3)}" {S2} transform="rotate(-12 24 24)"/><rect x="17" y="12" width="18" height="26" rx="3" fill="{c}" {S2} transform="rotate(8 24 24)"/>'
G['target']=lambda c: f'<circle cx="24" cy="24" r="12" fill="{WH}" {S2}/><circle cx="24" cy="24" r="7" fill="{c}"/><circle cx="24" cy="24" r="2.5" fill="{INK}"/>'
G['skull']=lambda c: f'<path d="M14 24 C14 13 34 13 34 24 V30 H30 V35 H18 V30 H14Z" fill="{WH}" {S2}/><circle cx="19.5" cy="24" r="3" fill="{INK}"/><circle cx="28.5" cy="24" r="3" fill="{INK}"/>'
G['wave']=lambda c: f'<path d="M10 22 Q14 16 18 22 T26 22 T34 22 T38 20 M10 30 Q14 24 18 30 T26 30 T34 30 T38 28" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round"/><path d="M10 22 Q14 16 18 22 T26 22 T34 22 T38 20 M10 30 Q14 24 18 30 T26 30 T34 30 T38 28" fill="none" stroke="{c}" stroke-width="3" stroke-linecap="round"/>'
G['crown']=lambda c: f'<path d="M12 33 L10 16 L18 23 L24 13 L30 23 L38 16 L36 33Z" fill="{GD}" {S2}/><circle cx="24" cy="27" r="2.5" fill="{MG}"/>'
G['up']=lambda c: f'<path d="M24 10 L36 23 H29 V37 H19 V23 H12Z" fill="{c}" {S2}/>'
G['dot']=lambda c: ''
G['chest']=lambda c: f'<rect x="10" y="20" width="28" height="17" rx="2" fill="{sh(AM,-0.3)}" {S2}/><path d="M10 20 C10 11 38 11 38 20Z" fill="{AM}" {S2}/><rect x="21" y="19" width="6" height="8" rx="1" fill="{GD}" {S2}/>'
G['house']=lambda c: f'<path d="M10 24 L24 12 L38 24 V37 H10Z" fill="{c}" {S2}/><rect x="20" y="27" width="8" height="10" fill="{INK}"/>'
G['list']=lambda c: ''.join(f'<rect x="11" y="{y}" width="5" height="5" rx="1" fill="{c}" {S2}/><path d="M20 {y+2.5} H37" stroke="{WH}" stroke-width="3" stroke-linecap="round"/>' for y in (13,22,31))
G['bars']=lambda c: f'<rect x="11" y="26" width="7" height="11" fill="{c}" {S2}/><rect x="20.5" y="19" width="7" height="18" fill="{c}" {S2}/><rect x="30" y="12" width="7" height="25" fill="{c}" {S2}/>'
I={}
def badge(c,g,gc=None): return ibg(c)+G[g](gc or c)
P={'dmg':(CY,'sword'),'hp':(GR,'heart'),'cash':(AM,'cash'),'xp':(AM,'xp'),'rate':(CY,'rate'),'range':(CY,'range'),
   'glass':(RD,'glass'),'greed':(RD,'greed'),'fort':(GR,'fort'),'frenzy':(RD,'frenzy'),'miser':(AM,'miser'),'bloodmoon':(MG,'moon')}
for k,(c,g) in P.items(): I['perk_'+k]=badge(c,g)
def card(c,g): return (f'<rect x="7" y="4" width="36" height="43" rx="6" fill="{INK}" opacity="0.4"/><rect x="5" y="2" width="36" height="43" rx="6" fill="{sh(c,-0.5)}" {S}/>'
    f'<rect x="8" y="5" width="30" height="37" rx="4" fill="{SL}" stroke="{c}" stroke-width="2"/><g transform="translate(-1 -1)">{G[g](c)}</g><rect x="13" y="38" width="20" height="2.5" rx="1" fill="{c}"/>')
for k,(c,g) in {'dmg':(CY,'sword'),'hp':(GR,'heart'),'cash':(AM,'cash'),'coin':(AM,'coin'),'xp':(AM,'xp'),'reroll':(GR,'reroll'),'wind':(CY,'wind'),'skip':(MG,'skip')}.items(): I['card_'+k]=card(c,g)
I['card_back']=(f'<rect x="7" y="4" width="36" height="43" rx="6" fill="{INK}" opacity="0.4"/><rect x="5" y="2" width="36" height="43" rx="6" fill="{sh(MG,-0.5)}" {S}/><rect x="8" y="5" width="30" height="37" rx="4" fill="{sh(MG,-0.2)}"/>'
    f'<path d="M23 12 L32 23.5 L23 35 L14 23.5Z" fill="{SL}" {S2}/><path d="M23 17 L28 23.5 L23 30 L18 23.5Z" fill="{MG}"/>')
I['chest']=G['chest'](AM)+f'<path d="M6 10 l3 3 M42 10 l-3 3 M24 4 v4" stroke="{GD}" stroke-width="2.5" stroke-linecap="round"/>'
L={'speed':(CY,'clock'),'dmg':(CY,'sword'),'hp':(GR,'heart'),'coin':(AM,'coin'),'xp':(AM,'xp'),'startcash':(AM,'cash'),'offcap':(AM,'chest'),'offrate':(AM,'clock'),'reroll':(GR,'reroll'),'labspeed':(GR,'flask')}
def labb(c,g): return ibg(c)+G[g](c)+f'<path d="M33 31 h6 M34 31 V35 L31 41 H41 L38 35 V31" fill="{WH}" stroke="{INK}" stroke-width="2"/><path d="M32 39 H40 L41 41 H31Z" fill="{c}"/>'
for k,(c,g) in L.items(): I['lab_'+k]=labb(c,g)
M={'kill':(RD,'skull'),'wave':(CY,'wave'),'boss':(MG,'crown'),'eco':(AM,'coin'),'cash':(AM,'cash'),'perk':(GR,'xp'),'lab':(GR,'flask'),'upgrade':(GR,'up')}
for k,(c,g) in M.items(): I['mis_'+k]=ibg(c)+f'<circle cx="38" cy="10" r="6" fill="{GR}" {S2}/><path d="M35 10 l2 2 4 -4" stroke="{INK}" stroke-width="2" fill="none"/>'+G[g](c)
for k,g in {'gem':'gem','coin':'coin','clock':'clock','lock':'lock','streak':'flame','tier':'tier','cash':'cash','xp':'xp','lab':'flask','card':'card','mission':'list','speed':'rate'}.items(): I['icon_'+k]=G[g]({'tier':GD,'xp':AM,'lab':GR,'card':MG,'mission':CY,'speed':CY}.get(k,WH))
for k,g in {'base':'grid','labs':'flask','cards':'card','missions':'list'}.items(): I['tab_'+k]=G[g]({'base':CY,'labs':GR,'cards':MG,'missions':AM}[k])
I['badge_dot']=f'<circle cx="24" cy="24" r="12" fill="{RD}" {S}/><circle cx="20" cy="20" r="4" fill="{sh(RD,0.5)}"/>'
I['speed_pill']=f'<rect x="3" y="13" width="42" height="22" rx="11" fill="{SL2}" {S}/><path d="M12 18 L20 24 L12 30Z M21 18 L29 24 L21 30Z" fill="{CY}" {S2}/><rect x="31" y="18" width="4" height="12" fill="{CY}" {S2}/><rect x="37" y="18" width="4" height="12" fill="{CY}" {S2}/>'
for k,v in I.items(): w(k,svg(48,v))
print(len(B)+len(E)+len(I))
