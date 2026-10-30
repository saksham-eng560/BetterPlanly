# UI specification

The UI follows two project skills: [`apple-design`](../.claude/skills/apple-design/SKILL.md), which covers the HIG look, and [`emil-design-eng`](../.claude/skills/emil-design-eng/SKILL.md), which covers motion. Tokens live in `frontend/src/design/tokens.css`, and components use nothing else.

| Light | Dark |
|---|---|
| ![Today, light](screenshots/today-light.png) | ![Today, dark](screenshots/today-dark.png) |

## Layout

```
┌──────────────── main column (scrolls) ─────────────────┬── agent inspector (23.5rem) ──┐
│ toolbar · material · sticky                            │ header: model status, "React  │
│   Planly   ‹ M T W T F S S ›      ⟲ History  + Import  │         to ticks" switch      │
├────────────────────────────────────────────────────────┤ messages (scroll)             │
│ Large Title "Today" / weekday   · subtitle "x of y done" │  user bubbles · agent bubbles │
│ ANYTIME   [card] [card]                                │  event chips · tool rows      │
│ 09:30 ─ [type-coded card, height ∝ duration]           │  change cards with Undo       │
│ ●──── now-line (today)                                 │ composer                      │
│        Free · 1h 15m                                   │                               │
│ Checklist (inset grouped):  Missed · <Day> · Unscheduled│                               │
└────────────────────────────────────────────────────────┴───────────────────────────────┘
```

- **Below 1080 px:** the inspector becomes a drawer from the right, opened from the sparkle button in the toolbar, with a dimmed scrim.
- **Below 760 px:** the brand and week arrows are hidden, and Import becomes an icon button.
- **Below 480 px:** the drawer takes the full width.
- **Sheets:** centred on desktop and bottom sheets on phones.

![Phone](screenshots/phone.png)

## Task types

Each type has a colour, used at about 13% as the card background, as a 3 px leading edge, and as the glyph colour. Blue is reserved for the accent.

| Type | Colour | Icon (Lucide) |
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

Colours with fixed meanings:
- **Red** means Missed only.
- **Green** means done, and also marks the agent-online dot and the switch.
- **Orange flag** marks high priority, following Reminders.

## Components

| Component | Notes |
|---|---|
| Task card | `<button>` that opens the task sheet. Shows a glyph circle, a headline title, and a footnote meta line (time range · duration · type). Badges show high priority, checklist progress and resource count. Done cards drop to 55% opacity and show a check glyph. |
| Checklist row | 56 px min-height. A 22 px Reminders-style circular checkbox in the type colour, with the checkmark drawn by `stroke-dashoffset`. Title and meta in the middle. Move and details actions sit at the end in tertiary grey, turning accent on hover. Separators are inset to the text start. |
| Move menu | Popover on material, opening from its trigger corner. Offers Today, Tomorrow, Next week, Pick a date… (native date input) and Remove date. |
| Task sheet | Native `<dialog>`, which gives focus trapping, Esc and an inert background. Holds a facts table, notes, steps, resources, "Ask the agent for resources", Move, and Mark as done. |
| Import sheet | Segmented control with three tabs: Plan file (drop zone and Choose File), Notion (database link) and Agent prompt (preview and Copy). |
| History popover | Change sets with actor icon, summary, relative time and Undo. Export is in its header. |
| Toasts | One-line pill on material at the bottom centre, with at most one action (Undo). They stay up for 5 s, pause on hover, and pause while the tab is hidden. |
| Agent panel | Header shows model, online state and the "React to ticks" switch. User messages are accent bubbles; agent replies are grouped-secondary bubbles. Trigger messages appear as grey chips showing only what happened, never the instructions to the model. Tool calls appear as small activity rows. Each run ends with a change card offering Undo. |

## Motion

| Interaction | Animation | Why |
|---|---|---|
| Button / card / day press | `scale(0.97)` (cards 0.985), 160 ms `--ease-out` | Feedback that the press registered |
| Card enters / leaves timeline | opacity + `translateY(6px) scale(0.98)` → rest, spring 0.45 s, bounce 0.12; exit 150 ms | Nothing appears from nothing; exits are faster than entrances |
| Agent or user moves a task | `motion` layout animation keyed by task id (spring) | The card visibly travels to its new slot, so a re-plan reads as one movement |
| Checkbox tick | fill scales 0.6 → 1 (240 ms ease-out), checkmark draws 240 ms after a 60 ms delay | Shows the state change |
| Popover | opacity + `scale(0.96)` → 1, 180 ms, origin at the trigger corner | Ties the popover to its trigger |
| Sheet | `@starting-style` opacity + `scale(0.96)` (desktop) / `translateY(100%)` (phone), 240 ms ease-out; close 120 ms | Modals stay centred and are dismissed quickly |
| Agent drawer | `translateX`, 320 ms `--ease-drawer` | iOS drawer curve |
| Toast | spring from `translateY(100%)`, exit 150 ms | Enters and leaves from the same edge |
| Chat items | opacity + 6 px rise, 200 ms | Streaming text itself is not animated |

Not animated:
- keyboard actions (Enter to send)
- token-by-token text
- hover colour changes, beyond a quick `ease`

**Reduced motion.** `MotionConfig reducedMotion="user"` turns transform animations into fades. CSS press scales, the drawer slide and sheet translation are removed under `prefers-reduced-motion`; opacity changes remain.

## Accessibility
- Every control is a real `<button>`, `<input type="checkbox">` or `<dialog>`. Icon-only buttons have `aria-label`s, such as "Move “Groceries”".
- Hit targets are at least 44 px. Icon buttons extend theirs with a pseudo-element, and checkboxes have a 44 px label.
- `:focus-visible` shows a 3 px accent ring at 50% opacity.
- The app respects `prefers-color-scheme`, `prefers-reduced-motion`, `prefers-reduced-transparency` (materials become opaque) and `prefers-contrast: more` (stronger separators and secondary labels).
- Text sizes are in `rem`. Times use tabular numerals.
- The chat log uses `aria-live="polite"`, and toasts use `role="status"`.

## Verification
`frontend/e2e/smoke.spec.ts` drives the real app with Playwright and writes the screenshots in `docs/screenshots/`. It runs against the backend, Postgres and `scripts/fake_ollama.py`, and covers:
- import
- the agent's day review and re-plan
- ticking with the agent reacting
- moving a task and undoing the move
- the task sheet
- dark mode
- the phone layout and the agent drawer
