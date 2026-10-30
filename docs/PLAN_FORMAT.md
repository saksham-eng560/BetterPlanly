# Plan file format

Planly imports four kinds of file. The **Planly v1** format (JSON or YAML) is the one to ask an AI agent for. The others exist so you can bring tasks you already have.

| File | Detected by | Parser |
|---|---|---|
| Planly v1 JSON / YAML | `.json`, `.yaml`, `.yml` | `backend/app/importers/plan_file.py` |
| Markdown (including Notion page exports) | `.md` | `backend/app/importers/markdown.py` |
| Notion database CSV export | `.csv` | `backend/app/importers/notion.py` |
| Notion database (live) | `POST /api/imports/notion` | `backend/app/importers/notion.py` |

## Planly v1 (JSON / YAML)

The schema is [`schemas/planly-plan.v1.schema.json`](../schemas/planly-plan.v1.schema.json), and there is a full example in [`examples/sample-plan.json`](../examples/sample-plan.json).

```json
{
  "planly": "1",
  "title": "Late October sprint",
  "tasks": [
    {
      "id": "dsa-graphs",
      "title": "DSA practice — graphs",
      "type": "study",
      "date": "2026-10-30",
      "start": "09:30",
      "duration": 90,
      "priority": "high",
      "status": "todo",
      "notes": "Two medium problems minimum.",
      "tags": ["dsa"],
      "checklist": ["BFS on grid", {"title": "Dijkstra", "done": true}],
      "resources": [{"title": "CP-Algorithms: BFS", "url": "https://cp-algorithms.com/graph/breadth-first-search.html", "kind": "article"}]
    }
  ]
}
```

| Field | Type | Default | Meaning |
|---|---|---|---|
| `planly` | `"1"` | required | Format version |
| `title` | string | file name | Plan name |
| `tasks[].id` | string | derived from date + title | Stable id. Re-importing a task with the same id updates it |
| `tasks[].title` | string | required | |
| `tasks[].type` | enum | `other` | `study work reading fitness meeting habit errand personal other` |
| `tasks[].date` | `YYYY-MM-DD` | none (Unscheduled) | |
| `tasks[].start` | `HH:MM` | none (Anytime) | 24-hour local time |
| `tasks[].duration` | minutes | none (treated as 30 when re-planning) | |
| `tasks[].priority` | enum | `medium` | `high medium low` |
| `tasks[].status` | enum | `todo` | `todo done skipped` |
| `tasks[].notes` | string | | Markdown |
| `tasks[].tags` | string[] | | |
| `tasks[].checklist` | (string \| {title, done})[] | | Sub-steps |
| `tasks[].resources` | {title, url?, kind?, note?}[] | | `kind`: `link video article book doc note` |

Export (`GET /api/export`) writes this same format, so an export always imports back.

**Getting a plan from an agent.** Paste [`examples/AGENT_PROMPT.md`](../examples/AGENT_PROMPT.md) into any AI assistant, describe your week, save the reply as `plan.json` and drop it on Planly. The same prompt is behind "Copy agent prompt" in the import sheet.

## Markdown

```markdown
# Late October sprint            ← optional: plan title

## 2026-10-30                    ← a date heading (YYYY-MM-DD); "## Unscheduled" or any other heading = no date
- [ ] 09:30 DSA practice — graphs (study, 90m, high) #dsa
  - [ ] BFS on grid              ← nested checkbox = checklist item
  - [CP-Algorithms](https://…)   ← nested link = resource
  - https://docs.python.org/…    ← nested bare URL = resource
  > Two medium problems minimum. ← quote = notes
- [x] 07:00 Morning run (fitness, 40m)   ← [x] = done
- [ ] Groceries (errand, low)    ← no time = Anytime
```

Metadata in the trailing `( … )` is comma-separated and order-free:

- a duration: `45m`, `90min`, `1h`, `1.5h`
- a priority: `high`, `medium` or `low`
- a type, from the list above

`#words` become tags. Each task's id is derived from its date and title, so re-importing an edited file updates tasks in place as long as you don't rename them.

## Notion

### CSV export
In Notion, open a database and choose **⋯ → Export → Markdown & CSV**, then upload the `.csv`. Columns are matched by name, ignoring case:

| Planly field | Column names tried |
|---|---|
| title | Name, Title, Task |
| date (+ start) | Date, Due, Due date, When, Scheduled |
| type | Type, Category, Area, Kind |
| status | Status, Done, Completed, Complete |
| priority | Priority |
| duration | Duration, Estimate, Minutes |
| notes | Notes, Description, Details |
| resource | URL, Link, Resource |
| tags | Tags, Labels |

Notion date values such as `October 30, 2026 9:30 AM` or `October 30, 2026 9:30 AM → 11:00 AM` are parsed. A range also sets the duration. Status values `Done`, `Complete`, `Completed`, `Yes` and `true` count as done. Type values outside the list map to `other`. A database exported as Markdown is a folder of pages; upload the CSV instead.

### Live sync (Notion API)
1. Create an internal integration at <https://www.notion.so/my-integrations> and copy its token.
2. Share the database with the integration (**⋯ → Connections**).
3. Set `NOTION_TOKEN` in `backend/.env` (or in docker-compose) and restart.
4. In Planly, open **Import → Notion** and paste the database id. That's the 32-character id in the database URL.

Properties are mapped by the same names as the CSV columns, with one difference: the title is always the property of type `title`. The Notion page id is used as the task id, so syncing again updates tasks. Planly does not write back to Notion in v1.

## Re-import rules
- A **Plan** is identified by its source (`plan_file`, `markdown`, `notion_csv`, `notion_api`) together with the file name or database id.
- A task whose id already exists in that plan is **updated**: title, type, date, start, duration, priority, notes and tags are overwritten, and checklist items and resources are added where their title is new.
- A task you completed in Planly is **left alone** (FR-1.6).
- Tasks that have disappeared from the source are **not** deleted.
- Each import is one Change set, so one Undo reverts it.
