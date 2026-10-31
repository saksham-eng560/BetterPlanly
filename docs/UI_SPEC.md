# UI specification

The UI is **glass over an environment**: Apple's visionOS / Liquid Glass language, art-directed after a reference landing page. That page has a vivid motion-blurred backdrop behind reeded glass, frosted panels with ruler ticks, huge light display type, a glass pill nav with a lime dot, and white pill buttons.

It follows three sources:
- the project skills [`apple-design`](../.claude/skills/apple-design/SKILL.md) (look) and [`emil-design-eng`](../.claude/skills/emil-design-eng/SKILL.md) (motion)
- the design spec [docs/design/GLASS_SPEC.md](design/GLASS_SPEC.md)
- the decision record [ADR 0006](adr/0006-glass-over-an-environment.md)

Tokens live in `frontend/src/design/tokens.css`. The environment and glass tiers live in `frontend/src/design/base.css`. Components use nothing else.

| Day | Night |
|---|---|
| ![Today, day](screenshots/today-light.png) | ![Today, night](screenshots/today-dark.png) |

## Three depths

| Depth | What it is | Where |
|---|---|---|
| **Environment** | One fixed CSS layer, the world behind the app. A cerulean → magenta → coral field is painted at 1/k width, blurred and stretched back out with `scaleX(k)`, which gives the reference's horizontal motion blur. A refraction copy sits behind a saw-tooth mask, and reeded-glass ribs (14 px pitch) and a darker top band go on top. It is static: no drift, no `filter`, no blend modes. Its luminance is capped so contrast is computable. | `main.tsx` `<Backdrop/>`, `base.css` `.bg*` |
| **Windows** | Glass that holds content. There are three tiers: **thin** (toolbar edge, ornaments), **regular** (Day window, widgets, agent window) and **thick** (sheets, popovers, toasts, the narrow-screen drawer). Each has a 0.5 px white edge and a 1 px specular top line. | `.glass-thin`, `.glass-regular`, `.glass-thick` |
| **Platters** | Flat white 6% fills inside windows, with no blur: task cards, checklist rows, bubbles, fields and pills. | `--platter`, `--platter-edge` |

Display type (≥ 22 px, weight 300) is the only content that sits directly on the environment: the "Today" header, the "Checklist" heading and the progress numbers.

## Colour roles
- **White is the interactive colour.** Primary buttons (Import, Send, Mark as done) are solid white pills with ink `#0B1020` labels. Secondary controls are glass circles.
- **Lime `#C6F432` is a signal, not an accent.** It marks *now / today / live* only:
  - the today dot in the week strip and the now-line with its time capsule
  - the elapsed ticks on the running task's ruler
  - the Import tab underline and the agent-online dot
  - the switch's on state and the focus ring
- **Hue belongs to content.** Task types and checklist sections use their own colours. A solid colour always carries ink, never white.
- **Red `#FF7A70`** means Missed (with `--red-text` for words). The **orange flag** marks high priority.

## Layout

```
┌──────────────── main column (scrolls over the fixed environment) ───────┬─ agent window ─┐
│ toolbar: Planly  (‹ M T W T F S S ›)  ◷  [+ Import]  · glass ornaments  │ glass-regular, │
│                                                                          │ inset 8–12 px  │
│ Today                       ← display XL, weight 300, on the environment │ header: model, │
│ Friday, October 30 · 2 of 10 done                                        │ "React to      │
│ ┌ Day window (glass-regular) ────────────────────────────────────────┐   │ ticks" switch  │
│ │ ANYTIME  [platter] [platter] [platter]                              │   │ messages       │
│ │ [platter: Morning run 07:00–07:40 ◷ 40m]                            │   │ change cards   │
│ │ Free · 1h 50m ┆┆┆┆┆┆┆┆┆┆┆┆┆┆┆┆┆┆┆┆┆┆┆┆                         │   │ composer       │
│ │ [platter: DSA practice  09:30 ──◷ 1h 30m── 11:00  ┆┆┆ruler┆┆┆]      │   │                │
│ │ (10:05)━━━━━━━━━━━━━━━ lime now-line ━━━━━━━━━━━━━━━━━━━━━━━━━━━     │   │                │
│ └─────────────────────────────────────────────────────────────────────┘   │                │
│ Checklist                                            ← display L         │                │
│ [widget window] [widget window] [widget window]  ← one per section       │                │
└──────────────────────────────────────────────────────────────────────────┴────────────────┘
```

- **At 1080 px and below:** the agent window becomes a drawer. The glass itself slides in from the right; it is never inside a transformed wrapper, which would cut it off from the environment. It uses the thick tier over a dimmed scrim, and opens from the sparkle ornament.
- **At 760 px and below:** the brand, the week arrows and the toolbar Today button are hidden, and Import becomes a white circle with a plus.
- **At 480 px and below:** the drawer is full screen and near-solid, as an iOS full-screen sheet is.
- **Sheets:** centred on desktop, bottom sheets on phones.

![Phone](screenshots/phone.png)

## Task types

Each type has an on-glass tint. Cards use it as a solid glyph disc (ink icon), as an 8% wash over the platter, and for the ruler ticks.

| Type | Tint | Icon (Lucide) |
|---|---|---|
| study | indigo | GraduationCap |
| work | cyan | Briefcase |
| reading | orange | BookOpen |
| fitness | pink | Dumbbell |
| meeting | purple | Users |
| habit | mint | Repeat |
| errand | brown | ShoppingBag |
| personal | yellow | Heart |
| other | gray | Circle |

## Components

| Component | As built |
|---|---|
| Week strip | The reference's pill nav, as a thin-glass capsule. A glass lozenge slides to the selected day (`layoutId="day-lozenge"`), a lime dot marks today, and grey dots mark days with tasks. |
| Toolbar | The brand, the week strip, History as a glass-circle ornament, and **Import** as a white pill. It is a sticky thin-glass band. |
| Task card | A `<button>` platter. It shows a type disc, a title clamped to 2 lines, and badges (flag, checklist progress, resource count). Short tasks show their time range, a "◷ 40m" duration pill and the type. Timed tasks of 45 min or more show large light Start/End numerals on a hairline with the duration pill, plus a **tick ruler** along the bottom edge. On the running task the ruler's elapsed part is lime. Done cards use secondary text and a strike-through, not opacity. |
| Now-line | A lime time capsule with a 2 px lime rule. |
| Free gap | A "Free · 1h 50m" pill next to a faint untinted tick ruler. |
| Widget boxes | One glass window per section (iOS widget style). Each has a solid icon disc, a title, and a large light done count, with rows as platters. A widget holds that section's tasks for the selected week and the next, plus its unscheduled ones. Open tasks come first, with "Show all" after 6. Missed tasks get their own red box, shown first. |
| Checklist row | A 56 px min-height platter row. It has a circular checkbox (a tint ring that fills solid with an ink checkmark), title and meta, and Move / details actions. |
| Move menu | A thick-glass popover, portalled to `document.body`, or into the `<dialog>` when used inside a sheet, so blurs never nest. It offers Today, Tomorrow, Next week, Pick a date… and Remove date. |
| Task sheet | A native `<dialog>` on thick glass. A **time card** echoes the reference's frosted panel, with large Start/End numerals, the duration pill and a ruler. Below it come facts, notes, steps, resources, Move and the white **Mark as done** pill. |
| Import sheet | Three tabs on a hairline track, with a lime underline that slides between them: Plan file, Notion and Agent prompt. The drop zone turns lime while dragging. The result banner is signal-tinted. |
| History popover | Shows change sets with actor icon, summary, relative time and Undo. Export is in the header. A **Reduce transparency** switch sits under the log; Safari has no `prefers-reduced-transparency`, so the app provides its own. |
| Toasts | A one-line thick-glass capsule at the bottom centre with at most one action. It stays up for 5 s, pausing on hover and while the tab is hidden. |
| Agent window | The header shows the model, an online dot and the "React to ticks" switch. User messages are white bubbles with ink text; agent replies are platters. Trigger messages appear as chips, tool calls as small activity rows, and each run ends with a change card offering Undo. The composer is a platter field next to a white send circle. |

## Motion

| Interaction | Animation | Why |
|---|---|---|
| Press (buttons, pills / platters / circles) | `scale(.97)` / `.985` / `.94`, 160 ms `--ease-out` | Confirms the press |
| Hover (fine pointer only) | `background-color` 120 ms, no transform | Kept small, because it happens constantly |
| Selected day / import tab | Lozenge and underline `layoutId` spring | Spatial continuity, as the reference's nav pill slides |
| Card enters, leaves or is re-planned | Spring 0.45 s, bounce 0.12; exit 150 ms; layout animation keyed by task id | A re-plan reads as one movement |
| Checkbox tick | Fill scales 0.6 → 1, then the mark draws | Shows the state change |
| Popover | Opacity + `scale(.96)` → 1, 180 ms, origin at the trigger corner | Ties it to its trigger |
| Sheet | `@starting-style` opacity + scale (desktop) / `translateY(100%)` (phone) | Modals stay centred |
| Agent drawer | `translateX` of the glass itself, 320 ms `--ease-drawer` | iOS drawer curve |
| Toast | Spring from `translateY(100%)`, exit 150 ms | In and out from the same edge |

**Not animated:**
- `backdrop-filter` and the environment: they are expensive, and animated blur shimmers
- theme switches
- keyboard actions
- streamed tokens
- the ruler's progress, which steps every 30 s

**Reduced motion.** `MotionConfig reducedMotion="user"`. Slides become jumps or fades, and CSS press scales, drawer and sheet translation and the skeleton pulse are removed.

## Accessibility
- **Contrast is computed, not eyeballed.** The model is in [docs/design/contrast](design/contrast). Text on glass uses only white or white at 0.84. Tertiary 0.62 is for icons and decoration. Solid colours carry ink.
- **Fallbacks.** `prefers-reduced-transparency`, the in-app Reduce transparency switch, `prefers-contrast: more`, `forced-colors` and browsers without `backdrop-filter` all switch the glass tiers to opaque twins (`--solid-*`).
  - More Contrast also dims the environment, removes the reeds, strengthens hairlines and turns the selected day solid white.
  - Forced colours hide the environment and use system colours.
- **Focus.** A 2 px lime ring with a 2 px offset, following border radius. Focusable elements only sit on glass or the top band.
- **Hit targets.** At least 44 px, with icon buttons and ornaments extended by `::after`. The phone week-strip days are 30–34 × 48 px.
- **Semantics.** Every control is a real `<button>`, `<input type="checkbox">` or `<dialog>`. Decorative rulers, lozenges and dots are `aria-hidden`. The chat log is `aria-live="polite"`, and toasts use `role="status"`.
- **Sizing.** Text sizes are in `rem`; times use tabular numerals.

## Performance
- **Blur budget.** At most 7 `backdrop-filter`s visible at once, never nested; cards, rows and ornaments never blur.
- **Static environment.** The environment is one fixed layer that doesn't animate, so scrolling never re-rasterises it.
- **Safari rules.** Use literal values in `-webkit-backdrop-filter`, never `var()`. No `filter`, `opacity < 1`, `mix-blend-mode` or `will-change` on any ancestor of a glass surface. See [GLASS_TECHNIQUE.md](design/GLASS_TECHNIQUE.md).

## Verification
`frontend/e2e/smoke.spec.ts` drives the real app with Playwright and writes the screenshots in `docs/screenshots/`. It runs against the backend, Postgres and `scripts/fake_ollama.py`, and covers:
- import
- the agent's day review and re-plan
- ticking with the agent reacting
- moving a task and undoing the move
- the task sheet
- dark mode
- the phone layout and the agent drawer
