# Dayline

A macOS workday coach. It times movement breaks around your calendar, walks you
through them, and keeps a private journal of how the work felt. It lives in the
menu bar for quick actions and has a desktop window with the overview, your
activities, the journal and all summaries.

No account. Calendar and Garmin are read-only. Everything except
an optional AI insight stays on the Mac.

## What it does

- **Break engine.** Works out the free gaps between meetings, then schedules
  standing, walking, breathing, squat, mobility and grip breaks inside them.
  Escalates from a quiet banner to a full-screen overlay on every display and
  Space. Pauses while the mic, camera or a conferencing app is in use.
- **Guided breaks.** Box breathing with a moving square, rep counters, step
  cards, pose sequences, balance intervals, grip sets with rest, 30-minute
  lunch away from the desk.
- **Your equipment.** Switch the built-in equipment on or off, remove what you
  do not own, and add your own with a name and a session length.
- **Editable activities.** Change the time, exercise, length or outcome of
  anything logged, delete it, or add what was missed. Totals and goals follow.
- **Journal.** Free entries plus a 4×4 mood grid (energy × pleasantness), with
  no default square. Guided reflection prompts at the end of the day.
- **Summaries.** Day, week and year. Standing, breaks, lunch, longest seated
  stretch, meetings, stress, Body Battery, goals and streaks. A 52×5 heatmap
  of workdays with switchable metrics.
- **Garmin, optional.** Stress, Body Battery, sleep and HRV tune the intensity
  of the day. Read-only, through a bundled Python helper.
- **AI insights, optional.** Bring your own Anthropic, OpenAI or
  OpenAI-compatible key. Only the aggregates you allow leave the Mac. Keys live
  in the Keychain.

## Build

Requires macOS 14+ and the Swift toolchain. This project builds with the
Command Line Tools alone; no Xcode project, no external Swift packages.

```sh
make test     # swift build + behavioural checks + release build
make build    # dist/Dayline.app, ad-hoc signed
make install  # copy to /Applications and launch
make dmg      # dist/Dayline-<version>-<arch>.dmg, drag to Applications
```

To try it without waiting for real data:

```sh
make run      # launches dist/Dayline.app with a year of sample data
```

`DAYLINE_DEMO=1` is the switch. Demo runs keep their data in a separate
`Dayline-Demo` folder, so they never touch your own. Loading the sample year
from Settings sets your data aside and clearing it brings your data back.

## Garmin (optional)

```sh
./scripts/setup-garmin.sh
```

This finds Python 3.12+ (Homebrew `python@3.13` works), creates a venv in
`~/Library/Application Support/Dayline/Garmin/venv`, and installs
`garminconnect==0.3.20`. Then connect from **Settings → Garmin**. The password
goes straight to Garmin through the helper and is not kept. The session token
lives only in the macOS Keychain; the helper holds it in memory and never
writes it to disk. MFA is supported.

## Privacy

- State: `~/Library/Application Support/Dayline/state.json`, written atomically
  off the main thread. One backup a day is kept in `Backups/` (seven days). A
  file that cannot be read is moved aside and the newest backup is restored; if
  only some records cannot be read, they are skipped and the original file is
  kept next to it.
- Secrets: Keychain only. Never in the JSON, never in a file.
- Calendar: EventKit, read-only, selected calendars only.
- Journal export: one Markdown file per day plus a JSON file with the journal
  and check-ins only, to a folder you pick.
- AI: off until you add a key. Once a key is set, journal text is included by
  default and calendar titles are not; both are separate toggles in
  Settings → AI.

## Layout

```
Sources/DaylineCore     scheduling, break engine, storage, summaries, AI, Garmin
Sources/Dayline         AppKit shell, SwiftUI screens, system services
Sources/DaylineChecks   behavioural checks (no XCTest needed)
scripts                 build, install, disk image, test, Garmin helper
docs/DECISIONS.md       why the app is shaped this way
```

## License

MIT. See [LICENSE](LICENSE).

## Design

The interface uses a warm paper background, green accent
(`#2C6A56`), amber for a due break, blue for calm/focus, red for an overlay
that has escalated. Rounded type for headings, system sans for body, monospaced
digits for times and metrics.
