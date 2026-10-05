# yDock

A customizable dock for macOS with widgets, profiles and its own look — a personal, Dockset-style app built with SwiftUI and AppKit.

> **⚠️ Beta.** yDock is in an early beta phase. It works day to day on the author's Macs, but expect rough edges, missing polish and breaking changes to the config file between versions. Some features have only been tested on a desktop Mac (see [Known limitations](#known-limitations)).

yDock runs alongside (or instead of) Apple's Dock: a floating panel with your apps, folders and live widgets. It lives in the menu bar, needs no Xcode to build, and is configured from a Settings panel or a plain JSON file.

## Features

**Dock**
- Apps, folders, files and separators; drag to reorder, drop from Finder to add, right-click to remove or reveal in Finder.
- Five positions: bottom, above Apple's Dock, **Notch** (top), left and right. Left/right docks switch to a compact vertical layout.
- **Notch mode:** the dock attaches to the bottom of the menu bar — flat top fused to it, rounded corners only at the bottom, no outline along the join — without covering any menu bar items. It uses the same dark / light / tinted colors as every other position.
- Auto-hide with edge reveal.
- Running-app indicators and hover zoom (both optional).
- Resize handle at the end of the dock: drag to make the whole dock smaller or bigger, double-click to reset. The handle grows and the cursor turns into a resize arrow on hover.
- Overflowing docks scroll item by item with a spring animation: arrows, trackpad or mouse wheel, with soft fading at the edges and settling on the nearest item.
- Appearance: dark, light or tinted (with a color picker), plus adjustable size, spacing and corner radius.

**Widgets**
- Click a widget to open a detail popover (rings, graphs, lists…). Widgets with options have a settings button in the popover, or right-click → *Widget settings…*.
- *Add Widget* gallery with search, categories and live previews.

**Profiles**
- Each profile is its own dock (e.g. Work, Gaming, Reading). A pill next to the dock shows the active profile and switches between them; create, rename and delete from Settings.
- Alarms keep working while another profile is active.

**Settings panel** (right-click the dock → *Dock settings…*)
- Position, auto-hide, size, spacing, corner radius, appearance and tint, hover zoom, running indicators, resize handle, profile switcher, open at login, profiles, language, open/reload the config file, quit.

**Languages:** English, Spanish, French, German, Portuguese, Italian, Japanese and Chinese — or follow the system language.

## Widgets

| Category | Widget | What it does |
|---|---|---|
| Clocks | **Clock** | Time and date; popover shows full date and seconds. |
| | **World clock** | Up to three time zones side by side (`zones` option). |
| | **Stopwatch** | Start / pause / reset from the popover. |
| | **Focus timer** | Work / break timer with a progress ring (`work`, `break` minutes). |
| | **Alarm** | Set a time from the popover; repeat daily, on weekdays or once; system sounds; label; snooze 5 min. Rings across all profiles. |
| | **Time progress** | How far through the year, month or day you are. |
| | **Countdown** | Days (or `HH:MM:SS`) to a date you choose. |
| Calendar | **Calendar** | Today plus your next event; popover lists upcoming events. |
| | **Month calendar** | Compact month grid with today highlighted; popover has month navigation and the selected day's events. |
| Reminders | **Reminders** | Count and titles of reminders due today. |
| Notes | **Sticky note** | A yellow note; click to edit in a small window. |
| | **Notes** | Count and latest titles from Notes.app. |
| Media | **Now playing** | Track and artist from Music or Spotify; click to play / pause. |
| System | **System activity** | CPU and RAM together; popover with rings and memory used. |
| | **CPU** / **Memory** | Individual meters. |
| | **Network** | Live download / upload speed with history graphs. |
| | **Battery** | Mac battery percentage, charging state and time remaining. |
| | **Batteries** | AirPods, Magic Keyboard / Mouse / Trackpad and other Bluetooth accessories. |
| Weather | **Weather** | Current conditions from Open-Meteo (no API key): temperature, feels like, humidity, wind, high / low. |
| Photos | **Photos** | A photo from your library, changing every N minutes or on click (recent or favorites). |
| Stocks | **Stocks** | Price and daily change for a symbol. |
| Tools | **Dropdown** | A button that pops up a menu of apps, folders and links. |
| | **Shortcut** | Runs a Shortcuts.app shortcut; every installed shortcut appears in the gallery. |
| | **AirDrop** | Drop files on it to open the AirDrop sheet; click to open AirDrop. |
| | **Script** | Runs any shell command on an interval and shows its output — handy for revenue, uptime, build status… |

## Requirements

- macOS 13 Ventura or later
- Swift toolchain (Xcode **or** just the Command Line Tools — `xcode-select --install`)

## Build and run

```bash
./build.sh          # builds and signs yDock.app
open yDock.app
```

Turn on *Open at login* in Settings so it starts with your Mac. To hide Apple's Dock, set *System Settings → Desktop & Dock → Automatically hide and show the Dock*.

### Installing on other Macs

```bash
./package.sh        # creates yDock.zip
```

On the other Mac: unzip, run `xattr -cr yDock.app`, move it to `~/Applications` and open it. You can sync the config by symlinking `~/.config/ydock/config.json` to iCloud Drive or Dropbox (app paths must exist on each Mac).

### Code signing and permissions

`build.sh` signs the app with a stable, self-signed identity kept in its own keychain in `./signing` (your login keychain and system trust settings are untouched). This matters: an ad-hoc signature changes on every build, so macOS would forget granted permissions and ask again each time. Delete `./signing` to start over (you will be asked for permissions once more).

| Permission | Used by |
|---|---|
| Calendars | Calendar, Month calendar |
| Reminders | Reminders |
| Photos | Photos |
| Automation (Music, Spotify, Notes) | Now playing, Notes |

## Configuration

Settings are stored in `~/.config/ydock/config.json`. It reloads automatically when you edit it; most options are also available in the Settings panel.

```jsonc
{
  "position": "bottom",          // bottom | aboveSystemDock | top (Notch) | left | right
  "autoHide": false,
  "appearance": "dark",          // dark | light | tinted
  "tint": "#0A84FF",
  "iconSize": 48,
  "spacing": 10,
  "cornerRadius": 22,
  "language": "system",          // system | en | es | fr | de | pt | it | ja | zh
  "activeProfile": "…",
  "profiles": [
    {
      "id": "…",
      "name": "Work",
      "items": [
        { "type": "app", "value": "/System/Applications/Notes.app" },
        { "type": "divider" },
        { "type": "widget", "value": "weather", "options": { "lat": "19.43", "lon": "-99.13", "unit": "c" } },
        { "type": "widget", "value": "script",  "options": { "label": "Uptime", "command": "uptime | awk '{print $3}'", "interval": "60" } }
      ]
    }
  ]
}
```

Config files from the app's earlier name (MyDock, `~/.config/mydock`) are carried over automatically on first launch.

## Known limitations

- **Beta software.** Config format and behavior may change; back up `config.json` if you have a setup you care about.
- **macOS and iPhone widgets can't be embedded.** macOS has no public API for third-party apps to host system or iPhone widgets, so yDock re-implements the equivalents natively.
- **Now playing** works with Music and Spotify only (the system-wide Now Playing API is not available to third-party apps).
- **Stocks** use Yahoo Finance's public chart endpoint, which is unofficial and may change.
- **Batteries**: iPhone battery can't be read from a Mac. The AirPods / accessories reading has not been verified on real hardware (developed on a Mac mini).
- **Reserved screen space:** macOS doesn't let third-party apps shrink the usable screen area, so windows can be maximized under yDock. Use auto-hide if that bothers you.
- The resize cursor uses a private WindowServer call (`SetsCursorInBackground`) because yDock is never the active app. If a future macOS removes it, the cursor falls back to the normal arrow; everything else keeps working.

## Development

Sources live in `Sources/yDock`. Handy launch flags for testing the UI without clicking:

```bash
open yDock.app --args --gallery            # Add Widget gallery
open yDock.app --args --dock-settings      # Settings panel
open yDock.app --args --detail=activity    # a widget's popover
open yDock.app --args --ring               # alarm ringing window
```

Adding a widget: implement the view, register it in `baseWidget` (`Widgets.swift`) and in `WidgetCatalog` (`Gallery.swift`), add its name to `Localization.swift`, and optionally a detail popover in `Details.swift`.

## Status

Beta. Issues and ideas are welcome.
