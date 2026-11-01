# Planly for iPhone — native SwiftUI app

## Context
You want Planly on your iPhone as a real app to track your day better. You asked for a **full native app written from scratch**, not a website wrapper, with **task reminders, a Home Screen widget and an app-icon badge**. It works on **home Wi-Fi only** and is signed with a **free Apple ID**.

Planly's brains (FastAPI + Postgres + the Ollama model) stay on your Mac, because an iPhone can't run qwen2.5:14b. The iPhone app is a second client of the same HTTP API the website uses (`docs/API.md`), so tasks, history, undo and the agent stay in sync between the two.

## What gets built

### 1. Backend: make it reachable from the phone (small change)
- `scripts/start.sh`: add `PLANLY_HOST` (default `127.0.0.1`), passed to uvicorn `--host`. At the end it prints the Mac's address for the phone (`http://<name>.local:8000` and the `ipconfig getifaddr en0` IP).
- `Makefile`: add `make phone` (= `PLANLY_HOST=0.0.0.0 scripts/start.sh`).
- No CORS change is needed, because a native app isn't a browser. Docker already exposes `:8080`, and nginx proxies `/api`, so the app accepts either `…:8000` or `…:8080`.

### 2. `ios/` — new Xcode project (iOS 17+, SwiftUI, no third-party dependencies)
```
ios/
  project.yml                 XcodeGen spec (source of truth, fallback generator)
  Planly.xcodeproj/           committed, so you just open it (Xcode 16+ synchronized folders)
  Config/Signing.xcconfig     the ONE file you edit: DEVELOPMENT_TEAM + BUNDLE_ID_PREFIX
  PlanlyKit/                  local Swift package shared by app + widget (+ tests)
    Models.swift              Task, ChecklistItem, Resource, ChangeSet, TaskChange, AppState, ImportResult, ThreadMessage (Codable, mirrors frontend/src/lib/api.ts)
    APIClient.swift           every endpoint the web uses + POST /tasks, PATCH/DELETE tasks, multipart import, export
    SSE.swift                 port of frontend/src/lib/sse.ts parseSseChunk + AsyncStream over URLSession.bytes
    Dates.swift               port of frontend/src/lib/dates.ts (weekStart, nextMonday, localNowIso, elapsedShare…)
    TaskTypes.swift           the 9 types: label, SF Symbol, colour (from design/tokens.css)
    ServerConfig.swift        server URL + settings in App Group UserDefaults; snapshot cache for widget/offline
    ReminderPlanner.swift     pure logic: tasks → reminder times (unit-tested)
    Tests/                    decoding of real API JSON, SSE parsing, dates, reminder planning
  Planly/                     the app
    PlanlyApp.swift, AppDelegate.swift   notifications delegate, BGAppRefreshTask, notification "Done" action
    Stores/PlanStore.swift    @Observable: week/14-day tasks, missed, unscheduled, state; mutations → undo toast; refresh triggers widget reload + badge + reminders
    Stores/AgentStore.swift   port of agentStore.ts: thread load, run queue, 409 retry, 4 s debounced task_event, day review on first open of a day with missed tasks, streaming tokens/tool chips/changes
    Features/Today/           TodayView, WeekStrip (Mon–Sun with progress dots), DayTimeline (type cards, now-line, "Free · 1h 20m" gaps, Anytime group, empty state)
    Features/Checklist/       one box per section (stable tint per section name, Missed in red), tick, swipe + context menu: Today/Tomorrow/Next week/Pick date
    Features/TaskDetail/      sheet: type, start/end, duration, priority, notes, steps (tickable), resources (open in Safari), complete/reopen, move, delete, "Ask the agent"
    Features/NewTask/         quick add (title, type, date, time, duration, priority)
    Features/Agent/           chat with markdown text, tool chips (describeTool port), changes card with Undo, react-to-changes toggle, model/reachable status
    Features/History/         change sets with actor + time, Undo, Export (share sheet)
    Features/Import/          .fileImporter for json/yaml/md/csv/zip → multipart upload, result summary + skipped files, Notion DB id when configured
    Features/Settings/        server address + "Test connection" (GET /api/health), reminder lead time (0/5/10/15 min), toggles for reminders/badge, Local Network help
    Features/Onboarding/      first-run: enter your Mac's address, test, allow notifications
    Design/                   gradient backdrop + .ultraThinMaterial glass cards to echo the web's glass look; light/dark; Dynamic Type; VoiceOver labels
    Services/Reminders.swift  schedules local notifications for the next 2 days (≤ 60, iOS caps at 64), category with "Mark done" / "Snooze 10 min"
    Services/Badge.swift      setBadgeCount(tasks left today)
    Assets.xcassets           AppIcon 1024 rendered from frontend/public/icon.svg, accent colour
    Info.plist                NSAllowsLocalNetworking + NSAllowsArbitraryLoads (plain http on LAN), NSLocalNetworkUsageDescription, BGTaskSchedulerPermittedIdentifiers, PlanlyAppGroup key
  PlanlyWidget/               widget extension
    TodayWidget               small: progress ring + next task; medium: next 3 tasks with tick buttons (iOS 17 interactive, CompleteTaskIntent); lock screen: circular progress + rectangular next task
    Provider                  fetches /api/tasks for today; falls back to the cached snapshot when the Mac is unreachable ("Last updated 14:05")
  README.md                   step-by-step setup guide (below)
```

**Free Apple ID caveat:** it isn't clear whether App Groups (how the app and widget share settings) work with a free Personal Team. So the widget also has its own "Mac address" field in Edit Widget. If signing rejects App Groups, the README says to remove that capability from both targets, and everything else still works.

### 3. Docs
- `README.md`: a short "On your iPhone" section linking `ios/README.md`.
- `docs/adr/0007-native-ios-client.md`: why native SwiftUI over a web view, LAN-only, and the API as the contract.

## Setup guide you'll get (`ios/README.md`, summary)
1. Mac: `make phone` (or `docker compose up`). Note the printed `http://YourMac.local:8000`. Allow incoming connections if the macOS firewall asks.
2. iPhone: Settings → Privacy & Security → **Developer Mode** on (it appears after the first install attempt).
3. Xcode → Settings → Accounts → add your Apple ID.
4. Edit `ios/Config/Signing.xcconfig`: set `DEVELOPMENT_TEAM` (shown in Accounts) and a unique `BUNDLE_ID_PREFIX` such as `com.saksham`.
5. Open `ios/Planly.xcodeproj`, plug in the iPhone, pick it as the run destination, press ⌘R.
6. On the iPhone, trust the developer: Settings → General → VPN & Device Management.
7. In the app, enter the Mac address, allow Local Network and Notifications. Then add the widget from the Home Screen.
8. A free Apple ID expires the app after 7 days: plug in and press ⌘R again (your data lives on the Mac, so nothing is lost).
Plus troubleshooting: can't connect (same Wi-Fi, Local Network permission, firewall, `.local` vs IP), App Group signing error, and the "Untrusted Developer" error.

## Verification
- **In this Linux container:**
  - Install the Swift toolchain and run `swift test` on `PlanlyKit`: model decoding against JSON captured from the real backend, SSE parser parity with `frontend/src/lib/lib.test.ts` cases, dates and the reminder planner.
  - Run `swiftc -parse` over all app and widget sources to catch syntax errors.
  - Start the backend with `PLANLY_HOST=0.0.0.0` plus fake Ollama and curl every endpoint the app calls from the LAN address.
  - Run the existing `make test` to confirm the backend and frontend are unchanged.
- **Can't be done here:** SwiftUI and WidgetKit only compile on macOS. The first real build happens on your Mac with ⌘R, and you'd report any compile errors back for me to fix. I'll keep the code to stable iOS 17 APIs to keep that list short.
- **On the iPhone:** tick a task in the app and see it ticked on the website, and the reverse. Undo from History. Chat with the agent and watch tokens stream in. A reminder fires and "Mark done" works from the notification. The widget tick button completes a task. The badge count drops as you tick tasks.

Commit to `claude/sleepy-fermi-a1duoe` and push.
