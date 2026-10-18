# Keyboard-only and Reduce Motion checks (item 9)

What the automated gates prove, and what still needs a person at a real keyboard. Run part B and C before a release
and after any change to a control style, a chart, the calendar, the card or an animation. Takes about 20 minutes.

## A. What is already checked automatically

| Check | Where | What it proves |
|---|---|---|
| `motion through tokens` | `scripts/ci.sh` | Every `withAnimation` / `.animation(` goes through `theme.motion(<MotionToken>, reduceMotion:)`; animation curves live only in `Tokens.swift`; every `TimelineView` pauses under Reduce Motion; nothing reads the system's Reduce Motion setting except `ReduceMotionRoot`. |
| `keyboard reachable` | `scripts/ci.sh` | No `.buttonStyle(.plain)` (use `PixelPlainButtonStyle`, which draws the focus ring); `.focusEffectDisabled()` only where the pixel ring is drawn; every tap gesture is on a view that takes focus and answers keys; every hover readout is also reachable with `chartKeyboard` (decorative hover is marked `hover-ok`). |
| `Theme` tests | `Tests/DesignSystemTests` | Under Reduce Motion every motion token is nil except the card flip, which is a crossfade of at most 0.25 s; the window root's override reaches views. |
| `KeyboardTests` | `Tests/ClepsoAppTests` | The chart cursor starts at the latest bar and holds at the ends; the calendar cursor moves by day and week over days with data only and walks a real year end to end. |

Probe evidence (debug build, no key events are ever posted; see `Sources/ClepsoApp/Debug/PopoverProbe.swift`):

- `-ClepsoProbeAX YES` with `swift scripts/probe-ax.swift <dir>`: the accessibility tree of every popover page,
  Dashboard page, the delete-all sheet and every onboarding step, read-only, with counts of controls that offer
  AXPress (Return/Space/VoiceOver can activate them) and AXIncrement (adjustable). It also lists the app menu's key
  equivalents (⌘, Settings…, ⌘W Close).
- `-ClepsoProbeFlipFrames YES` (add `-ClepsoProbeReduceMotion YES` for the reduced run): six frames of the player card
  turning over.
- `-ClepsoProbeFocusGallery YES`: every self-drawn control focused in turn through `@FocusState`, captured. Buttons and
  toggles take focus only while **Keyboard navigation** is on in System Settings, which the probe cannot turn on for
  itself; run it with the setting on to see every button's ring.

## B. Keyboard only

Setup: System Settings › Keyboard › **Keyboard navigation** on. Put the mouse aside for the whole section. In each
place below, press Tab repeatedly (Shift-Tab back) and check:

- [ ] **Every control is reached**, in reading order (left to right, top to bottom), and nothing invisible takes a stop.
- [ ] **The focused control is obvious**: a pixel frame in the theme's accent colour around it. Note it if you see a
      second, rounded system ring as well (a double ring), or none at all; say which control.
- [ ] **Space activates** a focused button or switch; **Return** activates the default (lit) button of a sheet or
      onboarding step.

### Popover (click the menu bar icon, then use only the keyboard)

- [ ] Tab reaches: EXIT DEMO (demo only), the CLAUDE CODE plan button, each limit card, DASHBOARD, refresh, QUIT.
- [ ] Space on the CLAUDE CODE button opens provider detail; Tab reaches ‹ AI CAPACITY, each limit row, the coverage
      chip, OPEN USAGE, CHANGE PLAN, QUIT.
- [ ] Space on a limit card opens the inspector; Tab reaches ‹ AI CAPACITY and COPY DETAILS.
- [ ] **Escape steps back** one level: inspector → detail (or overview) → overview → popover closes.
- [ ] ⌘, opens the Dashboard on Settings.

### Dashboard (each page from the sidebar)

- [ ] Sidebar: Tab reaches every section and the plan badge at the bottom; Space opens the section; the selected one
      stays lit.
- [ ] Home: every button; the daily bars chart takes focus (pixel frame round the chart); **← →** move a lit bar and
      the line under the chart reads its date and value.
- [ ] Limits: Add to calendar buttons.
- [ ] Session: each session row (Space chooses it), the buttons.
- [ ] Overview, All time: the range control (ALL TIME / 30 DAYS / 7 DAYS); the year arrows; the calendar takes focus as
      **one** stop (pixel frame round it): the first arrow chooses the latest day and its facts appear below; ← → move a
      week, ↑ ↓ a day; days without data are skipped; CLEAR is reachable. Then the hours chart (← → per hour).
- [ ] Overview, 30 days: the month calendar: ← → move a day, ↑ ↓ a week. The tokens chart and the hours chart by
      arrows. 7 days: the tokens chart.
- [ ] Models: both segmented controls; Chart view: the chart by arrows (date and per-model tokens in the line under it).
- [ ] Card: the card itself takes focus (pixel frame); Space or Return flips it; SAVE PNG…, COPY IMAGE, SHARE…, SHOW
      BACK.
- [ ] Goals: each switch (ON/OFF) and each stepper (↑ ↓ change the value).
- [ ] Account: the name field, CHANGE (plan sheet), the email field and its button.
- [ ] Settings: every theme swatch, every switch, every button down to the diagnostics log.
- [ ] Sheets (plan, Agents per task, Delete all Clepso data): focus starts inside the sheet; Tab stays inside it;
      **Escape closes it** (Cancel); Return triggers the lit button only where that is safe (never Delete).
- [ ] **⌘W closes the Dashboard**; ⌘, reopens it on Settings.

### Onboarding (first launch; for a rerun, launch a debug build with a fresh `-ClepsoDataDirectory`)

- [ ] Each step: Tab reaches every button, the plan menu, the switches; Return takes the lit primary button.
- [ ] The last step: the Launch at login switch, then OPEN.
- [ ] ⌘W closes the window.

### VoiceOver spot check (⌘F5)

- [ ] A chart reads its summary, then its current value; VO-Shift-↑/↓ (or the adjust gesture) steps through bars.
- [ ] A calendar day reads its date and counts, is announced as a button, and VO-Space chooses it.

## C. Reduce Motion

Setup: System Settings › Accessibility › Display › **Reduce motion** on.

- [ ] Card page: hover the card: it does **not** tilt, lift or glow. Flip it (click, Space or SHOW BACK): the faces
      **crossfade in place**, no turning.
- [ ] Models › Arena: the pixel characters stand still (no bob).
- [ ] Popover detail: the coverage chip shows and hides its sentence at once, without a fade.
- [ ] Nothing else in the popover, Dashboard or onboarding slides, zooms or bounces (system sheet and window animations
      follow the system's own setting).
- [ ] Turn Reduce motion off again: the card tilts and turns over, the characters bob.

## Known gaps

- The small activity grids that only show a tooltip (the card's back, the Goals week, the Home and Account
  calendars) are not keyboard stops; their numbers are in each square's VoiceOver label and elsewhere on the page.
- The loading spinner shown while the statistics file is read is the system's own and keeps spinning under Reduce
  Motion (it is brief and conveys status).
