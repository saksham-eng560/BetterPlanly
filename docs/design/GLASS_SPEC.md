# Planly restyle: "Glass over an environment"

This spec restyles the Planly frontend (`frontend/src`) after the Pelmatech reference image. It is written in Apple's visionOS / Liquid Glass language: glass windows float over a vivid, art-directed environment. It merges the reference with the project skills `apple-design` (HIG: clarity, deference, depth) and `emil-design-eng` (motion and polish).

- **Status:** implemented in `frontend/src` (see [UI_SPEC.md](../UI_SPEC.md) for the as-built summary and [ADR 0006](../adr/0006-glass-over-an-environment.md) for the decision).
- **Contrast model:** [`contrast/report.py`](contrast/report.py), which imports `contrast.py`. Every ratio in §6 comes from it. Re-run it with `python3 docs/design/contrast/report.py docs/design/contrast` whenever an environment stop or glass alpha changes.

---

## 0. Decisions at a glance

| Question | Decision |
|---|---|
| Backdrop | A CSS-only **environment**: one fixed layer of skewed radial gradients (cerulean → magenta → coral), a **top legibility band**, and a **reeded-glass** stripe overlay with a 14 px pitch. No photo and no `filter`. Its luminance is **capped**, so contrast can be calculated. |
| Where content lives | In **windows** (`glass-regular`): the Day window, one window per checklist widget, and the Agent window. Inside a window, content sits on **platters**: flat white fills at 6–9% with no blur. Text never sits directly on the environment, except display type and the top band. |
| Glass tiers | **thin** (toolbar band), **regular** (windows) and **thick** (sheets, popovers, toasts, drawer). Each tier's alpha is the smallest value that passes WCAG AA over the lightest part of the environment. |
| Accent | **White is the interactive colour.** visionOS-style solid white pills carry ink labels. **Lime `#C6F432` is a signal, not an accent.** It marks *now / today / selected / live* only: the today dot, the now-line, the elapsed part of a ruler, the active tab underline, the online dot, the switch's on state and the focus ring. **Apple blue and Apple green are retired.** |
| Ink | All text is white in both themes. Any solid colour (a white pill, lime, or a task tint) carries **ink `#0B1020`**, never white. |
| Display type | Light (300) weight at 22 px and above, and only for the day header, the "Checklist" heading, section progress, widget counts and time numerals. |
| Reference motifs | The pill nav becomes the **week-strip capsule** (a lozenge marks the selected day, a lime dot marks today). The Mondays card becomes the **timed task card** (large light start and end times, a "◷ 40m" duration pill on a hairline, a tick ruler along the bottom edge) and the **task-sheet time card**. The feature row becomes the **Import tab row** (hairline track with a lime underline). The white "Try for Free ↗" pill becomes the **primary button**. The round glass buttons become the **toolbar ornaments**. |
| Light vs dark | **Day** (light) uses the reference's vivid daytime environment with *smoked* glass. **Night** (dark) uses a deeper, more saturated night environment with lighter-alpha glass. Ink, accents, radii and type are identical. |
| Blur budget | At most 7 `backdrop-filter`s visible at once, never nested. Cards, rows, bubbles, chips, fields and toolbar ornaments never blur. |

---

## 1. Design principles

1. **Three depths, no more.** The *environment* is the world. *Windows* are glass. *Platters* are flat fills inside windows. Floating surfaces (sheets, popovers, toasts) are just thicker windows. This is the HIG's "depth" made spatial.
2. **Glass clamps; it does not decorate.** Each glass tier exists to squeeze the environment's luminance range into one where white text passes AA. Its alpha is computed, not tuned by eye. If a surface doesn't need clamping, it isn't glass.
3. **White is for doing, lime is for now, colour is for content.** Interactive emphasis is achromatic: white pills, white labels, glass buttons. That reads on every part of a multicolour backdrop. Lime is a small, rare signal. Hue belongs to the user's content: task types and sections.
4. **Light type only for big things.** Weight 300 is reserved for display words and numerals of 22 px and above. Everything else uses SF weights 400–700 at Apple's Dynamic Type sizes.
5. **Time is a ruler.** Durations read as tick scales and "◷ 2h" pills, as in the reference card. The now-line and the elapsed ticks of the current task are lime, so "where am I in my day" is visible at a glance.
6. **One blur per stack; motion moves glass, it never re-blurs it.** Animate `transform` and `opacity` of glass elements. Never animate `backdrop-filter` or the environment.
7. **Every vivid surface has an opaque twin.** Reduced transparency, increased contrast, forced colours and browsers without `backdrop-filter` all get solid panels in the same hue family, with no loss of hierarchy.

---

## 2. Reconciling "material is for chrome, not content"

`apple-design` says: *"Put material on chrome, never on content cards. Content sits on opaque grouped backgrounds"*. It lists *"glassmorphism on content"* as an anti-pattern. visionOS (and iOS 26 Liquid Glass widgets) puts content in glass windows over an environment. That is why the rule exists, and why visionOS can break it safely:

- **Why the HIG rule exists.** A low-alpha, per-card blur makes text contrast depend on whatever scrolls behind it. Contrast becomes unknowable and changes frame to frame. The problem is *unbounded contrast*, not glass as such.
- **Why visionOS can put content in glass.** There is no page under a visionOS window, because the environment *is* the page. The window's glass is (a) heavily blurred and tinted, (b) one uniform backplate per window, and (c) laid over environments Apple controls. In effect the window *is* the opaque grouped background, with a luminance that is clamped rather than fixed.

Planly adopts the visionOS resolution and keeps the HIG rule's intent with these rules:

| HIG intent | How Planly honours it |
|---|---|
| Content needs a stable backplate | A content region gets one **window**: a large blur, tint at α 0.50–0.66, and a contrast we computed (§6). Per-card glass stays forbidden. Task cards, checklist rows and bubbles are **platters** with no blur. Platters are the "grouped background" translated to glass. |
| Contrast must not depend on the backdrop | The environment is **art-directed CSS, not a user photo**. Its luminance is capped (Day L ≤ 0.21, Night L ≤ 0.14). The worst case is therefore known and tested. |
| Chrome recedes, content leads | Toolbar ornaments are the thinnest, smallest glass. Windows are the largest surfaces. Colour appears only in content. |
| Fallback to opaque | `prefers-reduced-transparency`, `prefers-contrast: more` and a missing `backdrop-filter` all switch every tier to its opaque twin (`--solid-*`). |
| Material marks edges with a hairline, not a heavy shadow | Glass has a 0.5 px white edge and a 1 px specular top line. Windows get a soft shadow; floating surfaces get the HIG layered shadow. |

Widgets are not "cards on a page". They are top-level windows over the environment, like iOS home-screen widgets over the wallpaper. That is why each one may be glass.

---

## 3. Legibility rules (normative)

- **L1 Environment ceiling.** Every environment stop, including the reed ridge highlight, stays at relative luminance **≤ 0.23 in Day and ≤ 0.20 in Night**. The **top band** (top 22 vh) stays **≤ 0.13 in Day and ≤ 0.03 in Night** (reed included). Changing a stop means re-running the contrast model.
- **L2 Text on the environment.** Only the following may sit directly on the environment:
  - display type of 24 px and above at weight 300 or more, in white: the day header, the "Checklist" heading and the section progress. These need 3:1 and get ≥ 3.81 (Day) and ≥ 5.10 (Night) anywhere.
  - the brand and the day subtitle, inside the top band (≥ 4.99:1).

  Everything else lives in glass.
- **L3 Text on glass.** Use only `--label` (white) or `--label-secondary` (0.84). `--label-tertiary` (0.62) is for icons, disabled states and decoration, **never informative text**. It reaches only 4.30:1 at worst.
- **L4 Solid colour carries ink.** White on a tint scores 1.38–2.85:1 (fail). Ink on a tint scores 6.64–13.69:1. This covers type discs, widget icons, checked checkboxes, the now-time capsule and white pills.
- **L5 Coloured text.** Only lime (the "Today" meta, ≥ 6.41:1 on windows) and `--red-text #FFBDB6` (missed meta and errors, **on windows only**, ≥ 4.65:1 even on a tint-washed widget) are allowed. Neither may sit on a platter or a hover state. Anything else coloured is a glyph (3:1) or a dot.
- **L6 Light weight.** No weight 300 below 22 px. Display text gets `--display-halo` (a soft shadow, not counted toward contrast).
- **L7 No detail behind glyphs.** Blur radius must be at least the reed pitch: 16, 28 and 40 px against a 14 px pitch. That attenuates the stripes by more than 99.9%, so no high-frequency pattern sits under text. Toolbar ornaments sit on the blurred toolbar edge for the same reason.
- **L8 No opacity dimming of content.** Done tasks use `--label-secondary` plus a strike-through. They no longer use `opacity: .55`, which drops contrast to about 2.4:1.
- **L9 Platter ceiling.** A platter is at most white 9% (hover). A tint wash is at most 8% on a task platter and 5% on a widget window. Pills that sit *on* a platter use an ink base, not more white. Anything brighter needs a new calculation.
- **L10 Focus lives on glass.** A focusable element must sit on glass or in the top band. The lime focus ring is ≥ 4.63:1 there, but only 2.97:1 over the lightest Day environment.

---

## 4. Tokens: `frontend/src/design/tokens.css` (full replacement)

Existing token names are kept and re-pointed, so any component not yet restyled is still legible on glass on day one. New tokens are added alongside.

```css
/* Planly "Glass over Environment" tokens: drop-in replacement for frontend/src/design/tokens.css.
   Existing token names are kept (re-pointed) so untouched components stay legible; new tokens are added.
   Every contrast figure quoted in DESIGN_SPEC.md was computed against these exact values. */

:root {
  /* The UI is light-on-glass in both themes, so native controls (scrollbars, date picker) render dark. */
  color-scheme: dark;

  /* ---------- environment: DAY (the reference: cerulean → magenta → coral, luminance-capped) ---------- */
  --env-base: #0B74AA;
  --env-top-a: #0A4E86;     /* top band, left: under the brand + "Today" headline */
  --env-top-b: #0B5F98;     /* top band, right: under the toolbar actions */
  --env-cerulean: #0B74AA;
  --env-cyan: #0A7DB0;
  --env-deep: #1A2C6A;      /* the dark motion-blurred "figure" streak */
  --env-magenta: #B02E6E;
  --env-coral: #CC4F62;     /* warm core; the reference's peach/white hot-spot is capped here */
  --env-amber: #C95A48;
  --env-lavender: #6A64A0;
  --env-rose: #965780;
  --reed-pitch: 14px;       /* fluted-glass stripe period */
  --reed-hi: 0.06;          /* ridge highlight (white) */
  --reed-lo: 0.07;          /* groove shade (black) */

  /* ---------- glass tiers ---------- */
  /* thin: ornaments that sit on the environment's top band (week capsule, toolbar circles, scroll edge) */
  --glass-thin-bg: rgb(10 18 48 / 0.40);
  --glass-thin-blur: 16px;
  --glass-thin-sat: 180%;
  --glass-thin-hl: 0.08;
  /* regular: content windows (day window, widgets, agent inspector) */
  --glass-regular-bg: rgb(10 18 48 / 0.56);
  --glass-regular-blur: 28px;
  --glass-regular-sat: 170%;
  --glass-regular-hl: 0.07;
  /* thick: floating surfaces over other glass (sheets, popovers, toasts, agent drawer) */
  --glass-thick-bg: rgb(11 16 40 / 0.66);
  --glass-thick-blur: 40px;
  --glass-thick-sat: 160%;
  --glass-thick-hl: 0.05;
  /* opaque twins (prefers-reduced-transparency, no backdrop-filter support) */
  --solid-thin: #0A3560;
  --solid-regular: #282B4F;
  --solid-thick: #222442;

  --glass-edge: inset 0 0 0 0.5px rgb(255 255 255 / 0.18);
  --glass-specular: inset 0 1px 0 rgb(255 255 255 / 0.28), inset 0 -1px 0 rgb(0 0 0 / 0.08);
  --shadow-window: 0 1px 2px rgb(4 8 30 / 0.10), 0 12px 32px rgb(4 8 30 / 0.20);
  --shadow-float: 0 0 0 0.5px rgb(255 255 255 / 0.16), 0 8px 24px rgb(4 8 30 / 0.28), 0 24px 64px rgb(4 8 30 / 0.36);
  --backdrop: rgb(4 8 24 / 0.32);   /* <dialog>::backdrop and drawer scrim */

  /* ---------- platters: flat fills inside a window (no blur) ---------- */
  --platter: rgb(255 255 255 / 0.06);
  --platter-hover: rgb(255 255 255 / 0.09);
  --platter-pressed: rgb(255 255 255 / 0.12);
  --platter-edge: inset 0 1px 0 rgb(255 255 255 / 0.10), inset 0 0 0 0.5px rgb(255 255 255 / 0.08);
  --tint-wash-amount: 8%;           /* task-type tint mixed into a task platter */
  --widget-wash-amount: 5%;         /* section tint mixed into a widget window */
  --lozenge: rgb(255 255 255 / 0.20); /* selected item in a capsule (week day, segment) */
  --check-ring: rgb(255 255 255 / 0.74); /* unchecked checkbox stroke (>= 4.5:1 on platters) */

  /* ---------- ink, labels, fills, separators (on glass, both themes) ---------- */
  --ink: #0B1020;                       /* text/glyphs on white, lime and solid tints */
  --label: #FFFFFF;
  --label-secondary: rgb(255 255 255 / 0.84);
  --label-tertiary: rgb(255 255 255 / 0.62);   /* icons, disabled, decoration: never informative text */
  --label-quaternary: rgb(255 255 255 / 0.30); /* tick marks, empty dots */
  --label-on-env: #FFFFFF;
  --label-on-env-secondary: rgb(255 255 255 / 0.88);
  --fill: rgb(255 255 255 / 0.18);
  --fill-secondary: rgb(255 255 255 / 0.14);
  --fill-tertiary: rgb(255 255 255 / 0.10);
  --fill-quaternary: rgb(255 255 255 / 0.06);
  --separator: rgb(255 255 255 / 0.14);
  --separator-opaque: rgb(255 255 255 / 0.22);

  /* legacy background names, re-pointed */
  --bg: transparent;
  --bg-secondary: var(--solid-regular);
  --bg-tertiary: var(--platter);
  --bg-grouped: var(--env-base);
  --bg-grouped-secondary: var(--platter);
  --bg-grouped-tertiary: var(--platter);
  --bg-elevated: var(--solid-thick);

  /* ---------- colour roles ---------- */
  --accent: #FFFFFF;          /* interactive = white (visionOS); filled buttons are white pills */
  --on-accent: var(--ink);
  --signal: #C6F432;          /* lime: "now / live / selected" indicator only */
  --on-signal: var(--ink);
  --focus: var(--signal);

  /* on-glass tints: solid discs, checkbox fills, ruler ticks. Always carry --ink glyphs, never white. */
  --indigo: #8F8CFF; --cyan: #5CCBFF; --orange: #FFAA3D; --pink: #FF6F91; --purple: #D08CFF;
  --mint: #5EE6DD; --brown: #C9A27A; --yellow: #FFD84D; --gray: #A8ADBD; --teal: #62D2E6;
  --red: #FF7A70;             /* missed / destructive disc */
  --red-text: #FFBDB6;        /* red text: on windows only (>= 4.65:1 incl. widget wash), never on platters */
  --red-wash: rgb(255 69 58 / 0.22);
  --green: var(--signal);     /* green is retired: "on / done / online" is lime */
  --blue: #5CA8FF;            /* kept for legacy references; not used for interaction */
  --flag: #FFC46B;            /* high-priority flag glyph */

  --type-study: var(--indigo);
  --type-work: var(--cyan);
  --type-reading: var(--orange);
  --type-fitness: var(--pink);
  --type-meeting: var(--purple);
  --type-habit: var(--mint);
  --type-errand: var(--brown);
  --type-personal: var(--yellow);
  --type-other: var(--gray);

  /* ---------- type ---------- */
  --font-text: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", "Segoe UI", system-ui, sans-serif;
  --font-display: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Inter", system-ui, sans-serif;
  --font-rounded: ui-rounded, "SF Pro Rounded", var(--font-text);
  --font-mono: ui-monospace, "SF Mono", "JetBrains Mono", Menlo, monospace;

  /* display scale: light (300) weight, white, only these elements */
  --text-display-xl: clamp(2.75rem, 1.9rem + 3.2vw, 4.5rem);   /* 44–72px: day header h1 */
  --text-display-l: clamp(2rem, 1.55rem + 1.6vw, 2.75rem);     /* 32–44px: "Checklist" h2 */
  --text-count: 2rem;                                          /* 32px: widget "4/15" */
  --text-time-l: 1.75rem;                                      /* 28px: task-sheet time card */
  --text-progress: 1.5rem;                                     /* 24px: section progress on env */
  --text-time: 1.375rem;                                       /* 22px: task-card start / end */
  --w-light: 300;
  --track-display: -0.035em;
  --display-halo: 0 1px 2px rgb(4 8 30 / 0.14), 0 0 32px rgb(4 8 30 / 0.22);

  /* Apple Dynamic Type scale (unchanged) */
  --text-large-title: 2.125rem; --text-title1: 1.75rem; --text-title2: 1.375rem; --text-title3: 1.25rem;
  --text-headline: 1.0625rem; --text-body: 1.0625rem; --text-callout: 1rem; --text-subhead: 0.9375rem;
  --text-footnote: 0.8125rem; --text-caption1: 0.75rem; --text-caption2: 0.6875rem;

  /* ---------- space (8pt grid, unchanged) ---------- */
  --s1: 0.25rem; --s2: 0.5rem; --s3: 0.75rem; --s4: 1rem; --s5: 1.25rem;
  --s6: 1.5rem; --s8: 2rem; --s10: 2.5rem; --s12: 3rem; --s16: 4rem;

  /* ---------- radius (concentric: window 32 − pad 12 = platter 20) ---------- */
  --r-xs: 8px;        /* tiny tags */
  --r-sm: 12px;       /* menu items, history rows, text fields */
  --r-md: 20px;       /* platters, fact groups, bubbles */
  --r-lg: 24px;       /* drop zone */
  --r-xl: 32px;       /* windows, sheets */
  --r-widget: 28px;
  --r-popover: 20px;
  --r-full: 999px;    /* capsules, pills, circles, checkboxes */
  --win-pad: 0.75rem;

  /* ---------- layout ---------- */
  --toolbar-h: 4.5rem;
  --ornament-h: 3.5rem;   /* week capsule */
  --control-h: 2.5rem;    /* toolbar circles and pills */
  --inspector-w: 23.5rem;
  --inspector-inset: 0.75rem;
  --content-max: 46rem;
  --hit: 44px;

  /* ---------- ruler motif ---------- */
  --tick-pitch: 6px;
  --tick-major-every: 30px;   /* every 5th tick */
  --tick-h: 5px;
  --tick-major-h: 9px;
  --ruler-h: 12px;

  /* ---------- motion ---------- */
  --ease-out: cubic-bezier(0.23, 1, 0.32, 1);
  --ease-in-out: cubic-bezier(0.77, 0, 0.175, 1);
  --ease-drawer: cubic-bezier(0.32, 0.72, 0, 1);
  --dur-press: 160ms;
  --dur-hover: 120ms;
  --dur-fast: 180ms;
  --dur-base: 240ms;
  --dur-sheet: 260ms;
  --dur-drawer: 320ms;
  --dur-exit: 140ms;
}

/* ---------- NIGHT: deeper, more saturated environment; glass is relatively lighter than its backdrop ---------- */
@media (prefers-color-scheme: dark) {
  :root {
    --env-base: #0A3C6C;
    --env-top-a: #071640;
    --env-top-b: #0A2552;
    --env-cerulean: #0A3C6C;
    --env-cyan: #0B4A78;
    --env-deep: #0B0E33;
    --env-magenta: #7E1A56;
    --env-coral: #AE3A3E;
    --env-amber: #A84C2E;
    --env-lavender: #2C2266;
    --env-rose: #4A1E4E;
    --reed-hi: 0.05;
    --reed-lo: 0.10;

    --glass-thin-bg: rgb(20 24 50 / 0.34);
    --glass-thin-sat: 160%;
    --glass-regular-bg: rgb(18 21 44 / 0.50);
    --glass-regular-sat: 150%;
    --glass-thick-bg: rgb(14 17 36 / 0.62);
    --glass-thick-sat: 140%;
    --solid-thin: #0E1B3F;
    --solid-regular: #251E3B;
    --solid-thick: #1E1932;

    --shadow-window: 0 1px 2px rgb(0 0 0 / 0.20), 0 12px 32px rgb(0 0 0 / 0.35);
    --shadow-float: 0 0 0 0.5px rgb(255 255 255 / 0.14), 0 8px 24px rgb(0 0 0 / 0.40), 0 24px 64px rgb(0 0 0 / 0.50);
    --backdrop: rgb(2 4 14 / 0.45);
  }
}

/* ---------- increased contrast ---------- */
@media (prefers-contrast: more) {
  :root {
    --label-secondary: rgb(255 255 255 / 0.92);
    --label-tertiary: rgb(255 255 255 / 0.80);
    --separator: rgb(255 255 255 / 0.40);
    --glass-edge: inset 0 0 0 1px rgb(255 255 255 / 0.45);
    --platter-edge: inset 0 0 0 1px rgb(255 255 255 / 0.30);
    --lozenge: #FFFFFF;          /* selected = solid white, number switches to --ink */
    --check-ring: #FFFFFF;
    --reed-hi: 0; --reed-lo: 0;
    --w-light: 400;
    --tint-wash-amount: 0%;
    --widget-wash-amount: 0%;
  }
}
```

### Token migration notes

| Old meaning | New value or role |
|---|---|
| `--accent` = Apple blue | `#FFFFFF`, the interactive colour. `.btn-filled` therefore becomes a white pill with `--on-accent` (ink) automatically. |
| `--green` = done / online / switch on | Aliased to `--signal` (lime). Green is retired. |
| `--bg-grouped-secondary` / `--bg-grouped-tertiary` (cards, rows, groups) | `--platter`, white 6% |
| `--bg-grouped` (page) | `--env-base`, the body fallback colour while the environment paints |
| `--bg-elevated` (sheet, segmented thumb) | `--solid-thick`. Sheets use the `glass-thick` class instead. |
| `--label-*` (dark text on white) | White at 1 / 0.84 / 0.62 / 0.30 |
| `--separator` | White 14%, 0.5 px |
| tints `--indigo` and the rest | On-glass pastel variants. They are always paired with ink glyphs. |
| `--shadow-card` | Removed. Platters are flat; delete its uses. |
| Radii `--r-md` 12 / `--r-xl` 22 | 20 / 32. The concentric chain is window 32 → padding 12 → platter 20. |

---

## 5. Environment and glass: `frontend/src/design/base.css`

Replace the old `.material` and `.material-thick` rules with the following. Keep the existing reset, typography, `.tabular` and `.visually-hidden` rules.

```css
/* Environment + glass materials: goes into frontend/src/design/base.css (replacing the old .material rules). */

body { background: var(--env-base); color: var(--label); }

/* ---------- environment (one fixed layer; never an ancestor of glass) ---------- */
.environment {
  position: fixed; inset: 0; z-index: -1;
  overflow: hidden; pointer-events: none;
  contain: strict;
  background: var(--env-base);
}
.env-field {
  position: absolute; inset: -20%;
  /* elongated, skewed ellipses read as a horizontal/diagonal motion blur */
  transform: skewY(-8deg);
  background:
    radial-gradient(34% 16% at 60% 70%, var(--env-amber) 0%, transparent 70%),
    radial-gradient(44% 22% at 52% 64%, var(--env-coral) 0%, transparent 72%),
    radial-gradient(40% 34% at 42% 60%, var(--env-magenta) 0%, transparent 70%),
    radial-gradient(11% 40% at 63% 40%, var(--env-deep) 0%, transparent 75%),
    radial-gradient(34% 30% at 92% 86%, var(--env-rose) 0%, transparent 70%),
    radial-gradient(30% 34% at 84% 58%, var(--env-lavender) 0%, transparent 70%),
    radial-gradient(40% 40% at 10% 90%, var(--env-cyan) 0%, transparent 70%),
    linear-gradient(160deg, var(--env-cerulean) 0%, var(--env-cyan) 45%, var(--env-cerulean) 100%);
}
.env-band {
  /* legibility band: guarantees the top ~22vh stays in the dark range for the brand, headline and toolbar */
  position: absolute; inset: 0 0 auto; height: 38vh;
  background: linear-gradient(90deg, var(--env-top-a), var(--env-top-b));
  -webkit-mask-image: linear-gradient(180deg, #000 0, #000 22vh, transparent 38vh);
  mask-image: linear-gradient(180deg, #000 0, #000 22vh, transparent 38vh);
}
.env-reeds {
  /* fluted / reeded glass: ridge highlight, flat, groove shade, per --reed-pitch */
  position: absolute; inset: 0;
  background-image: repeating-linear-gradient(90deg,
    rgb(255 255 255 / var(--reed-hi)) 0,
    rgb(255 255 255 / 0) calc(var(--reed-pitch) * 0.35),
    rgb(0 0 0 / 0) calc(var(--reed-pitch) * 0.55),
    rgb(0 0 0 / var(--reed-lo)) calc(var(--reed-pitch) * 0.9),
    rgb(255 255 255 / var(--reed-hi)) var(--reed-pitch));
}

/* ---------- glass tiers ---------- */
.glass-thin, .glass-regular, .glass-thick, .ornament {
  background:
    linear-gradient(180deg, rgb(255 255 255 / var(--_hl)) 0, rgb(255 255 255 / 0) 3rem),
    linear-gradient(var(--_wash, transparent), var(--_wash, transparent)),
    var(--_bg);
  -webkit-backdrop-filter: blur(var(--_blur)) saturate(var(--_sat));
  backdrop-filter: blur(var(--_blur)) saturate(var(--_sat));
  box-shadow: var(--glass-edge), var(--glass-specular), var(--_shadow, 0 0 #0000);
}
.glass-thin    { --_bg: var(--glass-thin-bg);    --_blur: var(--glass-thin-blur);    --_sat: var(--glass-thin-sat);    --_hl: var(--glass-thin-hl);    --_solid: var(--solid-thin); }
.glass-regular { --_bg: var(--glass-regular-bg); --_blur: var(--glass-regular-blur); --_sat: var(--glass-regular-sat); --_hl: var(--glass-regular-hl); --_solid: var(--solid-regular); --_shadow: var(--shadow-window); }
.glass-thick   { --_bg: var(--glass-thick-bg);   --_blur: var(--glass-thick-blur);   --_sat: var(--glass-thick-sat);   --_hl: var(--glass-thick-hl);   --_solid: var(--solid-thick);   --_shadow: var(--shadow-float); }
/* ornament: thin-glass look with NO backdrop-filter. Only valid on top of .toolbar::before (already blurred). */
.ornament { --_bg: var(--glass-thin-bg); --_hl: var(--glass-thin-hl); --_solid: var(--solid-thin);
  -webkit-backdrop-filter: none; backdrop-filter: none; }

/* toolbar scroll edge: the toolbar's single blur, always on, fading out below the bar */
.toolbar::before {
  content: ""; position: absolute; inset: 0 0 -1.5rem; z-index: -1; pointer-events: none;
  background: linear-gradient(180deg, var(--glass-thin-bg), transparent);
  -webkit-backdrop-filter: blur(var(--glass-thin-blur)) saturate(var(--glass-thin-sat));
  backdrop-filter: blur(var(--glass-thin-blur)) saturate(var(--glass-thin-sat));
  -webkit-mask-image: linear-gradient(180deg, #000 calc(100% - 1.5rem), transparent);
  mask-image: linear-gradient(180deg, #000 calc(100% - 1.5rem), transparent);
}

@supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
  .glass-thin, .glass-regular, .glass-thick, .ornament { --_bg: var(--_solid); }
  .toolbar::before { background: var(--solid-thin); }
}
@media (prefers-reduced-transparency: reduce) {
  .glass-thin, .glass-regular, .glass-thick, .ornament {
    --_bg: var(--_solid);
    -webkit-backdrop-filter: none; backdrop-filter: none;
  }
  .toolbar::before { background: var(--solid-thin); -webkit-backdrop-filter: none; backdrop-filter: none; }
}
@media (prefers-contrast: more) {
  .glass-thin, .glass-regular, .glass-thick, .ornament { --_bg: var(--_solid); -webkit-backdrop-filter: none; backdrop-filter: none; }
  .toolbar::before { background: var(--solid-thin); -webkit-backdrop-filter: none; backdrop-filter: none; }
  .environment::after { content: ""; position: absolute; inset: 0; background: rgb(4 8 24 / 0.35); }
}
@media (forced-colors: active) {
  .environment { display: none; }
  .glass-thin, .glass-regular, .glass-thick, .ornament { background: Canvas; border: 1px solid CanvasText; -webkit-backdrop-filter: none; backdrop-filter: none; }
}

/* ---------- platter ---------- */
.platter { background: var(--platter); box-shadow: var(--platter-edge); border-radius: var(--r-md); }

:focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }
```

**Environment DOM.** Add this as the first child of `.app` in `App.tsx`:

```tsx
<div className="environment" aria-hidden="true">
  <div className="env-field" />
  <div className="env-band" />
  <div className="env-reeds" />
</div>
```

- `.environment` must **never be an ancestor** of glass. It is a sibling at the back.
- The reeds use a normal blend at the alphas given in the tokens (ridge white 6%/5%, groove black 7%/10%). This keeps the contrast model exact.
- An SVG `feDisplacementMap` refraction is a possible later enhancement, but not baseline: it rasterises on the CPU and repaints on resize.
- No animation, no parallax and no `filter: blur` on the environment. The gradient falloff already supplies the softness. Animating the environment would force every glass layer to re-blur on every frame.

**The glass class owns `background`.** Component rules must never set `background` or `background-color` on an element that also carries a glass class. CSS load order (`base.css` first, feature CSS after) would let the component rule win and silently remove the glass. To tint glass, set `--_wash` (for example `.load-error { --_wash: var(--red-wash) }`). To change tier, override `--_bg`, `--_blur`, `--_sat`, `--_solid` and `--_shadow`, as the drawer does in §9.1.

**Class map.** Replace `className="… material"` and `"material-thick"` in components:

| Element | Class |
|---|---|
| `.toolbar` | none. Its `::before` is the scroll-edge blur. Remove `material` and the bottom border. |
| `.week-strip`, the History button, the "Today" button, the agent toggle | `.ornament` (no blur; sits on the toolbar edge) |
| `.timeline`, `.empty-day`, `.skeleton`, `.load-error`, `.widget`, `.checklist-empty`, `.chat` (desktop) | `.glass-regular` |
| `.chat` in the ≤ 1080 px drawer, `.sheet`, `.popover`, `.toast` | `.glass-thick` |

---

## 6. Contrast report (computed)

Method:

- sRGB alpha compositing, as browsers do it.
- Each glass tier is composited over the **darkest** and **lightest** environment stop. The lightest includes the reed ridge highlight. Blur averages the backdrop, so it cannot exceed the brightest stop.
- The top specular highlight is applied everywhere, which is conservative.
- `saturate()` is treated as luminance-neutral. When it clips it can only *lower* luminance, which only helps white text.

Format: worst (lightest backdrop) / best (darkest backdrop). Targets: 4.5:1 for body text, 3:1 for large text and essential graphics.

### Day

| Pair | thin (toolbar band) | regular (windows) | thick (floating) |
|---|---|---|---|
| `--label` white on glass | 7.86 / 9.69 | 8.21 / 13.28 | 10.42 / 14.92 |
| `--label-secondary` 0.84 on glass | 6.10 / 7.38 | 6.37 / 9.83 | 7.91 / 10.90 |
| `--label-tertiary` 0.62 (icons only) | 4.13 / 4.83 | 4.30 / 6.09 | 5.13 / 6.61 |
| White on platter, hover (worst) | 6.24 | 6.46 | 7.99 |
| Secondary on platter, rest / hover | 5.32 / 4.96 | 5.51 / 5.13 | 6.75 / 6.23 |
| Task title on tinted platter, hover (worst tint: yellow) | — | **5.58** | — |
| Task meta (secondary) on tinted platter (worst: yellow) | — | **4.79** | — |
| Checkbox ring 0.74 vs platter | 4.53 | 4.70 | 5.66 |
| Lime vs glass | 6.13 | 6.41 | 8.13 |
| White number on selected lozenge | 4.74 | 4.85 | 5.79 |
| Lime text / `--red-text` on window | — | 6.41 / 5.17 | — |
| `--red-text` / lime text on a widget with a 5% yellow wash (worst) | — | 4.65 / 5.76 | — |
| White on ink-based duration pill on a washed platter | — | 10.78 | — |
| White label on glass button (`btn-tinted`) rest / hover | — | 5.66 / 5.10 | — |
| Placeholder (secondary) in a field on a window | — | 5.01 | — |
| Flag `#FFC46B` glyph on platter, hover | — | 4.11 | — |
| White on red-wash / lime-wash platter | — | 6.93 / 5.84 | — |

### Night

| Pair | thin | regular | thick |
|---|---|---|---|
| `--label` on glass | 11.49 / 14.19 | 8.41 / 15.45 | 10.82 / 16.72 |
| `--label-secondary` on glass | 8.64 / 10.43 | 6.50 / 11.26 | 8.18 / 12.06 |
| `--label-tertiary` (icons only) | 5.51 / 6.39 | 4.37 / 6.78 | 5.27 / 7.13 |
| White on platter, hover | 8.76 | 6.59 | 8.28 |
| Secondary on platter, rest / hover | 7.35 / 6.76 | 5.62 / 5.23 | 6.97 / 6.42 |
| Task title / meta on tinted platter (worst: yellow) | — | **5.68 / 4.87** | — |
| Checkbox ring | 6.12 | 4.78 | 5.83 |
| Lime vs glass | 8.97 | 6.56 | 8.44 |
| Selected lozenge label | 6.26 | 4.94 | 5.97 |
| Lime text / `--red-text` on window | — | 6.56 / 5.29 | — |
| `--red-text` / lime text on a widget with a 5% yellow wash (worst) | — | 4.74 / 5.89 | — |
| White on ink-based duration pill on a washed platter | — | 10.91 | — |
| Glass-button label, rest / hover | — | 5.77 / 5.20 | — |
| Placeholder (secondary) in a field on a window | — | 5.10 | — |
| Flag glyph on platter | — | 4.20 | — |
| White on red-wash / lime-wash platter | — | 7.03 / 5.94 | — |

### On the environment and on solids

| Pair | Day | Night |
|---|---|---|
| Display white, anywhere (lightest stop + reed) | 3.81 (needs 3) | 5.10 |
| White brand or headline on top band (worst) | 5.93 | 13.08 |
| Subtitle white 0.88 on top band | 4.99 | 10.47 |
| Lime dot or focus ring on top band | 4.63 | 10.21 |
| White pill edge vs lightest environment | 3.81 | 5.10 |
| Ink on white pill / ink on lime | 18.93 / 14.77 | same |
| Ink glyph on tints (indigo … yellow) | 6.64 – 13.69 | same |
| White on a tint (forbidden, L4) | 1.38 – 2.85 | same |
| Opaque twins, white / secondary (thin · regular · thick) | 12.41 · 13.50 · 14.98 / 9.20 · 9.99 · 10.95 | 16.84 · 15.75 · 16.88 / 12.10 · 11.45 · 12.16 |

**Failures found and designed out.** In the reference, white text sits on a lightened glass card at about 2.9:1, and the inactive feature items sit at about 1.5:1. A first pass of this design failed too: secondary text on platters reached 3.2:1 and tinted glyphs 1.5:1. The fixes were:

- the luminance cap (L1)
- glass α raised to 0.56 (Day) and 0.50 (Night)
- platters capped at 6–9%
- secondary label raised to 0.84
- tint wash cut to 8% (5% on widgets)
- ink-on-tint discs (L4)

A second pass caught three more problems, all fixed:
- a white-on-white duration pill on a tinted platter (4.37), now ink-based (10.8)
- red text on a washed widget (4.06), now `#FFBDB6` with a 5% wash (4.65)
- the old 0.55-opacity done cards (L8)

---

## 7. Typography

The system stack is unchanged (never self-host SF). Apple's Dynamic Type scale is unchanged. The display tier is new:

| Token | Size | Weight / tracking / line-height | Used by (only these) |
|---|---|---|---|
| `--text-display-xl` | clamp 44 → 72 px | 300 / −0.035em / 1.02 | Day header `h1` ("Today", "Thursday") |
| `--text-display-l` | clamp 32 → 44 px | 300 / −0.03em / 1.05 | `.section-head h2` ("Checklist") |
| `--text-count` | 32 px | 300 / −0.02em / 1 | `.widget-count` ("4/15") |
| `--text-time-l` | 28 px | 300 / −0.02em / 1.1 | Task-sheet time card numerals |
| `--text-progress` | 24 px | 300 / −0.01em | `.section-head .progress` (on the environment) |
| `--text-time` | 22 px (20 px on phones) | 300 / −0.01em | Task-card start and end numerals |

All numerals use `font-variant-numeric: tabular-nums`. Headlines (17/600), body (17/400), footnotes and captions keep their Apple weights. Under `prefers-contrast: more`, `--w-light` becomes 400. The brand stays `--font-rounded` 700 at 20 px, white.

---

## 8. Colour roles

| Role | Token | Where |
|---|---|---|
| Interactive | `--accent` #FFF, `--on-accent` ink | White pills (primary), white labels on glass buttons, user bubbles, the send button, selected menu item, and selected states under increased contrast |
| Signal ("now / selected / live") | `--signal` lime | Today dot, now-line and its time capsule, elapsed ruler ticks, active tab underline, agent-online dot, activity dot, switch on, the "Today" meta text, the dot on the "Today" toolbar button, focus ring, `::selection` (ink text on lime) |
| Content hue | `--type-*`, section tints | Type discs, task-platter wash at 8%, ruler ticks, checkbox fill, widget icon disc and widget-window wash at 5% |
| Missed / destructive | `--red`, `--red-text`, `--red-wash` | Missed widget disc, missed meta text, error platters |
| Priority | `--flag` | High-priority flag glyph |

**Rule:** at most one lime element per component, and lime never fills an area larger than the 22 px now-capsule or a 2 px line. The switch track is the one exception.

---

## 9. Component mapping

CSS below is the target state. "TSX" notes the few markup changes; everything else is CSS only.

### 9.1 App shell and layout (`app.css`)

```css
.app { display: grid; grid-template-columns: minmax(0, 1fr) var(--inspector-w); height: 100dvh; }
.main-column { min-width: 0; height: 100dvh; overflow-y: auto; scroll-padding-top: var(--toolbar-h);
  scrollbar-width: thin; scrollbar-color: rgb(255 255 255 / .32) transparent; }
.content { display: grid; gap: var(--s8); max-width: calc(var(--content-max) + 2 * var(--s8)); margin: 0 auto;
  padding: var(--s6) var(--s8) var(--s16); }

/* desktop: the agent is a floating window inset from the viewport edge */
.inspector { min-width: 0; height: 100dvh; padding: var(--inspector-inset) var(--inspector-inset) var(--inspector-inset) 0; }
.inspector .chat { border-radius: var(--r-xl); overflow: hidden; }

@media (max-width: 1080px) {
  .app { grid-template-columns: minmax(0, 1fr); }
  .inspector {
    position: fixed; top: var(--s2); right: var(--s2); bottom: var(--s2); z-index: 30; padding: 0;
    width: min(var(--inspector-w), calc(100vw - 2 * var(--s2))); height: auto;
    transform: translateX(calc(100% + var(--s2)));
    transition: transform var(--dur-drawer) var(--ease-drawer);
  }
  /* swap the drawer's chat to the thick tier; it sits over other glass */
  .inspector .chat { --_bg: var(--glass-thick-bg); --_blur: var(--glass-thick-blur); --_sat: var(--glass-thick-sat); --_solid: var(--solid-thick); --_shadow: var(--shadow-float); }
  .app[data-chat-open] .inspector { transform: translateX(0); }
  .scrim { display: block; position: fixed; inset: 0; z-index: 25; background: var(--backdrop);
    opacity: 0; pointer-events: none; transition: opacity var(--dur-base) ease; }
  .app[data-chat-open] .scrim { opacity: 1; pointer-events: auto; }
}
@media (max-width: 760px) {
  .content { padding: var(--s4) var(--s4) var(--s16); gap: var(--s6); }
  .content > .glass-regular, .widget { border-radius: 28px; }   /* window 28 − padding 8 = platter 20 */
  .timeline { padding: var(--s2); }
}
@media (max-width: 480px) {
  .inspector { inset: 0; width: 100vw; }
  .inspector .chat { border-radius: 0; padding-top: env(safe-area-inset-top); }
}
@media (prefers-reduced-motion: reduce) { .inspector { transition: none; } }
```

- The drawer's scrim matters for legibility. It dims the white Import pill and the white text that would otherwise blur into a bright blob behind the drawer header.
- `index.html`: set `<meta name="color-scheme" content="dark">`. Add `<meta name="theme-color" content="#0A4E86" media="(prefers-color-scheme: light)">` and `content="#071640"` for dark.

### 9.2 Toolbar: pill nav → week strip, glass circles, white pill

```css
.toolbar { position: sticky; top: 0; z-index: 20; }            /* no material, no border; ::before in base.css */
.toolbar-inner { display: grid; grid-template-columns: 1fr auto 1fr; align-items: center; gap: var(--s4);
  min-height: var(--toolbar-h); max-width: calc(var(--content-max) + 2 * var(--s8)); margin: 0 auto; padding: var(--s2) var(--s6); }
.brand { font-family: var(--font-rounded); font-size: 1.25rem; font-weight: 700; color: var(--label-on-env); }
.toolbar-actions { display: flex; justify-content: flex-end; align-items: center; gap: var(--s2); }

/* round glass ornament buttons (History, agent toggle) */
.toolbar .icon-btn { width: var(--control-h); height: var(--control-h); border-radius: 50%; color: var(--label); }
.toolbar .icon-btn[aria-pressed="true"], .toolbar .icon-btn[aria-expanded="true"] { background: #fff; color: var(--ink); }
.activity-dot { top: 2px; right: 2px; width: 8px; height: 8px; background: var(--signal); box-shadow: 0 0 0 2px var(--solid-thin); }

/* Import = the reference's solid white pill */
.toolbar .btn-filled { min-height: var(--control-h); padding: 0 var(--s4) 0 var(--s3); }
/* "Today" (shown when another day is selected) = ornament pill with a lime dot */
.toolbar .today-btn { min-height: var(--control-h); padding: 0 var(--s4); border-radius: var(--r-full); color: var(--label); font-weight: 600; }
.toolbar .today-btn::before { content: ""; width: 6px; height: 6px; border-radius: 50%; background: var(--signal); }
```

TSX for `App.tsx`:

- Give the History trigger (in `HistoryPopover`) and the chat toggle `className="icon-btn ornament"`.
- Change the "Today" button to `className="btn today-btn ornament"`.
- Swap the Import button's `btn-tinted` for `btn-filled`.

**Week strip** (`timeline.css`), modelled on the reference's pill nav:

```css
.week-strip { display: flex; align-items: center; gap: 2px; height: var(--ornament-h); padding: 4px; border-radius: var(--r-full); }
.week-strip > .icon-btn { width: 2rem; height: 2rem; border-radius: 50%; color: var(--label-secondary); }
.week-strip ol { display: flex; gap: 2px; margin: 0; padding: 0; list-style: none; }
.week-strip .day { position: relative; isolation: isolate; /* keeps the z-index:-1 lozenge above the capsule fill */ display: grid; justify-items: center; gap: 1px; width: 2.75rem; height: 3rem;
  padding-top: 5px; border: 0; border-radius: var(--r-full); background: transparent; color: var(--label); cursor: pointer;
  transition: transform var(--dur-press) var(--ease-out), background-color var(--dur-hover) ease; }
.week-strip .day:active { transform: scale(0.96); }
.week-strip .dow { font-size: var(--text-caption2); font-weight: 600; letter-spacing: 0.02em; color: var(--label-secondary); }
.week-strip .num { font-size: var(--text-subhead); font-weight: 500; background: none; width: auto; height: auto; }
.week-strip .dot { width: 4px; height: 4px; border-radius: 50%; background: transparent; }
.week-strip .dot[data-on] { background: var(--label-tertiary); }
.week-strip .day[data-today] .dot { width: 5px; height: 5px; background: var(--signal); }   /* lime = today, always */
.week-strip .lozenge { position: absolute; inset: 0; z-index: -1; border-radius: inherit;
  background: var(--lozenge); box-shadow: inset 0 1px 0 rgb(255 255 255 / .22); }
.week-strip .day[aria-current="date"] .num { font-weight: 700; }
@media (hover: hover) and (pointer: fine) { .week-strip .day:hover { background: var(--platter-hover); } }
@media (prefers-contrast: more) { .week-strip .day[aria-current="date"] :is(.num, .dow) { color: var(--ink); } }
```

TSX for `WeekStrip.tsx`:

- Inside the selected day button, render `<motion.span layoutId="day-lozenge" className="lozenge" transition={{ type: "spring", duration: 0.3, bounce: 0 }} />`. The lozenge then slides between days, like the reference's active nav pill.
- When the selected day is today, the result is exactly the reference: a lozenge with a lime dot.

**Phones (≤ 760 px):**

- Hide the brand and the week chevrons (as today).
- Use `.toolbar-inner { display: flex; justify-content: space-between; padding: var(--s2); }`.
- Set `--control-h: 2.25rem` and `.day { width: 2.125rem }`; at ≤ 400 px, `.day { width: 2rem }`.
- Import becomes a 36 px white circle showing only the plus icon.
- Toolbar buttons keep their 44 px hit area through `::after`. The arithmetic (7 × 32 days + 6 × 2 gaps + 8 capsule padding + 3 × 36 buttons + 2 × 8 gaps + 2 × 8 gutters ≈ 384 px) fits a 390 px phone; at 375 px, days go to 30 px.

### 9.3 Day header (on the environment, top band)

```css
.day-head { margin-bottom: calc(-1 * var(--s3)); }
.day-head h1 { font-family: var(--font-display); font-size: var(--text-display-xl); font-weight: var(--w-light);
  letter-spacing: var(--track-display); line-height: 1.02; color: var(--label-on-env); text-shadow: var(--display-halo); }
.day-head p { margin-top: var(--s2); font-size: var(--text-body); color: var(--label-on-env-secondary); }
```

### 9.4 Day window: timeline, task cards, ruler, duration pill, now-line, free gaps

`timeline.css`:

```css
.timeline { display: grid; gap: var(--s2); padding: var(--win-pad); border-radius: var(--r-xl); }   /* + .glass-regular */
.anytime .group-title { padding: var(--s2) var(--s3); font-size: var(--text-footnote); font-weight: 500;
  letter-spacing: 0.02em; text-transform: uppercase; color: var(--label-secondary); }
.anytime-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(14rem, 1fr)); gap: var(--s2); margin: 0 0 var(--s2); padding: 0; list-style: none; }
.timed { display: grid; gap: var(--s2); margin: 0; padding: 0; list-style: none; }
.timed .slot { display: block; }                      /* the time gutter is gone: times live in the card */

/* ---- task card = platter ---- */
.task-card {
  --tint: var(--type-other);
  --_wash: color-mix(in srgb, var(--tint) var(--tint-wash-amount), transparent);
  position: relative;
  display: grid; grid-template-columns: auto minmax(0, 1fr) auto; column-gap: var(--s3); row-gap: var(--s1);
  width: 100%; min-height: 3.75rem; padding: var(--s3) var(--s4) var(--s3) var(--s3);
  border: 0; border-radius: var(--r-md); text-align: left; color: var(--label); cursor: pointer;
  background-color: var(--platter);
  background-image: linear-gradient(var(--_wash), var(--_wash));
  box-shadow: var(--platter-edge);
  transition: transform var(--dur-press) var(--ease-out), background-color var(--dur-hover) ease;
}
.task-card[data-size="regular"] { padding-bottom: calc(var(--s3) + var(--ruler-h) + 4px); }
.task-card:active { transform: scale(0.985); }
@media (hover: hover) and (pointer: fine) { .task-card:hover { background-color: var(--platter-hover); } }

.task-card .glyph { grid-row: span 2; display: grid; place-items: center; width: 1.75rem; height: 1.75rem;
  border-radius: 50%; background: var(--tint); color: var(--ink); }                 /* L4: ink on tint */
.task-card .title { font-size: var(--text-headline); font-weight: 600; line-height: 1.3; }
.task-card .badges { display: flex; align-items: center; gap: var(--s2); padding-top: 3px;
  font-size: var(--text-caption1); font-weight: 600; color: var(--label-secondary); }
.task-card .kind { font-weight: 500; }                   /* the reference's "ıl Beginners" chip, as plain text */
.task-card .flag { color: var(--flag); }
.task-card .meta { grid-column: 2 / -1; display: flex; flex-wrap: wrap; align-items: center; gap: 6px;
  font-size: var(--text-footnote); color: var(--label-secondary); }

/* regular (timed, ≥ 45 min): reference Start/End in large light numerals + duration pill on a hairline */
.task-card .when { grid-column: 2 / -1; display: grid; grid-template-columns: auto 1fr auto; align-items: center; column-gap: var(--s3); }
.task-card .when .t { font-size: var(--text-time); font-weight: var(--w-light); letter-spacing: -0.01em; line-height: 1.15; }
.task-card .when .track { display: grid; place-items: center; height: 1.5rem;
  background: linear-gradient(var(--separator), var(--separator)) center / 100% 1px no-repeat; }

/* duration pill: the reference's dark "◷ 2h". Ink-based, because a white-based pill on a tinted platter fails (4.37:1) */
.dur-pill { display: inline-flex; align-items: center; gap: 3px; padding: 2px 8px; border-radius: var(--r-full);
  background: color-mix(in srgb, var(--ink) 45%, transparent); box-shadow: inset 0 0 0 0.5px rgb(255 255 255 / .18);
  font-size: var(--text-caption1); font-weight: 600; color: var(--label); }

/* ruler: the reference's tick scale along the card's bottom edge */
.task-card .ruler { position: absolute; left: 0; right: 0; bottom: 0; height: var(--ruler-h);
  border-radius: 0 0 var(--r-md) var(--r-md); overflow: hidden; pointer-events: none; }
.task-card .ruler::before, .task-card .ruler::after { content: ""; position: absolute; inset: 0;
  background:
    repeating-linear-gradient(90deg, var(--_tick) 0 1px, transparent 1px var(--tick-major-every)) left bottom / 100% var(--tick-major-h) no-repeat,
    repeating-linear-gradient(90deg, var(--_tick) 0 1px, transparent 1px var(--tick-pitch)) left bottom / 100% var(--tick-h) no-repeat;
  background-position-x: var(--s3); }
.task-card .ruler::before { --_tick: color-mix(in srgb, var(--tint) 55%, transparent); }
.task-card .ruler::after { --_tick: var(--signal); clip-path: inset(0 calc((1 - var(--progress, 0)) * 100%) 0 0); }

/* done: no opacity dimming (L8) */
.task-card[data-done] { background-image: none; }
.task-card[data-done] .title { color: var(--label-secondary); text-decoration: line-through; text-decoration-color: rgb(255 255 255 / .45); }
.task-card[data-done] .ruler { opacity: .35; }

/* ---- now-line: lime capsule + 2px rule ---- */
.timed .now-line { display: grid; grid-template-columns: auto 1fr; align-items: center; gap: var(--s2); padding: 2px 0; }
.timed .now-line .time { padding: 2px 8px; border-radius: var(--r-full); background: var(--signal); color: var(--on-signal);
  font-size: var(--text-caption1); font-weight: 700; text-align: left; }
.timed .now-line .rule { height: 2px; border-radius: 1px; background: var(--signal); }
.timed .now-line .rule::before { content: none; }

/* ---- free gap: a faint, untinted ruler with a "Free · 1h 15m" pill ---- */
.timed .free { display: grid; grid-template-columns: auto 1fr; align-items: center; gap: var(--s2); min-height: 2rem; padding: 0 var(--s1); }
.timed .free-label { padding: 2px 8px; border: 0; margin: 0; border-radius: var(--r-full); background: var(--fill-quaternary);
  font-size: var(--text-caption1); font-weight: 500; color: var(--label-secondary); }
.timed .free::after { content: ""; height: 6px;
  background: repeating-linear-gradient(90deg, var(--label-quaternary) 0 1px, transparent 1px var(--tick-pitch)) left bottom / 100% 6px no-repeat; }

/* empty, loading and error states are windows too */
.empty-day { display: grid; justify-items: center; gap: var(--s2); padding: var(--s12) var(--s4); border-radius: var(--r-xl); text-align: center; color: var(--label-tertiary); }
.empty-day h3 { margin-top: var(--s2); font-size: var(--text-title3); font-weight: 600; color: var(--label); }
.empty-day p { max-width: 22rem; font-size: var(--text-subhead); color: var(--label-secondary); margin-bottom: var(--s3); }
.skeleton { display: grid; gap: var(--s2); padding: var(--win-pad); border-radius: var(--r-xl); }                 /* + .glass-regular */
.skeleton span { height: 4rem; border-radius: var(--r-md); background: var(--platter); animation: pulse 1.2s ease-in-out infinite alternate; }
@keyframes pulse { from { opacity: .5; } to { opacity: 1; } }
.load-error { --_wash: var(--red-wash); padding: var(--s4) var(--s5); border-radius: var(--r-xl); color: var(--label); font-size: var(--text-subhead); }  /* + .glass-regular; delete its old background */
@media (max-width: 760px) { .task-card .when .t { font-size: var(--text-title3); } }
@media (prefers-reduced-motion: reduce) { .skeleton span { animation: none; opacity: .75; } }
```

TSX for `DayTimeline.tsx`. Give `<section className="timeline">` the class `glass-regular`; give `.empty-day` the same. Then change `TaskCard`:

- **Size.**
  - Add `data-size`: `regular` when `!compact && task.start && (task.duration_min ?? 0) >= 45`, otherwise `compact`.
  - Regular `minHeight` = `min(10, max(6, duration/16))rem`. Compact keeps `max(3.75, …)`.
- **Glyph.** Show the type icon, or `Check` when done, in ink at stroke 2 on the tint disc.
- **Regular body.**
  - Title.
  - Badges: `<span className="kind">{kind.label}</span>`, then flag, checklist and resources.
  - The `when` row: `<span class="t">start</span><span class="track"><span class="dur-pill"><Clock3 size={11}/>{formatDuration}</span></span><span class="t">end</span>`.
  - The ruler: `<span className="ruler" aria-hidden="true" style={{"--progress": p}} />`.
- **Compact body.**
  - Timed: `.meta` shows `{start}–{end}`, then `<dur-pill>`, then `{kind}`.
  - Anytime: `.meta` shows `<dur-pill>` then `{kind}`. There is **no ruler**, because anytime tasks have no place in time.
- **Progress.** `p` is `(now − start) / duration` clamped to 0–1 for the task running now on today, and `0` otherwise. Pass `now` from `DayTimeline`. It updates every 30 s with no transition.
- **Remove the gutter.**
  - Delete the gutter `<span className="time">` from slot and free rows. The card's `aria-label` already carries the start time.
  - The now-line keeps its `.time` as the capsule.
- Add `aria-label` text "high priority" when flagged. The flag is visual-only today.

### 9.5 Checklist: section head, widgets, rows, checkboxes on glass

```css
.section-head { display: flex; align-items: baseline; justify-content: space-between; gap: var(--s3); margin-bottom: var(--s4); }
.section-head h2 { font-family: var(--font-display); font-size: var(--text-display-l); font-weight: var(--w-light);
  letter-spacing: -0.03em; line-height: 1.05; text-shadow: var(--display-halo); }
.section-head .progress { font-size: var(--text-progress); font-weight: var(--w-light); color: var(--label-on-env); text-shadow: var(--display-halo); }
.checklist-empty { padding: var(--s4) var(--s5); border-radius: var(--r-widget); color: var(--label-secondary); }   /* + .glass-regular */

.widgets { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 20rem), 1fr)); gap: var(--s4); align-items: start; }
.widget { --tint: var(--teal); --_wash: color-mix(in srgb, var(--tint) var(--widget-wash-amount), transparent);
  padding: var(--s4) 0 var(--s2); border-radius: var(--r-widget); overflow: hidden; }         /* + .glass-regular */
.widget-head { display: flex; align-items: center; gap: var(--s2); padding: 0 var(--s4) var(--s2); }
.widget-icon { display: grid; place-items: center; flex: none; width: 1.75rem; height: 1.75rem; border-radius: 50%;
  background: var(--tint); color: var(--ink); }
.widget-head h3 { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  font-size: var(--text-headline); font-weight: 600; color: var(--label); }                 /* white, not tinted */
.widget-count { font-family: var(--font-display); font-size: var(--text-count); font-weight: var(--w-light);
  letter-spacing: -0.02em; line-height: 1; color: var(--label); }

.check-row { --tint: var(--accent); position: relative; display: grid; grid-template-columns: auto 1fr auto; align-items: center;
  gap: var(--s3); min-height: 3rem; padding: var(--s1) var(--s2) var(--s1) var(--s4); background: transparent; }
.check-row + .check-row::before { content: ""; position: absolute; top: 0; right: 0; left: calc(var(--s4) + 22px + var(--s3));
  height: 0.5px; background: var(--separator); }
.row-title { font-size: var(--text-callout); line-height: 1.3; }
.row-meta { font-size: var(--text-footnote); color: var(--label-secondary); }
.row-meta[data-today] { color: var(--signal); }          /* L5: lime text, window only */
.row-meta[data-missed] { color: var(--red-text); }       /* L5: red text, window only */
.row-sub { color: var(--label-secondary); }             /* was tertiary: informative, so secondary (L3) */
.check-row[data-done] .row-title { color: var(--label-secondary); text-decoration: line-through; text-decoration-color: rgb(255 255 255 / .45); }
.row-actions .icon-btn { color: var(--label-tertiary); }
.row-actions .icon-btn[aria-expanded="true"] { color: var(--label); background: var(--lozenge); }
@media (hover: hover) and (pointer: fine) {
  .check-row:hover .row-actions .icon-btn { color: var(--label-secondary); }
  .row-actions .icon-btn:hover { color: var(--label); background: var(--platter-hover); }
}
.widget-more { margin: var(--s1) var(--s3) 0; font-size: var(--text-footnote); font-weight: 600; color: var(--label); }
```

There is no row hover background. That keeps `--red-text` and lime text on the window, as L5 requires.

TSX for `Checklist.tsx`:

- Give `<motion.section className="widget">` the class `glass-regular`.
- The `WIDGET_TINTS` comment about yellow no longer applies. Titles are white now, so `var(--yellow)` may be added.

**Checkbox** (`primitives.css`): a Reminders circle on glass.

```css
.checkbox .ring { fill: none; stroke: var(--check-ring); stroke-width: 1.75; }
.checkbox .fill { fill: var(--check); }
.checkbox .mark { stroke: var(--ink); stroke-width: 2.4; }            /* was #fff: L4 */
.checkbox input:focus-visible + svg { outline: 2px solid var(--focus); outline-offset: 2px; border-radius: 50%; }
@media (hover: hover) and (pointer: fine) { .checkbox:hover .ring { stroke: var(--check); } }
```

The fill-scale and stroke-draw timings are unchanged.

### 9.6 Agent window (`chat.css`)

```css
.chat { display: flex; flex-direction: column; height: 100%; min-height: 0; border-left: 0; }   /* + .glass-regular */
.chat-head { display: flex; align-items: center; gap: var(--s3); min-height: 3.5rem; padding: var(--s2) var(--s3) var(--s2) var(--s4);
  border-bottom: 0.5px solid var(--separator); }
.chat-title { color: var(--label); }
.status-dot { width: 7px; height: 7px; background: var(--label-quaternary); }
.status-dot[data-on] { background: var(--signal); }                 /* the reference's lime dot */
.chat-status, .react-toggle { color: var(--label-secondary); }

.chat-scroll { padding: var(--s4); scrollbar-width: thin; scrollbar-color: rgb(255 255 255 / .32) transparent;
  /* soft fade at the edges: allowed because nothing inside blurs */
  -webkit-mask-image: linear-gradient(transparent, #000 12px, #000 calc(100% - 12px), transparent);
  mask-image: linear-gradient(transparent, #000 12px, #000 calc(100% - 12px), transparent); }
.bubble { border-radius: var(--r-md); font-size: var(--text-subhead); line-height: 1.4; }
.bubble.user { background: #fff; color: var(--ink); border-bottom-right-radius: 6px; }          /* white = you */
.bubble.assistant { background: var(--platter); box-shadow: var(--platter-edge); color: var(--label); border-bottom-left-radius: 6px; }
.event-chip { border-radius: 14px; background: var(--platter); color: var(--label-secondary); }
.tool-row { color: var(--label-secondary); }
.tool-row[data-done] svg { color: var(--signal); }
.chat-error { background: var(--red-wash); color: var(--label); }
.chat-error svg { color: var(--red-text); }
.changes-card { border-radius: var(--r-md); background: var(--platter); box-shadow: var(--platter-edge); }
.changes-card ul { color: var(--label-secondary); }
.changes-card li[data-undone] { color: var(--label-secondary); text-decoration: line-through; }   /* not tertiary (L3) */
.typing { background: var(--platter); border-radius: var(--r-md); }
.typing span { background: var(--label-secondary); }
.chat-empty { color: var(--label-tertiary); }
.chat-empty p { color: var(--label-secondary); }
.suggestions .btn { border-radius: var(--r-full); }      /* .btn-gray = glass button */
.composer { border-top: 0.5px solid var(--separator); }
.composer .field { border-radius: var(--r-full); }
.send { background: #fff; color: var(--ink); }
.send:disabled { opacity: 1; background: var(--fill); color: var(--label-tertiary); }
```

In TSX, give the `<aside className="chat">` the class `glass-regular`. Narrow screens get the thick-tier override from §9.1.

### 9.7 Shared controls (`base.css`)

```css
.btn { border-radius: var(--r-full); min-height: 2.25rem; padding: 0 var(--s4);
  transition: transform var(--dur-press) var(--ease-out), background-color var(--dur-hover) ease; }
.btn:active:not(:disabled) { transform: scale(0.97); }
.btn:disabled { opacity: 1; color: var(--label-tertiary); cursor: default; }
.btn:is(.btn-filled, .btn-tinted, .btn-gray):disabled { background: var(--fill-tertiary); }   /* disabled controls are exempt from 1.4.3 */
.btn-filled { background: #fff; color: var(--ink); }                                  /* the reference's white pill */
.btn-tinted { background: var(--fill-secondary); color: var(--label); box-shadow: inset 0 1px 0 rgb(255 255 255 / .12); }  /* glass button */
.btn-gray { background: var(--fill-tertiary); color: var(--label); }
.btn-plain { background: transparent; color: var(--label); padding: 0 var(--s2); }  /* "Schedule Demo ↗" text link */
.btn-large { min-height: 3rem; padding: 0 var(--s6); border-radius: var(--r-full); font-size: var(--text-body); }
@media (hover: hover) and (pointer: fine) {
  .btn-filled:hover:not(:disabled) { background: rgb(255 255 255 / .88); }
  .btn-tinted:hover:not(:disabled) { background: var(--fill); }
  .btn-gray:hover:not(:disabled) { background: var(--fill-secondary); }
  .btn-plain:hover { text-decoration: underline; text-underline-offset: 3px; text-decoration-color: rgb(255 255 255 / .5); }
}
.icon-btn { border-radius: 50%; color: var(--label); }
.icon-btn.secondary { color: var(--label-secondary); }
.icon-btn[aria-pressed="true"], .icon-btn[aria-expanded="true"] { background: var(--lozenge); }
@media (hover: hover) and (pointer: fine) { .icon-btn:hover { background: var(--platter-hover); } }

.field { border-radius: var(--r-sm); background: var(--fill-tertiary); color: var(--label);
  box-shadow: inset 0 0 0 0.5px rgb(255 255 255 / .14); }
.field::placeholder { color: var(--label-secondary); }                             /* placeholders must pass 4.5:1 */
.field:focus { outline: none; box-shadow: inset 0 0 0 1px rgb(255 255 255 / .40), 0 0 0 3px color-mix(in srgb, var(--signal) 45%, transparent); }
input[type="date"].field { color-scheme: dark; }

.switch { background: var(--fill); box-shadow: inset 0 0 0 0.5px rgb(255 255 255 / .20); }
.switch:checked { background: var(--signal); }
.switch::after { background: #fff; box-shadow: 0 1px 3px rgb(0 0 0 / .25), 0 0 0 0.5px rgb(11 16 32 / .2); }

.chip { border-radius: var(--r-full); background: var(--fill-tertiary); color: var(--label-secondary); }
.group-title { color: var(--label-secondary); font-weight: 500; }
.group { border-radius: var(--r-md); background: var(--platter); box-shadow: var(--platter-edge); }

:focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }   /* drop the old border-radius override: outlines follow radius */
::selection { background: var(--signal); color: var(--ink); }
```

The **tab row** (the reference's feature row) replaces the segmented control's appearance. Markup and roles (`role="tablist"`, `aria-selected`) stay the same.

```css
.segmented { position: relative; display: grid; grid-auto-flow: column; grid-auto-columns: 1fr; padding: 0; border-radius: 0; background: none;
  box-shadow: inset 0 1px 0 var(--separator); }                       /* hairline track across the top */
.segmented button { position: relative; display: grid; justify-items: start; gap: 6px; min-height: 3.25rem; padding: var(--s3) var(--s2) var(--s2);
  border: 0; border-radius: 0; background: none; text-align: left; font-size: var(--text-subhead); font-weight: 500; color: var(--label-secondary); }
.segmented button svg { color: var(--label-tertiary); }
.segmented button[aria-selected="true"] { background: none; box-shadow: none; color: var(--label); font-weight: 600; }
.segmented button[aria-selected="true"] svg { color: var(--signal); }
.segmented .tab-underline { position: absolute; top: 0; left: 0; right: 0; height: 2px; border-radius: 1px; background: var(--signal); }
```

TSX for `ImportSheet.tsx`:

- Add a tiny 16 px line icon before each label: `FileUp`, `Database`, `Sparkles`.
- Render `<motion.span layoutId="tab-underline" className="tab-underline" />` inside the selected tab, with a spring of 0.25 s and bounce 0.

### 9.8 Sheets (`primitives.css`, `checklist.css`, `import.css`)

```css
.sheet { border-radius: var(--r-xl); color: var(--label); }   /* + .glass-thick (set in Sheet); delete the old `background: var(--bg-elevated)` */
.sheet::backdrop { background: var(--backdrop); }                            /* dim only: no second full-screen blur */
.sheet-header h2 { font-size: var(--text-title2); font-weight: 600; letter-spacing: -0.01em; }
@media (max-width: 640px) {
  .sheet { border-radius: var(--r-xl) var(--r-xl) 0 0; }
  .sheet-body::before { content: ""; display: block; width: 36px; height: 5px; margin: calc(-1 * var(--s2)) auto var(--s3);
    border-radius: var(--r-full); background: rgb(255 255 255 / .45); }      /* the reference panel's grabber (touch only) */
}
```

In `Sheet`, set `className={\`sheet glass-thick${wide ? " sheet-wide" : ""}\`}`. The `<dialog>` is in the top layer, so its glass sees the whole page.

**Task sheet.** The reference card appears here literally.

```css
.time-card { --tint: inherit; position: relative; display: grid; gap: var(--s1);
  padding: var(--s4) var(--s4) calc(var(--s4) + var(--ruler-h)); border-radius: var(--r-md);
  background-color: var(--platter); background-image: linear-gradient(color-mix(in srgb, var(--tint) 8%, transparent), color-mix(in srgb, var(--tint) 8%, transparent));
  box-shadow: var(--platter-edge); }
.time-card .head { display: flex; justify-content: space-between; align-items: baseline; }
.time-card .day { font-size: var(--text-title3); font-weight: 400; }                  /* "Friday" (the reference's "Mondays") */
.time-card .kind { display: inline-flex; gap: 4px; align-items: center; font-size: var(--text-caption1); font-weight: 600; color: var(--label-secondary); }
.time-card .labels { display: flex; justify-content: space-between; margin-top: var(--s2); font-size: var(--text-caption1); color: var(--label-secondary); }
.time-card .when { display: grid; grid-template-columns: auto 1fr auto; align-items: center; column-gap: var(--s3); }
.time-card .t { font-size: var(--text-time-l); font-weight: var(--w-light); letter-spacing: -0.02em; }
/* .track, .dur-pill and .ruler reuse the task-card rules (scope those selectors to `.task-card, .time-card`) */
.sheet-glyph { width: 2.25rem; height: 2.25rem; background: var(--tint); color: var(--ink); }
.facts { border-radius: var(--r-md); background: var(--platter); box-shadow: var(--platter-edge); }
.facts > div + div { box-shadow: inset 0 0.5px 0 var(--separator); }
.facts dt { color: var(--label-secondary); }
.task-sheet .group { background: var(--platter); }
.resource-row svg { color: var(--label-secondary); }          /* not the tint: a tint glyph on a platter fails 3:1 */
.resource-text a { color: var(--label); text-decoration: underline; text-decoration-color: rgb(255 255 255 / .4); text-underline-offset: 3px; }
.resource-note, .muted { color: var(--label-secondary); }
```

TSX for `TaskSheet.tsx`:

- Insert `.time-card` after the header. Its rows are:
  1. The weekday (or "Unscheduled") with a `kind` chip (type icon plus label).
  2. "Start" and "End" captions. These are omitted when there is no start time.
  3. Start, then the track holding the duration pill, then end. When there is no start, only the duration pill is shown.
  4. A ruler, with progress when the task is running now.
- Drop the **When** and **Duration** rows from `.facts` (the card shows them).
- Show "Mark as done" as `btn-filled btn-large` (the white pill). Its "Reopen" state becomes `btn-tinted btn-large`.
- "Ask the agent for resources" stays `btn-tinted` (a glass button).
- External resource links get a trailing `ArrowUpRight` (14 px), echoing "Schedule Demo ↗".

**Import sheet** (`import.css`):

```css
.drop-zone { border-radius: var(--r-lg); background: var(--fill-quaternary); box-shadow: none;
  border: 1.5px dashed rgb(255 255 255 / .30); color: var(--label-tertiary); }
.drop-zone[data-dragging] { border: 2px solid var(--signal); background: color-mix(in srgb, var(--signal) 8%, transparent); }
.drop-title { color: var(--label); }
.drop-hint, .field-label, .field-help { color: var(--label-secondary); }
.field-help code { padding: 1px 6px; border-radius: 6px; background: var(--fill-tertiary); }
.prompt-preview { border-radius: var(--r-md); background: var(--platter); color: var(--label-secondary); scrollbar-width: thin; }
.import-result { background: color-mix(in srgb, var(--signal) 16%, transparent); color: var(--label); }
.import-result svg { color: var(--signal); }
.import-errors { background: var(--red-wash); color: var(--label); }
```

In the drop zone, "Choose Folder…" is a white pill and "Choose Files…" is a glass button. The copied state of "Copy prompt" shows a lime `Check`.

### 9.9 Popovers: Move menu and History (`primitives.css`, `primitives.tsx`, `history.css`)

```css
.popover { border-radius: var(--r-popover); padding: 6px; font-size: var(--text-subhead); }   /* + .glass-thick */
.menu-item { min-height: 2.25rem; border-radius: 14px; color: var(--label); }                  /* 20 − 6 = 14, concentric */
.menu-item svg, .menu-item .hint { color: var(--label-secondary); }
@media (hover: hover) and (pointer: fine) {
  .menu-item:hover { background: #fff; color: var(--ink); }                                   /* the accent is white, so the highlight is a white pill */
  .menu-item:hover svg, .menu-item:hover .hint { color: rgb(11 16 32 / .62); }               /* ink 0.62 on white = 5.33:1 */
}
@media (pointer: coarse) { .menu-item { min-height: 2.75rem; } }
.menu-separator { background: var(--separator); }

.history-item > svg, .history-time, .history-empty { color: var(--label-secondary); }
.history-item[data-undone] .history-summary { color: var(--label-secondary); text-decoration: line-through; }
```

**Required code change: portal the popover.** Today the panel renders inside `.popover-anchor`, which can sit inside a `.widget`. A widget has `backdrop-filter`, so it is a **Backdrop Root**: a nested popover's blur would only see the widget's own pixels. The widget's `overflow: hidden` also clips the menu. In `Popover`:

1. Render the panel with `createPortal(panel, trigger.closest("dialog") ?? document.body)`.
   - Use the nearest open `<dialog>`, because a modal dialog makes the rest of the document inert and sits in the top layer.
2. Position it `position: fixed` from `trigger.getBoundingClientRect()`:
   - `top: rect.bottom + 8` and `right: innerWidth − rect.right` for `align="end"`, or `left: rect.left` for `start`.
   - Flip above the trigger when it would overflow the viewport, which replaces the `.sheet-footer .popover` override.
3. Close it on scroll of `.main-column`, on resize, and on Escape.
4. Keep `transform-origin` at the trigger corner.
5. Outside-click detection must test **both** `root.current` and the panel ref, because the panel is no longer inside `root`.

Inside a sheet the popover still nests under the sheet's glass. That is acceptable: thick-on-thick is darker, so contrast only rises.

### 9.10 Toasts (`toasts.css`)

```css
.toast { border-radius: var(--r-full); color: var(--label); }              /* + .glass-thick (replaces material-thick) */
.toast .btn-plain { font-weight: 600; }
.toast.error .toast-message { color: var(--label); }
.toast.error::before { content: ""; width: 8px; height: 8px; border-radius: 50%; background: var(--red); flex: none; }
```

There is an existing bug, noticed in passing and outside the restyle. A toast fired while a modal `<dialog>` is open (the Import success toast) renders *under* the top layer and is inert. A fix is to host `.toaster` in an element with `popover="manual"` that is shown on mount, which puts it in the top layer.

---

## 10. Motion

The skills' framework applies: how often, why, which easing, how long.

| Interaction | Animation | Why |
|---|---|---|
| Press: buttons, pills, ornaments / platters / icon circles | `scale(.97)` / `.985` / `.94`, 160 ms `--ease-out` | Confirms the press |
| Hover (fine pointer only) | `background-color` 120 ms `ease`, no transform | Tens of times a day, so as small as possible |
| Selected day changes | Lozenge `layoutId` spring, 0.3 s, bounce 0 | Spatial continuity, as the reference's nav pill slides |
| Import tab changes | Underline `layoutId` spring, 0.25 s | Same |
| Card enters, leaves or is re-planned | Unchanged: spring 0.45 s / 0.12; exit 150 ms | A re-plan reads as one movement |
| Now-line moves | `layout="position"` (unchanged) | |
| Checkbox tick | Unchanged; the mark is drawn in ink | Shows the state change |
| Popover | Opacity + `scale(.96)` → 1, 180 ms ease-out, origin at the trigger corner; exit 120 ms | Ties it to the trigger |
| Sheet | `@starting-style` opacity + `scale(.96)` (desktop) or `translateY(100%)` (phone), 260 ms; close 140 ms | Modals stay centred |
| Agent drawer | `translateX`, 320 ms `--ease-drawer` | iOS drawer curve |
| Toast | Spring from `translateY(100%)`; exit 150 ms | Same edge in and out |
| Ruler progress | None (steps every 30 s) | Imperceptible steps; a transition would be noise |
| Skeleton | Opacity 0.5 ↔ 1, 1.2 s ease-in-out, alternate | Loading feedback |

**Not animated:**

- `backdrop-filter`, blur radius and saturation (expensive, and blur transitions on glass shimmer)
- the environment (no drift or parallax)
- theme switching
- keyboard actions
- streamed tokens

Emil's "blur to mask a crossfade" is allowed only on small labels (≤ 2 px), never on glass.

**Reduced motion.** `MotionConfig reducedMotion="user"` stays. The lozenge and underline jump instead of sliding. CSS press scales, drawer and sheet translation, the spinner and the skeleton pulse are removed. Opacity fades remain.

---

## 11. Day (light) vs Night (dark)

| Aspect | Day (`prefers-color-scheme: light`) | Night (`dark`) |
|---|---|---|
| Environment | The reference palette: cerulean `#0B74AA`, cyan, magenta `#B02E6E`, coral `#CC4F62` and amber `#C95A48` cores, lavender and rose low corners. Top band `#0A4E86 → #0B5F98`. | Deeper and more saturated: navy `#071640` top band, teal-blue, indigo-black figure, plum `#7E1A56`, an ember core `#AE3A3E` / `#A84C2E`, violet lows. Max L 0.14. |
| Reeds | Ridge 6%, groove 7% | Ridge 5%, groove 10% (deeper grooves read better at night) |
| Glass | *Smoked*: tint `rgb(10 18 48)` at α 0.40 / 0.56 / 0.66, saturate 180 / 170 / 160% | Lighter alpha because the backdrop is darker: α 0.34 / 0.50 / 0.62, saturate 160 / 150 / 140%. Over navy the glass reads lighter than its surroundings, like the reference's frosted panel. |
| Shadows and dim | Window shadow at 20%; `::backdrop` and scrim 32% | 35%; 45% |
| Opaque twins | `#0A3560` / `#282B4F` / `#222442` | `#0E1B3F` / `#251E3B` / `#1E1932` |
| Identical in both | White ink, secondary 0.84, lime, white pills, on-glass tints, radii, type, motion | |

visionOS has one appearance, and Planly follows it. **The ink never flips.** Theme changes the *time of day of the environment*, and each theme's glass alpha keeps the same AA guarantees. `color-scheme: dark` is set in both themes, so scrollbars, date pickers and form controls stay light-on-dark.

---

## 12. Accessibility and fallbacks

- **`prefers-reduced-transparency: reduce`**
  - Every tier switches to its `--solid-*` twin with no `backdrop-filter`. The environment stays visible around the panels; platters stay as fills.
  - Contrast rises to at least 12.4:1 for labels.
  - Supported in Chromium. Safari does not expose this preference, but its contrast still passes without it.
- **`prefers-contrast: more`**
  - Solid panels.
  - The environment is dimmed by a 35% navy overlay, which lifts display text to ≥ 7.75:1 (Day).
  - Reeds are off and the tint wash is 0%.
  - Secondary 0.92, tertiary 0.80, hairlines 1 px at 40%, checkbox ring white.
  - The selected lozenge becomes solid white with ink text.
  - Display weight becomes 400.
- **`forced-colors: active`**
  - The environment is hidden.
  - Glass becomes `Canvas` with a `CanvasText` border.
  - Add `forced-color-adjust: auto` defaults. Lime signals (now-line, today dot) fall back to `Highlight` via `@media (forced-colors: active) { .now-line .rule, .day[data-today] .dot { background: Highlight; } }`.
  - The checkbox fill falls back to `Highlight`.
- **No `backdrop-filter` support** (`@supports not`): solid twins.
- **`prefers-reduced-motion`**: see §10.
- **Focus.**
  - A 2 px lime outline with a 2 px offset (≥ 4.63:1 on the top band, ≥ 6.13:1 on glass), following border radius.
  - The composer and fields use an inset ring plus a lime halo.
  - No focusable element sits on the bare environment outside the top band (L10).
- **Hit targets.**
  - 44 px through `::after` on every icon button and ornament.
  - The phone week-day buttons stay 32–34 px wide × 48 px tall. This is a pre-existing compromise; it is mitigated by 2 px gaps and swipe-free selection.
- **Zoom.** All sizes are in `rem`. The environment depends only on the viewport, and windows reflow at 200%.
- **Screen readers.** The ruler, lozenge, dots and duration-pill icon are `aria-hidden`. Duration and type are already in the card's `aria-label`; add "high priority" to it.

---

## 13. Performance

| Layer | `backdrop-filter` | Typically visible |
|---|---|---|
| Environment | none (gradients only, `contain: strict`, never repainted on scroll) | 1 |
| `.toolbar::before` scroll edge | blur 16 px | 1 |
| Toolbar ornaments (week capsule, History, Today, agent) | **none** (fill-only over the edge layer) | 3–4 |
| Day window | blur 28 px | 1 |
| Widgets | blur 28 px | 2–4 |
| Agent window | blur 28 px | 1 |
| Sheet or drawer | blur 40 px | 0–1 |
| Popover, toasts | blur 40 px | 0–2 |
| Platters, cards, rows, bubbles, chips, fields, pills | **none** | many |

- **Budget.** At most 7 simultaneous blurs, never nested. A parallel perf harness in this session measured 30 blurred cards scrolling over a fixed backdrop: p50 frame time rose from 16.7 ms to 33 ms. That run was headless Chromium with software raster at DPR 2 , so treat it as relative, not absolute. Per-card glass is therefore out.
- **Backdrop-root pitfalls.** None of these may appear on **any ancestor of a glass element** (`.app`, `.main-column`, `.content`, `.checklist`, `.widgets`, `.inspector`, `.timeline`'s parent): `opacity < 1`, `filter`, `mask` / `mask-image`, `clip-path`, `mix-blend-mode`, `backdrop-filter`, `will-change: opacity | filter`. Any of them silently cuts the environment out of every glass child.
  - `transform` is fine, so the drawer and Motion's layout animations are safe.
  - Opacity on the glass element *itself* (Motion's fade-in) is fine.
  - The `.chat-scroll` mask is fine because nothing inside it blurs.
- **Never animate `backdrop-filter` values or the environment.** Moving glass over a static backdrop re-blurs only that element. Moving the backdrop re-blurs all of them on every frame.
- **Avoid `background-attachment: fixed`** for faked glass. iOS ignores it and Chromium repaints on scroll.
- **Text on translucent layers** loses LCD sub-pixel anti-aliasing. `-webkit-font-smoothing: antialiased` is already set, so this is consistent.
- **`will-change: transform`** is allowed only on `.inspector` while the drawer animates.
- **Optional safety valve.** Add `<html data-glass="lite">`, which applies the opaque twins, when a 2 s scroll probe shows p95 > 24 ms or `navigator.hardwareConcurrency <= 4`. It is not required for v1.

---

## 14. Risks and trade-offs

1. **"Light mode" is not paper-white.** Both appearances are white-on-glass, following visionOS. Users who expect black-on-white get a bright daytime environment instead. Opaque modes cover accessibility; a "Paper" theme could come later.
2. **Less luminous than the reference.** The white-hot peach core is capped at coral (L ≤ 0.21), and the glass is smoked (α 0.50–0.66) rather than the reference's milky α ≈ 0.3. This is the cost of AA, since the reference itself fails (about 2.9:1 on its cards).
3. **GPU cost** on low-end and Linux machines without GPU raster. The blur budget and opaque twins mitigate it; the `data-glass="lite"` valve is available if needed.
4. **The contrast model is an approximation.** It assumes sRGB compositing and a luminance-neutral `saturate()`. The thinnest margins are task meta on a yellow-washed platter (4.79 Day / 4.87 Night) and the selected lozenge (4.74). Verify on real screenshots with pixel sampling or axe in the e2e run, and treat `tools/final2.py` as a gate when tokens change.
5. **Art direction is load-bearing.** Moving the warm core or brightening a stop can break L1 and L2 silently. Keep the environment in tokens only, and never take user wallpapers without a per-image luminance check.
6. **Code changes beyond CSS:**
   - Popover portal and outside-click logic
   - TaskCard markup (size, `when` row, ruler, progress)
   - WeekStrip lozenge
   - the TaskSheet time card
   - Import tab icons
   - the environment DOM

   The popover change is the riskiest; cover it with e2e tests for the Move menu in a widget and in a sheet.
7. **Semantic shift:** green → lime for on / online / done-step, blue → white for interaction. Update `docs/UI_SPEC.md` (colour meanings, components, motion) and regenerate `docs/screenshots/*` through `frontend/e2e/smoke.spec.ts`.
8. **Safari** has no `prefers-reduced-transparency`. Firefox needs a backdrop-filter version of 103 or later (fine).
9. **Ruler semantics.** Fixed-pitch ticks are decorative; only the lime elapsed fill carries meaning, and it is duplicated by the now-line. Some users may read tick count as duration; tooltips are not needed.
10. **Phone toolbar density.** Seven days plus three 36 px buttons fill a 390 px width exactly. Localised narrow weekday labels wider than one glyph would overflow, so test with `de` and `ja`.

---

## 15. Implementation order and checklist

1. **`tokens.css`** (§4). The app becomes legible on the new colours immediately.
2. **`base.css`** (§5, §9.7). Environment, glass tiers, ornament, scroll edge, buttons, fields, switch, tab row, focus, selection.
3. **`App.tsx` and `app.css`** (§9.1–9.3). Environment DOM, toolbar classes, floating inspector, drawer, phone rules, `index.html` metas.
4. **Timeline** (§9.4). `TaskCard` markup, ruler, progress, now-line, free gaps, window.
5. **Checklist** (§9.5) and the checkbox.
6. **Chat** (§9.6).
7. **Sheets, popovers (portal), toasts** (§9.8–9.10).
8. **Docs.** `UI_SPEC.md`, screenshots, and a note in `apple-design` usage about the glass-content exception (§2).

**Verify:**

- Day, Night, 390 px phone and the 1080 px drawer.
- Reduced transparency, increased contrast and forced colours (DevTools rendering emulation).
- 200% zoom.
- Keyboard-only pass (focus is always visible).
- axe contrast pass on e2e screenshots.
- Pixel-sample the darkest and lightest points under `.timeline` and `.widget`, and re-check §6.
- Scroll the checklist at DPR 2 with ≤ 7 blurs visible and keep p95 under 20 ms on target hardware.
- Open the Move menu from a widget and from the task sheet: the menu is not clipped and the blur is visible.
