"""Contrast model for the Planly glass redesign.

Browsers alpha-composite in gamma-encoded sRGB, so blends are done on 0..255 values.
saturate() is modelled as luminance-preserving (Rec.709 luma weights); we keep a margin for that.
Blur averages the environment, so the darkest/lightest blurred backdrop is bounded by the
darkest/lightest environment stop (reed highlights included as a worst case on the light side).
"""

def hx(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def to_hex(c):
    return '#%02X%02X%02X' % tuple(max(0, min(255, round(v))) for v in c)

def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def cr(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def over(top, alpha, bottom):
    return tuple(t * alpha + b * (1 - alpha) for t, b in zip(top, bottom))

WHITE = (255, 255, 255)
INK = hx('#0B1020')

THEMES = {
    'day': {
        'env': {
            'top-band (headline zone)': '#0A5A93',
            'cerulean': '#0B78B0',
            'cyan right': '#0C86B8',
            'deep figure': '#1A2C6A',
            'magenta': '#B02E6E',
            'coral core': '#D9575E',
            'amber glow': '#D66A4C',
            'lavender low': '#6A64A0',
            'rose low-right': '#9A5A80',
        },
        'reed_hi': 0.07,  # white highlight of a reed ridge (worst case, before blur)
        'tiers': {
            # name: (tint, alpha, top-highlight alpha)
            'glass-thin':    ('#0A1230', 0.30, 0.10),
            'glass-regular': ('#0A1230', 0.40, 0.08),
            'glass-thick':   ('#0B1028', 0.58, 0.06),
        },
    },
    'night': {
        'env': {
            'top-band (headline zone)': '#081A44',
            'deep navy': '#06143A',
            'teal-blue': '#0A4472',
            'indigo': '#1A1450',
            'plum-magenta': '#861A58',
            'ember core': '#C4443F',
            'amber ember': '#B9572F',
            'violet low': '#2C2266',
        },
        'reed_hi': 0.05,
        'tiers': {
            'glass-thin':    ('#141832', 0.30, 0.10),
            'glass-regular': ('#12152C', 0.38, 0.08),
            'glass-thick':   ('#0E1124', 0.60, 0.06),
        },
    },
}

PLATTER = 0.10       # white platter on a window
PLATTER_HOVER = 0.14
TEXT_ALPHAS = {'label (1.0)': 1.0, 'secondary (0.74)': 0.74, 'tertiary (0.56)': 0.56}

TYPE_TINTS = {  # on-glass tints, shared by both themes (glass is always dark-ish)
    'study indigo': '#8F8CFF',
    'work cyan': '#5CCBFF',
    'reading orange': '#FFAA3D',
    'fitness pink': '#FF6F91',
    'meeting purple': '#D08CFF',
    'habit mint': '#5EE6DD',
    'errand brown': '#C9A27A',
    'personal yellow': '#FFD84D',
    'other gray': '#A8ADBD',
    'missed red': '#FF7A70',
}
SIGNAL = hx('#C6F432')   # lime
TINT_WASH = 0.16          # tint mixed into a task platter


def report(theme_name):
    t = THEMES[theme_name]
    env = {k: hx(v) for k, v in t['env'].items()}
    print(f'\n================ {theme_name.upper()} ================')
    print('Environment stops (L, white contrast):')
    for k, c in env.items():
        hi = over(WHITE, t['reed_hi'], c)
        print(f'  {k:28s} {to_hex(c)}  L={lum(c):.3f}  white {cr(WHITE, c):5.2f}:1   with reed ridge L={lum(hi):.3f} white {cr(WHITE, hi):5.2f}:1')
    dark_k = min(env, key=lambda k: lum(env[k]))
    light_k = max(env, key=lambda k: lum(env[k]))
    darkest, lightest = env[dark_k], over(WHITE, t['reed_hi'], env[light_k])
    print(f'  darkest = {dark_k} ({to_hex(darkest)}), lightest (+reed) = {light_k} ({to_hex(lightest)})')
    print(f'  lime signal on darkest env {cr(SIGNAL, darkest):.2f}:1, on lightest env {cr(SIGNAL, lightest):.2f}:1')
    print(f'  white pill edge vs lightest env {cr(WHITE, lightest):.2f}:1')

    for tier, (tint, a, hl) in t['tiers'].items():
        tint = hx(tint)
        print(f'\n  {tier}: tint {to_hex(tint)} @ {a:.2f}, top highlight white @ {hl:.2f}')
        for label, bg_env in (('darkest', darkest), ('lightest', lightest)):
            base = over(tint, a, bg_env)
            top = over(WHITE, hl, base)  # under the specular highlight (headers)
            for surf_name, surf in (('window', top), ('platter', over(WHITE, PLATTER, top)), ('platter:hover', over(WHITE, PLATTER_HOVER, top))):
                parts = []
                for tl, ta in TEXT_ALPHAS.items():
                    fg = over(WHITE, ta, surf)
                    parts.append(f'{tl.split()[0]} {cr(fg, surf):5.2f}')
                print(f'    over {label:8s} {surf_name:14s} bg {to_hex(surf)} L={lum(surf):.3f} | ' + ' | '.join(parts)
                      + f' | lime {cr(SIGNAL, surf):4.2f}')

    # task platters: window(regular) + platter + tint wash; text white & secondary; glyph tint vs platter
    tint_r, a_r, hl_r = t['tiers']['glass-regular']
    print('\n  Task platters on glass-regular (tint wash %.0f%%): white title / secondary meta / glyph tint vs platter' % (TINT_WASH * 100))
    worst = {}
    for name, hexv in TYPE_TINTS.items():
        tc = hx(hexv)
        rows = []
        for label, bg_env in (('dark', darkest), ('light', lightest)):
            base = over(WHITE, hl_r, over(hx(tint_r), a_r, bg_env))
            plat = over(WHITE, PLATTER, base)
            washed = over(tc, TINT_WASH, plat)
            sec = over(WHITE, 0.74, washed)
            rows.append((label, washed, cr(WHITE, washed), cr(sec, washed), cr(tc, washed), cr(WHITE, tc)))
        s = '  '.join(f'[{l}] bg {to_hex(w)} title {a1:4.2f} meta {a2:4.2f} glyph {a3:4.2f}' for l, w, a1, a2, a3, _ in rows)
        print(f'    {name:16s} {hexv}  {s}  | white-on-solid-tint {rows[0][5]:4.2f}  ink-on-tint {cr(INK, tc):5.2f}')

    print('\n  Display/body text directly on environment:')
    top_band = env['top-band (headline zone)']
    for a in (1.0, 0.86):
        fg = over(WHITE, a, over(WHITE, t['reed_hi'], top_band))
        print(f'    white@{a:.2f} on top band (+reed): {cr(fg, over(WHITE, t["reed_hi"], top_band)):.2f}:1')
    print(f'    white@1.00 on lightest env (+reed): {cr(WHITE, lightest):.2f}:1  (display text only, needs >= 3:1)')


for name in THEMES:
    report(name)

print('\nINK on white pill: %.2f:1' % cr(INK, WHITE))
print('INK@0.6 on white (disabled-ish): %.2f:1' % cr(over(INK, 0.6, WHITE), WHITE))
print('Lime vs white (adjacent): %.2f:1' % cr(SIGNAL, WHITE))
print('Ink on lime: %.2f:1' % cr(INK, SIGNAL))
