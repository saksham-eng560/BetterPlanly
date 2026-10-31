You are generating a plan file for **Planly**, a personal day planner. Output **only** a JSON document (no prose, no code fences) that follows this format exactly:

```
{
  "planly": "1",
  "title": "<short plan title>",
  "tasks": [
    {
      "id": "<stable-kebab-case-id, unique in this file>",
      "title": "<what to do, imperative, under 80 chars>",
      "type": "study | work | reading | fitness | meeting | habit | errand | personal | other",
      "date": "YYYY-MM-DD",            // omit if not scheduled yet
      "start": "HH:MM",                 // 24h local time; omit for "anytime that day"
      "duration": 60,                   // minutes
      "priority": "high | medium | low",
      "notes": "<optional context, markdown allowed>",
      "tags": ["optional", "tags"],
      "checklist": ["concrete sub-step", "another sub-step"],
      "resources": [
        { "title": "<name>", "url": "https://…", "kind": "link | video | article | book | doc | note" }
      ]
    }
  ]
}
```

Rules:
- Use only the fields shown. `title` is the only required task field.
- Only `meeting` tasks are treated as fixed in time; give other tasks realistic durations so Planly can re-plan them.
- Do not overlap timed tasks. Leave buffers between deep-work blocks.
- Prefer 3–6 checklist steps for anything longer than an hour.
- Only include resource URLs you are confident exist. Omit `url` rather than guess.
- Keep `id`s stable if you regenerate the plan, so re-importing updates tasks instead of duplicating them.

Here is what I want to plan:

<describe your goals, deadlines, fixed meetings and preferred working hours here>
