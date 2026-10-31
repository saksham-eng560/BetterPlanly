import sys, io, contextlib
sys.path.insert(0, sys.argv[1])
with contextlib.redirect_stdout(io.StringIO()):
    from contrast import hx, to_hex, lum, cr, over, WHITE, INK

SIGNAL = hx('#C6F432')
TINTS = {  # on-glass tints (solid discs, checkbox fills, ruler ticks) -> ink glyphs on top
    'indigo (study)': '#8F8CFF', 'cyan (work)': '#5CCBFF', 'orange (reading)': '#FFAA3D', 'pink (fitness)': '#FF6F91',
    'purple (meeting)': '#D08CFF', 'mint (habit)': '#5EE6DD', 'brown (errand)': '#C9A27A', 'yellow (personal)': '#FFD84D',
    'gray (other)': '#A8ADBD', 'teal (widget)': '#62D2E6', 'red (missed)': '#FF7A70',
}
TEXT_TINTS = {'red text (missed meta, errors)': '#FFBDB6', 'flag orange': '#FFC46B', 'lime text (Today meta)': '#C6F432'}

THEMES = {
  'DAY': dict(
    top={'top-a': '#0A4E86', 'top-b': '#0B5F98'},
    env={'top-a': '#0A4E86', 'top-b': '#0B5F98', 'cerulean': '#0B74AA', 'cyan': '#0A7DB0', 'deep': '#1A2C6A',
         'magenta': '#B02E6E', 'coral': '#CC4F62', 'amber': '#C95A48', 'lavender': '#6A64A0', 'rose': '#965780'},
    reed=0.06,
    tiers={'thin': ('#0A1230', 0.40, 0.08, 'top'), 'regular': ('#0A1230', 0.56, 0.07, 'env'), 'thick': ('#0B1028', 0.66, 0.05, 'env')}),
  'NIGHT': dict(
    top={'top-a': '#071640', 'top-b': '#0A2552'},
    env={'top-a': '#071640', 'top-b': '#0A2552', 'cerulean': '#0A3C6C', 'cyan': '#0B4A78', 'deep': '#0B0E33',
         'magenta': '#7E1A56', 'coral': '#AE3A3E', 'amber': '#A84C2E', 'lavender': '#2C2266', 'rose': '#4A1E4E'},
    reed=0.05,
    tiers={'thin': ('#141832', 0.34, 0.08, 'top'), 'regular': ('#12152C', 0.50, 0.07, 'env'), 'thick': ('#0E1124', 0.62, 0.05, 'env')}),
}
SEC, TER, RING = 0.84, 0.62, 0.74
PLAT, HOV, WASH = 0.06, 0.09, 0.08

for name, th in THEMES.items():
    print(f'\n######## {name}')
    env = {k: hx(v) for k, v in th['env'].items()}
    for k, c in env.items():
        ridge = over(WHITE, th['reed'], c)
        print(f'  env {k:9s} {to_hex(c)} L={lum(c):.3f}  white {cr(WHITE, c):5.2f}  (+reed {cr(WHITE, ridge):5.2f})')
    top = {k: hx(v) for k, v in th['top'].items()}
    top_light = over(WHITE, th['reed'], max(top.values(), key=lum))
    print(f'  top band: white {cr(WHITE, top_light):.2f}, white@{SEC} {cr(over(WHITE, SEC, top_light), top_light):.2f}, lime {cr(SIGNAL, top_light):.2f}')
    env_light = over(WHITE, th['reed'], max(env.values(), key=lum))
    env_dark = min(env.values(), key=lum)
    print(f'  anywhere: display white on lightest {cr(WHITE, env_light):.2f}; white pill edge vs lightest {cr(WHITE, env_light):.2f}; lime on lightest {cr(SIGNAL, env_light):.2f}')
    for tier, (tint, a, hl, scope) in th['tiers'].items():
        pool = top if scope == 'top' else env
        dk = min(pool.values(), key=lum)
        lk = over(WHITE, th['reed'], max(pool.values(), key=lum))
        print(f'  [{tier}] {tint} @ {a} (+hl {hl}) over {scope}')
        for side, e in (('darkest', dk), ('lightest', lk)):
            win = over(WHITE, hl, over(hx(tint), a, e))
            p, ph = over(WHITE, PLAT, win), over(WHITE, HOV, win)
            sel = over(WHITE, 0.20, win)  # selected lozenge
            print(f'     {side:8s} window {to_hex(win)}: label {cr(WHITE, win):5.2f} sec {cr(over(WHITE, SEC, win), win):5.2f} ter {cr(over(WHITE, TER, win), win):5.2f} lime {cr(SIGNAL, win):5.2f}'
                  f' | platter {to_hex(p)}: label {cr(WHITE, ph):5.2f}(hover) sec {cr(over(WHITE, SEC, p), p):5.2f} sec(hover) {cr(over(WHITE, SEC, ph), ph):5.2f} ring {cr(over(WHITE, RING, p), p):4.2f}'
                  f' | lozenge label {cr(WHITE, sel):4.2f}')
            if tier == 'regular' and side == 'lightest':
                tt = min((cr(WHITE, over(hx(v), WASH, ph)), k) for k, v in TINTS.items())
                tm = min((cr(over(WHITE, SEC, over(hx(v), WASH, p)), over(hx(v), WASH, p)), k) for k, v in TINTS.items())
                print(f'     washed task platter worst: title {tt[0]:.2f} ({tt[1]}), meta {tm[0]:.2f} ({tm[1]})')
                for k, v in TEXT_TINTS.items():
                    print(f'     {k:32s} {v}: on window {cr(hx(v), win):.2f}, on platter(hover) {cr(hx(v), ph):.2f}')
                red_plat = over(hx('#FF453A'), 0.22, win)
                print(f'     error platter (red 22%) {to_hex(red_plat)}: white text {cr(WHITE, red_plat):.2f}')
                lime_plat = over(SIGNAL, 0.16, win)
                print(f'     success platter (lime 16%) {to_hex(lime_plat)}: white text {cr(WHITE, lime_plat):.2f}')
print('\nInk glyph on solid tints:')
for k, v in TINTS.items():
    print(f'  {k:18s} {v}  ink {cr(INK, hx(v)):5.2f}  white {cr(WHITE, hx(v)):4.2f}')
print(f'Ink on white pill {cr(INK, WHITE):.2f}; ink on lime {cr(INK, SIGNAL):.2f}; ink@0.62 on white {cr(over(INK, 0.62, WHITE), WHITE):.2f}')

# ---- extra pairs quoted in DESIGN_SPEC.md section 6 ----
YELLOW, REDT = hx('#FFD84D'), hx('#FFBDB6')
for name, th in THEMES.items():
    env = {k: hx(v) for k, v in th['env'].items()}
    light = over(WHITE, th['reed'], max(env.values(), key=lum))
    tint, a, hl, _ = th['tiers']['regular']
    win = over(WHITE, hl, over(hx(tint), a, light))
    ttint, ta, thl, _ = th['tiers']['thick']
    thick = over(WHITE, thl, over(hx(ttint), ta, light))
    washed = over(YELLOW, WASH, over(WHITE, PLAT, win))
    ww = over(YELLOW, 0.05, win)
    top = over(WHITE, th['reed'], max((hx(v) for v in th['top'].values()), key=lum))
    print(f'\n[{name} extras, worst case]')
    print(f'  red-text on window {cr(REDT, win):.2f} | on 5% yellow widget wash {cr(REDT, ww):.2f} | lime on it {cr(SIGNAL, ww):.2f}')
    print(f'  white on ink-45% duration pill over washed platter {cr(WHITE, over(INK, 0.45, washed)):.2f}')
    print(f'  glass button label rest {cr(WHITE, over(WHITE, 0.14, win)):.2f} hover {cr(WHITE, over(WHITE, 0.18, win)):.2f}')
    print(f'  field placeholder (secondary on white 10%) {cr(over(WHITE, SEC, over(WHITE, 0.10, win)), over(WHITE, 0.10, win)):.2f}')
    print(f'  subtitle white .88 on top band {cr(over(WHITE, 0.88, top), top):.2f}')
