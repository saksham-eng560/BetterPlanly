# Glass over an environment

## Context
The user asked for the app to look like a reference landing page: a vivid, motion-blurred blue/magenta/coral backdrop behind reeded glass, frosted panels with ruler ticks, huge light display type, a glass pill nav with a lime dot, and white pill buttons. They also wanted it to keep Apple's design language. The `apple-design` skill forbids material on content ("put material on chrome, never on content cards"), because per-card blur makes text contrast depend on whatever scrolls behind it.

## Decision
Follow visionOS rather than iOS-on-a-page:
- **One fixed, CSS-only environment.** The backdrop is drawn in CSS, with no photo and no `filter`. Its luminance is capped (Day ≤ 0.23, Night ≤ 0.20; the top band is darker), so the worst-case contrast is known.
- **Content lives in windows.** These use the `glass-regular` tier, and inside them content sits on flat platters with no blur. Three tiers exist (thin, regular, thick), and each one's alpha is the smallest value that passes WCAG AA over the lightest part of the environment.
- **Colour roles.** White is the interactive colour. Lime `#C6F432` only signals "now / today / live". Solid colours carry ink `#0B1020`.
- **Opaque twins.** Every tier has a solid twin, used for reduced transparency, increased contrast, forced colours and browsers without `backdrop-filter`. Since Safari doesn't expose `prefers-reduced-transparency`, the app also has its own switch for this.

The full spec is in [docs/design/GLASS_SPEC.md](../design/GLASS_SPEC.md), the CSS techniques and Safari notes are in [GLASS_TECHNIQUE.md](../design/GLASS_TECHNIQUE.md), and the ratios come from [docs/design/contrast](../design/contrast).

## Consequences
- **Blur budget.** At most 7 blurred surfaces at once, never nested. Cards, rows, bubbles and ornaments never blur. Popovers are portalled out of their glass ancestors, so they don't nest.
- **Fixed environment.** It is not user-customisable: changing a colour stop means re-running the contrast model.
- **Safari constraints.** `-webkit-backdrop-filter` takes literal values, never `var()`. Nothing that creates a backdrop root (`filter`, `opacity < 1`, `mix-blend-mode`, `will-change`) may sit on an ancestor of a glass surface.
- **Phone drawer.** On phones the full-screen agent drawer is near-solid, as an iOS full-screen sheet is, so it stays readable wherever a large blur is tiled or skipped.
