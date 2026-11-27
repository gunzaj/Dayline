# Decisions

Why Dayline is built the way it is, including the constraints that shaped it.

## Name

The app, bundle ID (`io.github.gunzaj.dayline`) and menu-bar label are all
Dayline.

## No Xcode: SwiftPM plus a hand-assembled bundle

Dayline is developed with only the Command Line Tools installed, and that SDK
ships without the SwiftUI macro plugin. Consequences:

- `@State`, `@StateObject`'s macro expansion, `@Observable` and SwiftData's
  `@Model` all fail to compile (`external macro implementation ... not found`).
  The app uses `ObservableObject`/`@Published` and one small `ObservableObject`
  per screen instead of `@State`.
- There is no XCTest, so `Sources/DaylineChecks` is a plain executable of
  assertions. `make test` runs it.
- There is no `.xcodeproj`. `scripts/build.sh` compiles with SwiftPM, copies the
  binary into `Dayline.app/Contents/MacOS`, adds `Info.plist`, icons and the
  Garmin helper, then ad-hoc signs with `codesign --force --sign -`.

SwiftData was the first storage choice and was abandoned for the same macro
reason, not for a design objection. `Store` is a hand-rolled Codable JSON store.
Saves are encoded and written on a background queue and a burst of them
collapses into one write. Before the first write of each day the previous file
is copied to `Backups/` (seven kept). Decoding is per record: one record that
cannot be read is skipped and counted, the original file is copied aside before
anything can overwrite it, and a file that cannot be read at all is quarantined
and replaced by the newest backup.

## AppKit shell, SwiftUI screens

`MenuBarExtra` cannot show a coloured countdown title or open arbitrary
windows the way the design needs. Dayline uses `NSApplication` with
`.accessory` activation policy (no Dock icon, `LSUIElement`), an `NSStatusItem`
with a template icon and a text title, and an `NSPopover` hosting
`PopoverView`. Every other screen is an `NSWindow` + `NSHostingView`, tracked by
route so a second click focuses the existing window.

The break overlay is one borderless window per `NSScreen`, at `.screenSaver`
level with `canJoinAllSpaces` and `fullScreenAuxiliary`, so it lands over full
screens and on every Space. The overlay itself stays click-through-free because
its only job is Start, Snooze or Skip.

## Time model

`TimeOfDay` is minutes since midnight, independent of date. `DayKey` is a local
`YYYY-MM-DD` string. All planning happens in local time; there is no timezone
database and no travel handling. Day boundaries come from the per-weekday
schedule, with a wind-down prompt before the end of work hours.

Defaults: 09:00–17:30 Mon–Fri, wind-down 17:15, lunch window 11:30–14:00, five
goals (standing 120 min, six breaks, two breathing sessions, 30-minute lunch,
one reflection).

## Break engine

The engine is pure and deterministic given events, settings, health and the
current time; `DaylineChecks` exercises it without a UI. Decisions are ordered:

1. Day off or outside work hours: no prompts.
2. In a meeting or escalated overlay already showing: hold.
3. Media playing (`pauseOnMedia`): downgrade to a hint, never an overlay.
4. Microphone open: allow notifications but cap escalation after
   `openMicCapMinutes`, and skip overlays entirely for known conferencing apps.
5. Focus mode: notification only.
6. Otherwise: notification after `escalationNotificationAfter` minutes late,
   overlay after `escalationOverlayAfter`.
7. Snoozes are capped; after the cap the only choices are start or skip.

Lunch is protected: no break is booked over the lunch gap, and the lunch break
gets its own timer. A long meeting or a long back-to-back run schedules a break
in the next free gap. Standing-call rules match on title, length, attendee count
or recurrence, as include or exclude.

## Screen-share detection is a heuristic

Without the Screen Recording permission there is no reliable way to know that a
screen is being shared. Dayline treats an open camera or microphone plus a
known conferencing app in the foreground as "in a call", and pauses escalation.
That covers Meet, Zoom, Teams and Webex in practice; a browser tab sharing in a
non-conferencing app can be missed. This is documented in Settings rather than
papered over with a permission request the app does not otherwise need.

## Verification

`autoConfirm` credits a break when the timer ends and the signal was plausible
(idle changed, media stopped, or the user confirms). `honorSystem` credits the
timer. Ambiguous cases surface a one-tap "Yes, done" card instead of silently
crediting or discarding. A break only counts once it ends; closing the session
window ends it with no credit.

## Garmin

The official Garmin API needs a partner programme. The practical route is
`python-garminconnect`, so the app bundles a small helper and talks JSON over
stdin/stdout. The helper and venv are deliberately outside the signed bundle:
the app is ad-hoc signed, and a venv inside `Contents/Resources` would break the
seal on every package update. The helper path is resolved at runtime; if Python
or the venv is missing, Garmin is simply offline and the rest of the app works.

The helper never touches the disk: the app passes the session token on stdin,
the helper returns the refreshed one on stdout, and only the Keychain stores
it. Readings are reduced to one sample per 15 minutes before they reach the
app, which keeps the state file small. The helper runs with a timeout and a
minimal environment.

Sync is read-only and capped at 400 days of history. Errors are shown in
Settings, not as modal alerts, because a failed Garmin sync must never block a
break.

## AI

AI is opt-in and provider-agnostic: Anthropic Messages API, OpenAI Chat
Completions, or any OpenAI-compatible base URL. The prompt is built in
`AIPrompt` from daily aggregates; calendar titles and journal text are separate
opt-ins, both off by default except journal text, which is the
point of an insight. The test connection call sends a tiny prompt so a bad key
fails fast without spending a weekly insight.

## Heatmap

The year view is 52 weeks × 5 workdays (Mon–Fri). Weekends
and explicit days off are drawn as dashed empty cells, not as zeroes, so a day
off cannot look like a failed goal. Metrics are goals, standing, breaks, stress,
mood and energy; the default is goals.

## What is intentionally not here

- No cloud sync, accounts or telemetry.
- No event creation or editing.
- No notification permission prompt until the first break would be due.
- No attempt to count steps from the Mac; Garmin steps are used when present,
  otherwise movement minutes stand in.
