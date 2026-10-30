---
name: apple-design
description: Build web interfaces that look and feel like Apple software, following the Human Interface Guidelines (clarity, deference, depth). Use when designing or reviewing any frontend screen, component, design token, colour, typography, layout, material/blur surface, icon, or dark-mode treatment that should feel native to macOS/iOS. Pair with emil-design-eng for motion.
---

# Apple Design (for the web)

Make web UI feel like a first-party Apple app: quiet, content-first, precise. This skill covers **visual design, layout, and components**. For animation timing and interaction feel, also load `emil-design-eng`.

## Initial Response

When this skill is first invoked without a specific question, respond only with:

> Ready. I'll design to Apple's Human Interface Guidelines: clarity, deference, depth.

## The three principles

1. **Clarity.** Text is legible at every size, icons are precise, and every element has an obvious purpose. If something needs explaining, it is probably the wrong control.
2. **Deference.** The UI frames the content and never competes with it. Use few colours, thin separators, translucent chrome and plenty of space. The user's tasks are the hero; the app's own UI is not.
3. **Depth.** Layering and motion show hierarchy. Sheets slide over content, sidebars sit behind translucent material, and popovers float above. The user always knows where they are and how to get back.

When two choices conflict, pick the one that removes something.

## Typography

- **Font stack.** SF Pro is licensed only for Apple platforms, so never self-host or `@font-face` it. Use the system stack. It renders SF on Apple devices and falls back cleanly elsewhere:
  ```css
  --font-text: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", "Segoe UI", system-ui, sans-serif;
  --font-display: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Inter", system-ui, sans-serif;
  --font-mono: ui-monospace, "SF Mono", "JetBrains Mono", Menlo, monospace;
  --font-rounded: ui-rounded, "SF Pro Rounded", var(--font-text);
  ```
- **Type scale.** Use the iOS Dynamic Type "Large" defaults, in `rem` so browser zoom and user font settings scale everything:

  | Style        | Size / line height (px) | Weight   |
  |--------------|-------------------------|----------|
  | Large Title  | 34 / 41                 | 700      |
  | Title 1      | 28 / 34                 | 700      |
  | Title 2      | 22 / 28                 | 700      |
  | Title 3      | 20 / 25                 | 600      |
  | Headline     | 17 / 22                 | 600      |
  | Body         | 17 / 22                 | 400      |
  | Callout      | 16 / 21                 | 400      |
  | Subheadline  | 15 / 20                 | 400      |
  | Footnote     | 13 / 18                 | 400      |
  | Caption 1    | 12 / 16                 | 400      |
  | Caption 2    | 11 / 13                 | 400      |

  On dense desktop layouts, step down one level: 13px is the macOS body size.
- **Tracking.** Apple tightens large text and loosens small text. Use about `-0.022em` at 28px and above, `-0.01em` at 17–22px, `0` at 13–15px, and `+0.01em` at 11–12px.
- **Hierarchy comes from weight and colour, not size alone.** A Headline in `--label` above a Subheadline in `--label-secondary` beats three different font sizes.
- Use `font-variant-numeric: tabular-nums` for times, durations, counters and anything that updates.
- Never use all-caps body text. Small-caps-style section headers in a grouped list are fine: Footnote size, `--label-secondary`, uppercase, `+0.02em`.

## Colour

Use semantic tokens only. Components never contain raw hex values. Define every token for light and dark themes. The values below are Apple's system colours (light / dark).

```css
:root {
  /* tints */
  --blue: #007AFF;   --green: #34C759;  --indigo: #5856D6; --orange: #FF9500;
  --pink: #FF2D55;   --purple: #AF52DE; --red: #FF3B30;    --teal: #30B0C7;
  --yellow: #FFCC00; --mint: #00C7BE;   --cyan: #32ADE6;   --gray: #8E8E93;
  --accent: var(--blue);

  /* labels */
  --label: #000000;
  --label-secondary: rgba(60, 60, 67, 0.60);
  --label-tertiary: rgba(60, 60, 67, 0.30);
  --label-quaternary: rgba(60, 60, 67, 0.18);

  /* backgrounds */
  --bg: #FFFFFF;            --bg-secondary: #F2F2F7;        --bg-tertiary: #FFFFFF;
  --bg-grouped: #F2F2F7;    --bg-grouped-secondary: #FFFFFF; --bg-grouped-tertiary: #F2F2F7;

  /* fills (for controls, chips, track backgrounds) */
  --fill: rgba(120, 120, 128, 0.20);           --fill-secondary: rgba(120, 120, 128, 0.16);
  --fill-tertiary: rgba(118, 118, 128, 0.12);  --fill-quaternary: rgba(116, 116, 128, 0.08);

  /* separators */
  --separator: rgba(60, 60, 67, 0.29);  --separator-opaque: #C6C6C8;
}
@media (prefers-color-scheme: dark) {
  :root {
    --blue: #0A84FF;   --green: #30D158;  --indigo: #5E5CE6; --orange: #FF9F0A;
    --pink: #FF375F;   --purple: #BF5AF2; --red: #FF453A;    --teal: #40C8E0;
    --yellow: #FFD60A; --mint: #63E6E2;   --cyan: #64D2FF;   --gray: #8E8E93;

    --label: #FFFFFF;
    --label-secondary: rgba(235, 235, 245, 0.60);
    --label-tertiary: rgba(235, 235, 245, 0.30);
    --label-quaternary: rgba(235, 235, 245, 0.16);

    --bg: #000000;            --bg-secondary: #1C1C1E;         --bg-tertiary: #2C2C2E;
    --bg-grouped: #000000;    --bg-grouped-secondary: #1C1C1E;  --bg-grouped-tertiary: #2C2C2E;

    --fill: rgba(120, 120, 128, 0.36);           --fill-secondary: rgba(120, 120, 128, 0.32);
    --fill-tertiary: rgba(118, 118, 128, 0.24);  --fill-quaternary: rgba(118, 118, 128, 0.18);

    --separator: rgba(84, 84, 88, 0.60);  --separator-opaque: #38383A;
  }
}
```

Rules:
- **One accent colour per app.** Use it for interactive elements only: buttons, links, selection, the current-time indicator. Do not make decorative text blue.
- Category colours (for example, task types) take a tint at low opacity for the background (`color-mix(in srgb, var(--orange) 14%, transparent)`) and the full tint for a small glyph or edge. Never fill a large area with saturated colour.
- Dark mode is not inverted light mode. It uses pure black at the base, elevated surfaces get lighter (`--bg-secondary`, then `--bg-tertiary`), and tints shift to their brighter dark variants.
- Red means destructive or overdue. Green means done. Don't reuse them for anything else.

## Materials (translucency)

Chrome such as toolbars, sidebars, sheets, popovers and floating panels sits on translucent material, so content shows through softly behind it.

```css
.material-regular {
  background: color-mix(in srgb, var(--bg-secondary) 72%, transparent);
  backdrop-filter: saturate(180%) blur(24px);
  -webkit-backdrop-filter: saturate(180%) blur(24px);
}
.material-thin  { /* same, 55% and blur(16px) */ }
.material-thick { /* same, 88% and blur(32px) */ }

@media (prefers-reduced-transparency: reduce) {
  .material-regular, .material-thin, .material-thick {
    background: var(--bg-secondary); backdrop-filter: none; -webkit-backdrop-filter: none;
  }
}
```

- Put material on **chrome**, never on content cards. Content sits on opaque grouped backgrounds.
- Mark the edge where a material meets content with a hairline (`0.5px solid var(--separator)`; use `1px` on low-DPR screens) instead of a shadow.
- Floating surfaces (popovers, menus, toasts) get material and a soft layered shadow:
  `box-shadow: 0 0 0 0.5px var(--separator), 0 4px 12px rgba(0,0,0,.08), 0 16px 40px rgba(0,0,0,.12);`

## Shape

- **Continuous corners.** Apple uses squircle-like corners. On the web, use a slightly larger `border-radius` than feels natural, and add `corner-shape: squircle` as progressive enhancement.
- Radius tokens: `--r-xs: 6px` (chips, tags), `--r-sm: 8px` (buttons, inputs), `--r-md: 12px` (cards, list groups), `--r-lg: 16px` (panels), `--r-xl: 22px` (sheets, modals), `--r-full: 999px` (pills, avatars, circular checkboxes).
- **Concentric radii.** A nested element's radius equals the parent radius minus the padding between them.
- Borders are rare. Separate things with spacing, background contrast or hairlines. A 1px solid grey box around every card looks like a web template, not Apple.

## Layout and spacing

- Use an 8pt grid with 4pt for fine adjustments. Tokens: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`.
- Margins: 16px on compact (phone), 20px on regular, and 24–32px content padding on desktop.
- **Inset grouped lists** are the signature pattern. Rows sit in a rounded group on `--bg-grouped-secondary`, over a `--bg-grouped` page, with hairline separators *inset* to the text start (not full width).
- Row height is at least 44px. **Hit targets are at least 44×44px**, even when the visible glyph is smaller; extend them with padding or a pseudo-element.
- Desktop app shell: a translucent **sidebar** (240–280px) for navigation, content in the centre, and an optional **inspector** panel on the right (300–360px) for detail or chat. Panels collapse into sheets on narrow viewports.
- Use one primary action per view, top-right or as a prominent filled button. Everything else is secondary.
- White space is a feature. If a screen feels empty, the hierarchy is working; don't fill it.

## Components

- **Buttons.** There are four styles: *filled* (accent background, white label; primary action only), *tinted* (accent at 15% background, accent label), *gray* (`--fill-tertiary` background, `--label` text) and *plain* (accent text, no background). Height is 32px on desktop and 44–50px for large touch buttons, with radius `--r-sm` or a pill shape. Never give a button a shadow.
- **Checkboxes** follow the Reminders style. A circle, 22px, with a `1.5px` stroke in `--label-tertiary`. When checked it fills with the task's tint (or `--accent`) and shows a white checkmark; the row's title fades to `--label-secondary`. It never becomes a square.
- **Segmented control.** `--fill-tertiary` track, white or elevated thumb with a small shadow that slides between segments, 13px semibold labels.
- **Toggle switch.** 51×31, green (`--green`) when on.
- **Text fields.** `--fill-tertiary` background, no border, `--r-sm` radius, and a 3–4px accent focus ring at 30–40% opacity on focus.
- **Sheets and modals.** Slide up from the bottom on compact screens and appear centred on desktop. Use `--r-xl` corners, a grabber on touch, and a dimmed backdrop (`rgba(0,0,0,.2)` light, `.4` dark).
- **Popovers and menus.** Material surface, 6–8px item padding, 13px text, a hover highlight in `--accent` with white text (macOS style) or `--fill-tertiary`, and separators between groups.
- **Toasts / HUD.** A small pill at the bottom centre on material. Keep it to one line, with at most one action ("Undo").
- **Empty states.** A centred SF-style glyph at 48px in `--label-tertiary`, a Title 3 heading, one sentence of Subheadline in `--label-secondary`, and one action.

## Iconography

- Use a line icon set that matches SF Symbols' optical weight: Lucide or Phosphor at `stroke-width: 1.75`, sized to the cap height of adjacent text. Don't mix icon families.
- Icons inherit `currentColor`. Use filled variants only for selected or active state (for example, a selected tab).
- Never use the Apple logo or Apple product imagery, and never copy apple.com assets.

## Accessibility (non-negotiable)

- Text contrast is at least 4.5:1, and 3:1 for large text and essential icons. Check secondary labels on materials specifically.
- Respect `prefers-reduced-motion`, `prefers-reduced-transparency`, `prefers-contrast: more` (strengthen separators and labels) and `prefers-color-scheme`.
- Show a visible focus ring for keyboard users (`:focus-visible`): 3px accent at 50% opacity, offset 2px. Never use `outline: none` without a replacement.
- Every icon-only button has an `aria-label`. Use real `<button>`, `<input type="checkbox">` and `<dialog>` elements.
- Sizes are in `rem` so the layout survives 200% zoom.

## Anti-patterns (instant "not Apple")

- Gradients on buttons or cards, heavy drop shadows, or thick borders on every container.
- More than one saturated colour in a view, or coloured text used for emphasis.
- Centred body text, all-caps buttons, or letter-spaced headings.
- Skeuomorphic textures, or glassmorphism on *content* (material is for chrome).
- Tiny hit targets, cramped rows, or edge-to-edge separators in inset lists.
- Spinner-only loading for content. Use skeleton rows or keep the previous content visible.
- Emoji used as icons in the interface.

## Review checklist

Before shipping a screen, confirm:
1. Squint test: the user's content is the most prominent thing, and the chrome recedes.
2. Only one accent colour, and it appears only on interactive elements.
3. Every colour, radius, space and font size comes from a token.
4. Light and dark themes both look intentional. Dark is not just "inverted".
5. Translucent chrome falls back to opaque under reduced transparency.
6. All targets are at least 44px, every element has a focus ring, and contrast passes.
7. Nothing on screen could be removed without losing meaning.
