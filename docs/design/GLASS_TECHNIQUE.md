# Reeded-glass rendering technique (research + prototype)

Target: the reference `images/4.webp`, with a motion-blurred photographic gradient, vertical reeded glass over the whole page, frosted panels on top, and ruler ticks on cards. The app is React + Vite with plain CSS. Safari on a MacBook Air (M-series, 2x DPR) comes first; Chrome must also work.

**Prototype:** `proto/index.html` (self-contained, no JS needed, `?theme=dark` for night).
**Screenshots:** `proto/shot.png` (day, 1440x900), `shot-dark.png`, `shot-reduced-transparency.png`, `shot-contrast-more.png`.
**Side-by-side:** `compare.png` (reference on top, render below) · `reed-variants.png` (no reeds / recommended / SVG displacement).
**Perf harness:** `proto/perf.html?v=<variant>` + `tools/perf.cjs`; raw results are in `proto/perf-*.json` / `perf-final.txt`.

> Note: another agent briefly wrote its own app prototype into `proto/` during this work. It now lives in `spec-proto/`, a separate deliverable. Everything in `proto/` is this technique prototype.

---

## TL;DR — the recipe

| Layer | Technique | Cost profile |
|---|---|---|
| Backdrop painting | One `position: fixed` layer. The painting is a stack of `radial-gradient`s in one custom property plus two silhouette shapes. It is blurred **anisotropically**: painted at 1/k width, `filter: blur()`, then `scaleX(k)`. | Rasterised once and composited after that. **0 main-thread paints while scrolling** (measured). |
| Reeded glass | (a) **Refraction:** a second copy of the painting shifted by about 8px, shown through a saw-tooth `mask-image` with one ramp per rib. (b) **Rib lighting:** a `repeating-linear-gradient` of dark and light bands at normal alpha, with **no `mix-blend-mode`**. | Static, inside the same fixed layer. **No measurable scroll cost** (`full` vs `nobg` within noise). |
| Frosted panels | `backdrop-filter: blur() saturate()` in 3 tiers, written with **literal values** and always with the `-webkit-` twin. Bright top edge via `inset 0 1px 0`. Nested cards use plain translucent fills. | The only real per-frame cost. Budget **≤ 6 blurred surfaces visible at once.** |
| Ruler ticks | Three stacked `repeating-linear-gradient`s (every 4px, 20px, 40px) at different heights, plus one fade mask. | Free (static raster). |
| Ambient drift | **Don't.** It forces re-blurring of the backdrop *and* every glass surface on every frame (measured about 3x worse than static). | Expensive. |

---

## 1. The vivid backdrop (no photo)

**Options evaluated**

| Option | Look | Safari | Cost | Verdict |
|---|---|---|---|---|
| Layered `radial-gradient`s only | Smooth but "geometric": perfect ellipses, no motion | ✅ | Cheapest | Not painterly enough on its own |
| Gradients + isotropic `filter: blur()` | Softer blobs, still no direction | ✅ (`filter` is GPU/Core Animation) | One-time raster | OK |
| **Gradients + shapes + anisotropic blur (scaleX trick) + streaks** | Horizontal motion smear, crisp-ish vertical edges, streaks. Matches the reference. | ✅ only `filter: blur`, `transform`, `clip-path`, `mask-image` | One-time raster (a 1/8-width source is even cheaper to blur) | **Recommended** |
| SVG `feTurbulence`/`feGaussianBlur stdDeviation="x y"` | Native anisotropic blur, grain | SVG-as-image works; SVG filters on HTML are software-rendered in WebKit | One-time, but slower first paint and every resize | Fine as a static image; not needed |
| CSS "mesh gradient" (conic/radial grids) | Too clean and digital | ✅ | Cheap | Doesn't read as a photo |

**Why the scaleX trick:** CSS `blur()` is isotropic. A filter runs in the element's *local* space, so you paint the layer at `width: 100%/k`, blur it by `v`, and stretch it back with `transform: scaleX(k)`. The result has `k*v` px of horizontal blur and `v` px of vertical blur, which is a motion blur, using only a GPU-friendly `blur()`. Percent-based gradient positions and sizes map straight back to viewport percentages. With `k: 8; v: 4.5px` you get 36px horizontal and 4.5px vertical. Low vertical blur keeps the thin horizontal **streak lines** (three co-prime `repeating-linear-gradient`s, masked to the subject) visible. Those streaks are what make it read as "photo, motion-blurred" rather than "gradient".

**Light and dark:** every colour is a token (`--c-*`), and the night variant only swaps tokens (`:root[data-theme="dark"]`, or wrap the same block in `@media (prefers-color-scheme: dark)`). Text stays white in both, because the day palette is mid-tone vivid, not pastel.

**Ambient drift:** not worth it. A slow `transform` drift on the painting (40s, compositor-only) still invalidates the *input* of every `backdrop-filter` above it. Every visible glass surface then re-blurs every frame, even when nothing scrolls, and the filtered painting re-blurs too. Measured in Chromium: mean frame **88 ms with drift vs 31 ms static**, and **20.6 s vs 5.4 s** of compositor draw time over a 4 s scroll. On an M-series GPU it won't be that slow, but it costs battery permanently for an effect almost nobody notices behind frosted panels. If you want life, use a one-shot 600 ms cross-fade when the theme or day changes. If you insist on drift: only on a hero with ≤ 2 glass surfaces, ≥ 60 s period, paused via `document.hidden` and `prefers-reduced-motion`.

## 2. Reeded / fluted glass over the whole page

**What the reference actually does (measured):** I folded the column-luminance profile of the reference. The rib period is **≈ 24 px at 1440 CSS px** (18.2 px in the 1103 px-wide image), so a bit wider than the 10–14 px guess; `--reed` is one token, so tune it. Each rib is a soft dark band right after the edge (about 25% of the width), a slow recovery, then a thin bright line just before the next edge. The amplitude is small (±2–6 levels out of 255). Most of the visual signal comes from **colours stepping at rib edges** (refraction), not from the light/dark lines.

| Option | Fidelity | Safari | Cost | Verdict |
|---|---|---|---|---|
| Fixed overlay of `repeating-linear-gradient` ribs + `mix-blend-mode: overlay/soft-light` | Gives ridge lines, no colour displacement | ⚠️ WebKit bug 250828: blend modes on **fixed** layers drop out when the layer switches tiled/non-tiled (large windows, ~1800 px+). Blend modes on fixed or sticky layers are also a known scroll-jank source. | Composite-time blend per frame | Avoid the blend; keep the ribs |
| `backdrop-filter` on a striped `mask-image` overlay | Poor: blurring an already-blurred backdrop barely changes it, so no ridges | ✅ with `-webkit-` | Adds a **full-viewport backdrop surface**, the most expensive primitive on the page | Reject |
| `backdrop-filter: url(#feDisplacementMap)` | True refraction | ❌ **Not in Safari**. WebKit: accelerated filters, including backdrop-filter, can't use SVG filters (bug 245510, still open; a patch is in progress, not shipped). Chrome only. | GPU | Reject (Safari is primary) |
| `filter: url(#feDisplacementMap)` on **our own** backdrop element (not backdrop-filter) | True displaced edges (sawtooth steps at the head outline); needs a separate lighting layer. Showed a top-edge artifact until the y-channel is neutralised. | Supported, but WebKit runs SVG filters on HTML in software. Not verified here (Playwright WebKit couldn't be downloaded in this sandbox). | Static, so 0 scroll cost in Chromium (measured); slower first paint and every resize | Optional enhancement only |
| **Refraction cross-fade + rib lighting (normal alpha)** | Each rib shows an offset, compressed slice with a step at its edge, plus the light/dark ridge. Visually matches the reference (`reed-variants.png`: none / recommended / SVG). | ✅ only `mask-image` (+`-webkit-`), `transform`, gradients | Static; measured **no extra scroll cost** | **Recommended** |

**Why the cross-fade works:** a cylindrical lens array displaces the image roughly linearly across each rib and jumps at the boundary, a saw-tooth. With a second copy of the painting shifted by `s`, revealed through a mask whose alpha ramps 0→1 across each rib, each pixel shows `(1-a)·P(x) + a·P(x+s)`. For a heavily blurred P, that is approximately `P(x + a·s)`, the same saw-tooth displacement. No SVG filter is needed, and it's identical in Safari and Chrome. Keep `--reed-shift` at about 1/3 of `--reed`. At 26px it turns into venetian blinds and the silhouette stops reading.

The ribs live **inside the fixed backdrop layer, under the glass**. So glass panels blur the ribs away, exactly like the reference, where cards show no ribs.

## 3. Frosted glass panels

**Tier values** (calibrated by sampling the reference's panel, card and nav colours against the render):

| Tier | Use | backdrop-filter | Fill (day) | Edge |
|---|---|---|---|---|
| thin | nav pill, icon buttons | `blur(18px)` | `rgba(235,245,250,.16)` | top `inset 0 1px 0 rgba(255,255,255,.30)` + hairline `.07` |
| regular | cards, sheets | `blur(24px) saturate(130%)` | `rgba(70,150,180,.22)` | same + drop shadow `0 24px 60px -12px rgba(4,30,70,.30)` |
| thick | big floating panel | `blur(40px) saturate(105%)` | `rgba(70,150,180,.22)` | top edge `.22` |
| inner (no blur) | cards *inside* a glass panel | **none** | `rgba(255,255,255,.075)` | `inset 0 1px 0 rgba(255,255,255,.16)` |

The reference's glass is *desaturated* teal, so keep `saturate()` low (100–130%). The usual `saturate(180%)` Apple-style value turns it neon over this backdrop.

**Bright top edge:** `box-shadow: inset 0 1px 0 0 rgba(255,255,255,.3), inset 0 0 0 1px rgba(255,255,255,.07)`. It costs nothing and follows `border-radius`. Avoid `border-image` (ignores radius) and gradient borders via `mask-composite` (an extra mask layer per panel, plus Safari prefix mismatches).

**How many blurred layers:** cost scales with *visible blurred area × radius*, recomputed on every frame where anything beneath changes, and scrolling always counts. In the harness (30 cards in a 3-column grid, scrolled 12 px/frame):
- ≈ 6 visible blurred surfaces held 60 fps even with **software** GL.
- ≈ 8 visible started dropping frames.
- ≈ 16 visible fell to 30 fps.
- Cutting the blur radius from 24px to 16px recovered about 20%.

Budget: **≤ 6 simultaneously visible `backdrop-filter` surfaces.** Lists of items go *inside* one glass container as `.glass-inner` fills. Never nest `backdrop-filter`. Per the spec's Backdrop Root, a blurred parent makes the child see only the parent, which wastes work and looks wrong.

**Scroll repaints:** a `position: fixed` backdrop layer is composited, so scrolling causes **0 main-thread `Paint` events** (Chromium trace, all static variants). The re-blur of glass happens in the compositor, on the GPU. The anti-pattern is `background-attachment: fixed`. Chrome repaints it on the main thread every scroll frame: measured **256 Paint events and 4,185 raster tasks (11.7 s of raster) in 4 s**, versus 0 Paint events and 108 raster tasks for the fixed layer. iOS Safari ignores it entirely. Rules:
- The backdrop is a sibling at the root (`<Backdrop/>` before `<App/>`), `position: fixed; inset: 0; z-index: -1; contain: strict; isolation: isolate`. `contain: strict` stops anything inside invalidating page layout. `will-change` is unnecessary: fixed is already composited, and an extra layer hint only costs memory.
- **Never** put `transform`, `filter`, `opacity < 1`, `mask`, `mix-blend-mode`, or `will-change: transform/opacity` on an *ancestor* of glass, including route-transition wrappers. That creates a Backdrop Root, so the glass can't see the backdrop and goes flat. It also turns `position: fixed` into "fixed to that ancestor". Animate the glass element itself instead.
- Inner scroll containers (`overflow: auto` panes) are fine; keep the blurred surfaces as few as above.

## 4. Ruler ticks

```css
.ruler {
  --tick: rgba(255, 255, 255, .55);
  --step: 4px;                                  /* fine tick spacing */
  height: 30px;
  background:
    repeating-linear-gradient(90deg, var(--tick) 0 1px, transparent 1px calc(var(--step) * 10)) 0 100% / 100% 26px no-repeat, /* major */
    repeating-linear-gradient(90deg, var(--tick) 0 1px, transparent 1px calc(var(--step) * 5))  0 100% / 100% 19px no-repeat, /* mid   */
    repeating-linear-gradient(90deg, var(--tick) 0 1px, transparent 1px var(--step))            0 100% / 100% 14px no-repeat; /* fine  */
  -webkit-mask-image: linear-gradient(to top, #000 35%, transparent);
          mask-image: linear-gradient(to top, #000 35%, transparent);
  opacity: .6;
}
```
Each layer's `background-size` height sets the tick length, and `background-position: 0 100%` bottom-aligns it. Majors overlap the fine ticks, so they come out slightly brighter for free. To mark a time range, overlay one more `linear-gradient` with the range colour clipped by `background-size`/`background-position` in %. Use one mask layer only; see the Safari notes on `mask-composite`.

## 5. Fallbacks

```css
@supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
  .glass { background: color-mix(in srgb, var(--bg-base) 70%, white 12%); }
}
/* Safari does NOT expose prefers-reduced-transparency (Chrome 118+ does), so mirror it with an app setting. */
@media (prefers-reduced-transparency: reduce) {
  :root:not([data-transparency="full"]) .bg__refract,
  :root:not([data-transparency="full"]) .bg__reeds { display: none; }
  :root:not([data-transparency="full"]) .glass { -webkit-backdrop-filter: none; backdrop-filter: none; background: color-mix(in srgb, var(--bg-base) 82%, white); }
}
:root[data-transparency="reduced"] .bg__refract,
:root[data-transparency="reduced"] .bg__reeds { display: none; }
:root[data-transparency="reduced"] .glass { -webkit-backdrop-filter: none; backdrop-filter: none; background: color-mix(in srgb, var(--bg-base) 82%, white); }

@media (prefers-contrast: more) {               /* Safari 14.1+, Chrome 96+; maps to macOS "Increase contrast" */
  .bg__refract, .bg__reeds { display: none; }
  .bg::after { content: ""; position: absolute; inset: 0; background: rgba(0, 12, 35, .45); }
  .glass { -webkit-backdrop-filter: none; backdrop-filter: none; background: rgba(8, 30, 70, .92); box-shadow: inset 0 0 0 1.5px #fff; }
  .glass-inner { background: rgba(255,255,255,.08); box-shadow: inset 0 0 0 1px rgba(255,255,255,.6); }
  :root { --ink-2: #fff; --ink-3: rgba(255,255,255,.88); }
}
@media (prefers-reduced-motion: reduce) {        /* backdrop is static by default; kills an opt-in drift */
  .bg__paint { animation: none !important; }
}
```
Both media modes were rendered via CDP emulation (`shot-reduced-transparency.png`, `shot-contrast-more.png`).

---

## Final CSS (copy-paste)

### Tokens
```css
:root {
  --reed: 24px;              /* rib period (reference ≈ 24px @1440) */
  --reed-shift: 8px;         /* refraction strength, keep ≈ reed/3 */
  --k: 8;                    /* motion-blur anisotropy */
  --blur-v: 4.5px;           /* vertical blur → 36px horizontal */

  /* day palette (sampled from the reference) */
  --c-edge: #0d659b; --c-base: #037fb6; --c-base-2: #3f9fc3; --c-right: #63a8c0;
  --c-sky: #0fa2d3; --c-mist: #72a8b8; --c-figure: #13235e; --c-figure-2: #193a78;
  --c-plum: #6c1f5e; --c-magenta: #e4427a; --c-peach: #ee948f; --c-peach-hi: #f8c3b4;
  --c-coral: #e2919b; --c-lav: #a088b6; --c-lilac: #c79bc2; --c-orchid: #b8459c; --c-warm: #d4bdba;
  --bg-base: var(--c-base);
  --streak-lite: rgba(255, 210, 225, .45);
  --streak-dark: rgba(30, 40, 120, .30);

  --glass-tint: rgba(70, 150, 180, .22);
  --glass-tint-thin: rgba(235, 245, 250, .16);
  --glass-fill-inner: rgba(255, 255, 255, .075);
  --glass-edge: rgba(255, 255, 255, .30);
  --glass-hair: rgba(255, 255, 255, .07);
  --glass-shadow: 0 24px 60px -12px rgba(4, 30, 70, .30);
}
:root[data-theme="dark"] {     /* or @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { … } } */
  --c-edge: #050f2c; --c-base: #0a2558; --c-base-2: #11306a; --c-right: #1b3566;
  --c-sky: #123f86; --c-mist: #26406c; --c-figure: #030a20; --c-figure-2: #071737;
  --c-plum: #3a0c43; --c-magenta: #b3205f; --c-peach: #c86a63; --c-peach-hi: #e19a86;
  --c-coral: #a84a6c; --c-lav: #4c3a7c; --c-lilac: #6a4a8c; --c-orchid: #7a2275; --c-warm: #3f3460;
  --streak-lite: rgba(255, 160, 190, .16); --streak-dark: rgba(0, 0, 30, .30);
  --glass-tint: rgba(20, 40, 90, .30); --glass-tint-thin: rgba(30, 55, 110, .28);
  --glass-fill-inner: rgba(255, 255, 255, .07); --glass-edge: rgba(255, 255, 255, .26);
  --glass-hair: rgba(255, 255, 255, .10); --glass-shadow: 0 24px 60px -12px rgba(0, 0, 0, .55);
}
```

### Backdrop markup (React)
```tsx
// Render once at the root, as a sibling BEFORE the app. Never inside a transformed/filtered/faded wrapper.
const Paint = () => (
  <div className="bg__paint"><i className="bg__body" /><i className="bg__head" /><i className="bg__streaks" /></div>
);
export const Backdrop = () => (
  <div className="bg" aria-hidden="true">
    <Paint />
    <div className="bg__refract"><Paint /></div>
    <div className="bg__reeds" />
  </div>
);
```

### Backdrop + reeds CSS
```css
:root {
  --base: linear-gradient(90deg, var(--c-edge) 0%, var(--c-base) 7%, var(--c-base) 45%, var(--c-base-2) 75%, var(--c-right) 100%);
  --paint:
    /* horizontal arm / motion streaks */
    radial-gradient(ellipse 13% 2% at 41% 18.5%, color-mix(in oklab, var(--c-coral) 75%, white) 0 30%, transparent 100%),
    radial-gradient(ellipse 10% 1.6% at 44% 23.5%, var(--c-coral) 0 30%, transparent 100%),
    radial-gradient(ellipse 13% 1.8% at 37% 13.5%, var(--c-lav) 0 30%, transparent 100%),
    radial-gradient(ellipse 11% 1.5% at 30% 27%, var(--c-lav) 0 25%, transparent 100%),
    /* plum fold + magenta core */
    radial-gradient(ellipse 5% 18% at 55% 60%, var(--c-plum) 0 45%, transparent 100%),
    radial-gradient(ellipse 6.5% 20% at 48.5% 66%, var(--c-magenta) 0 50%, transparent 100%),
    radial-gradient(ellipse 5% 9% at 42% 82%, var(--c-magenta) 0 35%, transparent 100%),
    /* peach body glow */
    radial-gradient(ellipse 8% 14% at 42% 69%, var(--c-peach-hi) 0 35%, transparent 100%),
    radial-gradient(ellipse 15% 34% at 40% 52%, var(--c-peach) 0 55%, transparent 100%),
    radial-gradient(ellipse 14% 16% at 46% 30%, var(--c-coral) 0 45%, transparent 100%),
    radial-gradient(ellipse 20% 11% at 38% 19%, var(--c-lav) 0 35%, transparent 100%),
    /* lilac / orchid lower left */
    radial-gradient(ellipse 18% 18% at 28% 76%, var(--c-lilac) 0 45%, transparent 100%),
    radial-gradient(ellipse 7% 10% at 24% 91%, var(--c-orchid) 0 40%, transparent 100%),
    radial-gradient(ellipse 13% 13% at 68% 90%, var(--c-lav) 0 30%, transparent 100%),
    /* warm haze bottom right, mist right side, sky band */
    radial-gradient(ellipse 36% 26% at 92% 100%, var(--c-warm) 0 35%, transparent 100%),
    radial-gradient(ellipse 30% 70% at 90% 45%, var(--c-mist) 0 40%, transparent 100%),
    radial-gradient(ellipse 55% 25% at 40% 0%, var(--c-sky) 0 30%, transparent 100%),
    var(--base);
}

.bg {
  position: fixed; inset: 0; z-index: -1;
  overflow: hidden; contain: strict; isolation: isolate; pointer-events: none;
  background: var(--base);           /* same as the paint's base, so blur edge fall-off is invisible */
}
/* painted at 1/k width, blurred, stretched back: anisotropic (motion) blur */
.bg__paint {
  position: absolute; top: 0; bottom: 0; left: 0;
  width: calc(100% / var(--k));
  transform-origin: 0 0; transform: scaleX(var(--k));
  background: var(--paint);
  filter: blur(var(--blur-v));
}
/* refraction: shifted copy through a saw-tooth mask (one 0→1 ramp per rib) */
.bg__refract {
  position: absolute; inset: 0;
  -webkit-mask-image: repeating-linear-gradient(90deg, transparent 0, #000 var(--reed));
          mask-image: repeating-linear-gradient(90deg, transparent 0, #000 var(--reed));
}
.bg__refract > .bg__paint { transform: translateX(var(--reed-shift)) scaleX(var(--k)); }

/* blurred silhouette (percent coords = viewport %, because the layer is scaled back) */
.bg__head, .bg__body { position: absolute; display: block; }
.bg__head { left: 56.2%; top: 8%; width: 8%; height: 16%; border-radius: 50%; background: var(--c-figure); }
.bg__body {
  inset: 0;
  background: linear-gradient(180deg, var(--c-figure) 25%, var(--c-figure-2) 55%, color-mix(in oklab, var(--c-figure-2) 55%, var(--c-plum)) 75%);
  clip-path: polygon(58% 22%, 62.5% 22%, 67% 25.5%, 70% 30%, 71.5% 37%, 71% 49%, 69.5% 61%, 67% 71%, 61% 74%, 57.5% 66%, 55.5% 53%, 54% 42%, 53.5% 34%, 55.5% 27%);
}
/* motion streaks: co-prime periods, masked to the subject; smeared horizontally by the parent's blur */
.bg__streaks {
  position: absolute; inset: 0;
  background:
    repeating-linear-gradient(180deg, transparent 0 10px, var(--streak-lite) 10px 14px, transparent 14px 29px),
    repeating-linear-gradient(180deg, transparent 0 5px,  var(--streak-lite) 5px 8px,   transparent 8px 19px),
    repeating-linear-gradient(180deg, transparent 0 14px, var(--streak-dark) 14px 19px, transparent 19px 37px);
  -webkit-mask-image:
    radial-gradient(ellipse 15% 15% at 42% 23%, #000 15%, transparent 100%),
    radial-gradient(ellipse 8% 18% at 70% 42%, rgba(0,0,0,.4) 10%, transparent 100%),
    radial-gradient(ellipse 14% 10% at 48% 84%, #000 10%, transparent 100%);
          mask-image:
    radial-gradient(ellipse 15% 15% at 42% 23%, #000 15%, transparent 100%),
    radial-gradient(ellipse 8% 18% at 70% 42%, rgba(0,0,0,.4) 10%, transparent 100%),
    radial-gradient(ellipse 14% 10% at 48% 84%, #000 10%, transparent 100%);
}
/* rib lighting: dark band after each edge, thin highlight before the next (normal alpha, no blend mode) */
.bg__reeds {
  position: absolute; inset: 0;
  background: repeating-linear-gradient(90deg,
    rgba(0, 25, 70, .045) 0,
    rgba(0, 25, 70, .03) calc(var(--reed) * .2),
    rgba(0, 25, 70, 0)   calc(var(--reed) * .45),
    rgba(255, 255, 255, .015) calc(var(--reed) * .7),
    rgba(255, 255, 255, .05) calc(var(--reed) * .9),
    rgba(255, 255, 255, .08) calc(var(--reed) - 1.5px),
    rgba(0, 25, 70, .045) var(--reed));
}
```

### Glass tiers
```css
/* LITERAL values on purpose: Safari 18.x can drop -webkit-backdrop-filter whose value contains var() (WebKit 289149 / 297620). */
.glass {                                   /* regular: cards, sheets */
  background: var(--glass-tint);
  -webkit-backdrop-filter: blur(24px) saturate(130%);
          backdrop-filter: blur(24px) saturate(130%);
  box-shadow: inset 0 1px 0 0 var(--glass-edge), inset 0 0 0 1px var(--glass-hair), var(--glass-shadow);
}
.glass--thin {                             /* nav pill, icon buttons */
  background: var(--glass-tint-thin);
  -webkit-backdrop-filter: blur(18px);
          backdrop-filter: blur(18px);
  box-shadow: inset 0 1px 0 0 var(--glass-edge), inset 0 0 0 1px var(--glass-hair);
}
.glass--thick {                            /* big floating panel */
  --glass-edge: rgba(255, 255, 255, .22);
  -webkit-backdrop-filter: blur(40px) saturate(105%);
          backdrop-filter: blur(40px) saturate(105%);
}
.glass-inner {                             /* nested: never re-blur */
  background: var(--glass-fill-inner);
  box-shadow: inset 0 1px 0 0 rgba(255,255,255,.16), inset 0 0 0 1px rgba(255,255,255,.05);
}
```
The ruler and fallbacks CSS are in sections 4 and 5 above.

---

## Safari notes (consolidated)

1. **`backdrop-filter`**: always ship `-webkit-backdrop-filter` *and* `backdrop-filter`. Safari 18 release notes list unprefixed support, but reports show it gated or broken on some builds (e.g. 18.6 on Sonoma).
2. **No `var()` inside `-webkit-backdrop-filter`.** WebKit bug 289149 (Safari 18.2+ / iOS 18) and bug 297620 (Sonoma) describe the value being dropped. Use literal per-tier classes, as above.
3. **No SVG filters in `backdrop-filter`** (bug 245510): accelerated filters can't use SVG filters. Chrome supports it, Safari doesn't, so no liquid-glass refraction via backdrop. Refraction has to be baked into *our own* backdrop layer, which is what the cross-fade does.
4. **No `mix-blend-mode` on fixed layers** (bug 250828: the blend drops when the layer flips tiled/non-tiled on large windows). Use normal-alpha overlays.
5. **Masks:** unprefixed `mask-*` has been in Safari since 15.4. Still ship `-webkit-mask-image`, and avoid mixing `-webkit-mask-composite` with `mask-composite` (regression history), so use one mask layer per element.
6. **Backdrop Root:** `filter`, `opacity`, `mask`, `mix-blend-mode` and `will-change` on an ancestor cut glass off from the backdrop. Watch for page-transition wrappers.
7. **`prefers-reduced-transparency` is not supported in Safari.** It is limited availability: Chrome/Edge 118+ only. Provide an in-app toggle that sets `data-transparency="reduced"`. `prefers-contrast` and `prefers-reduced-motion` are supported.
8. WebKit composites `backdrop-filter` through Core Animation backdrop layers on the GPU. The per-surface cost is much lower than in the software numbers below, but it scales the same way (count × area × radius). The ≤ 6-surface budget is the safe reading.

Not verified on real Safari: Playwright's WebKit build couldn't be downloaded in this sandbox (CDN blocked). All Safari statements come from WebKit bugs and release notes, and the recipe deliberately uses only primitives Safari has shipped for years. **Check on the Mac:** open `proto/index.html` in Safari and confirm the ribs, refraction and glass. Then scroll `perf.html?v=full` with the Timelines tab open.

## Perf findings (Chromium headless, software GL / SwiftShader, 1440x900 @2x, rAF vsync-locked at 60 Hz)

240 rAF frames, `scrollBy(0,12)` per frame, 30-card page (`perf.html`). Chromium trace for main-thread `Paint` / `RasterTask` and viz draw time. Final run in `proto/perf-final.txt`; earlier runs agreed within ±2 ms mean.

| Variant (`?v=`) | What | Glass visible | Mean frame | p95 | Frames > 20 ms | Main-thread Paint events (scroll) | Raster during scroll | Viz draw (4 s) |
|---|---|---|---|---|---|---|---|---|
| `noglass` | backdrop + reeds, cards as plain fills | 1 (nav) | **16.7 ms** | 16.8 | 0 / 238 | 0 | 47 ms | 0.36 s |
| `every3` | 1 glass card per row | ≈ 5–6 | **16.7 ms** | 16.7 | 0 | 0 | 58 ms | 1.86 s |
| `every2` | every other card glass | ≈ 8 | 19.1 ms | 33.3 | 33 | 0 | 62 ms | 2.62 s |
| `blur16` | all glass, 16px radius | ≈ 16 | 26.8 ms | 50 | 124 | 0 | 84 ms | 4.40 s |
| `full` | **recipe**: all 30 cards glass (24px) | ≈ 16 | 30.8 ms | 50 | 127 | 0 | 84 ms | 5.35 s |
| `nobg` | same, but no refraction copy / rib layer | ≈ 16 | 31.0 ms | 50 | 126 | 0 | 78 ms | 5.42 s |
| `svg` | reeds via `filter:url(#feDisplacementMap)` on backdrop | ≈ 16 | 26.8 ms | 50 | 123 | 0 | 77 ms | 4.43 s |
| `drift` | recipe + 40 s transform drift on the painting | ≈ 16 | **88.2 ms** | 100 | 233 | 0 | 83 ms | **20.6 s** |
| `attach` | backdrop as `background-attachment: fixed` (no layer) | ≈ 16 | 32.9 ms | 66.6 | 115 | **256** | **11.7 s** (4,185 tasks) | 4.49 s |

One-time load raster (whole page): 748 ms for `full` vs 435 ms for `nobg` in *software* raster. The second (refracted) copy of the painting roughly doubles the backdrop's one-time raster. That cost recurs on window resize, not on scroll. On GPU raster (Apple Silicon) it is a few ms.

**How to read this:** absolute numbers are pessimistic because there is no GPU in this sandbox, so every blur pass runs on the CPU. The *relative* findings are what carry over:
- The static backdrop (painting + refraction + ribs) causes **zero main-thread paints during scroll**, and its compositing cost is noise (`full` ≈ `nobg`). The reeded effect is effectively free.
- **The glass count is the only real lever.** No glass gives a flat 16.7 ms. About 5 visible glass surfaces stays at 60 fps. About 15 visible halves the frame rate. A smaller radius (16px) helps about 20%.
- **Drift is the most expensive thing tested.** It makes every frame a full re-blur of backdrop and glass.
- **`background-attachment: fixed`** moves the cost to the main thread: hundreds of repaints and about 11 s of raster per 4 s scroll.
- The SVG `feDisplacementMap` on the static backdrop has no scroll cost in Chromium, but it adds WebKit software-filter risk for no visible gain over the cross-fade.

## Sources
- WebKit bug 245510: backdrop-filter `url()` SVG filters unsupported. https://bugs.webkit.org/show_bug.cgi?id=245510 · related 297770: https://bugs.webkit.org/show_bug.cgi?id=297770
- WebKit bug 289149 / 297620: `-webkit-backdrop-filter` with custom properties not applied. https://bugs.webkit.org/show_bug.cgi?id=289149 · https://bugs.webkit.org/show_bug.cgi?id=297620
- WebKit bug 250828: `mix-blend-mode` on fixed/sticky layers lost on large windows. https://bugs.webkit.org/show_bug.cgi?id=250828
- WebKit bug 240324: Safari 15.4 unprefixed `mask`, `mask-composite` mismatch. https://bugs.webkit.org/show_bug.cgi?id=240324
- Safari 18 release notes (unprefixed backdrop-filter). https://developer.apple.com/documentation/safari-release-notes/safari-18-release-notes
- Chrome 118 `prefers-reduced-transparency`. https://developer.chrome.com/blog/css-prefers-reduced-transparency · availability: https://web-platform-dx.github.io/web-features-explorer/features/prefers-reduced-transparency
- Fluted glass via backdrop-filter + gradient mask (evaluated, rejected). https://www.shadcn.io/shaders/fluted-glass-shader
- W3C fxtf notes on backdrop-filter and composited scrolling. https://lists.w3.org/Archives/Public/public-fxtf-archive/2018Nov/0098.html
