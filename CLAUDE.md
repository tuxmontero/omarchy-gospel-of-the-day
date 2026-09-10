# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An Omarchy (Quickshell/QML) bar plugin that shows the Catholic daily Mass readings from Evangelizo.org. Declared in `manifest.json` as `jonathan.gospel-of-the-day`, kind `bar-widget`, entry point `BarWidget.qml`.

## Commands

```bash
python3 tests/test_evangelizo.py        # backend tests (unittest, no network)
node tests/model-test.js                # pure-JS model assertions
node tests/panel-close-test.js          # Panel.qml close-helper regression
omarchy plugin validate .               # manifest / plugin validation
```

Run a single Python test: `python3 -m unittest tests.test_evangelizo.SecurityTests.test_blocks_non_https_and_other_hosts` (from repo root), or `python3 tests/test_evangelizo.py ParseTests`.

The JS tests use only `node`'s `assert` — no test framework, no `package.json`. They fail by throwing.

Exercise the helper by hand:

```bash
python3 scripts/evangelizo.py --lang SP --date 2026-09-10 --cache-dir /tmp/gcache
```

Install / reload in a live Omarchy session:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable jonathan.gospel-of-the-day --section right
```

## Architecture

Four layers, deliberately separated so most logic is testable without a desktop:

1. **`BarWidget.qml`** — the `✝` bar button. Owns a `Loader` for `Panel.qml` and injects host references into it (`bar`, `settings`, `anchorItem`, `hostWidget`) via `injectPanel()`, re-running on `onBarChanged`/`onSettingsChanged` because the host may set them in any order. Also exposes an `IpcHandler` (`refresh`/`open`/`close`/`toggle`) for `omarchy-shell ipc`.
2. **`Panel.qml`** — all UI and interaction state (`pickerMode`, `activeTab`, `viewDate`, `day`, `loading`, `lastError`). `pickerMode` is `"rite"`, `"language"`, or `""`, and `choosing` is just `pickerMode !== ""`; most of the body is gated on `!root.choosing`. Shells out to the backend through a Quickshell `Process` (`fetchProc`) whose stdout/stderr are `StdioCollector`s; `applyFetch()` parses stdout with `Model.parsePayload` and falls back to stderr text as `lastError`. Copy uses `Quickshell.execDetached(["wl-copy", ...])`.
3. **`Model.js`** — pure JavaScript, shared by QML (`import "Model.js" as Model`) and Node tests via a trailing `module.exports` guard. Holds the rite table (`RITES`, each with nested `languages` of code/name/rtl), date clamping (`MAX_LOOKBACK_DAYS = 30`), payload normalization, and clipboard text formatting. Put logic here rather than in `Panel.qml` whenever it can be expressed without QML types — that is what makes it testable.
4. **`scripts/run-helper.sh` → `scripts/evangelizo.py`** — the network/cache backend. Python standard library only; no third-party deps anywhere in the project.

`SelectableText.qml` is a read-only `TextEdit` used so readings can be selected and copied; `Panel.qml`'s inline `BodyText` component splits text on newlines into one `SelectableText` per paragraph.

Styling comes from the host: `qs.Commons`/`qs.Ui` provide `Style.space()`, `Style.font.*`, `Color.*`, and hover helpers. Don't hardcode pixel sizes or colors — go through `Style`/`Color` and `bar.foreground`/`bar.fontFamily`.

## Security model — preserve these invariants

The backend is intentionally locked down; changes that widen it need a good reason.

- `run-helper.sh` validates `--lang` against an allowlist and `--date` against `^\d{4}-\d{2}-\d{2}$` **before** exec, then runs the Python under `systemd-run --user` with `NoNewPrivileges`, `ProtectHome=read-only`, `ProtectSystem=strict`, `PrivateTmp`, `ReadWritePaths=<cache dir>`, `MemoryMax=64M`, `TasksMax=32`, `RuntimeMaxSec=45`. Panel.qml always invokes the wrapper, never `evangelizo.py` directly.
- `evangelizo.py` re-validates language and date, allows exactly `https://feed.evangelizo.org/v2/reader.php` (checked again on the post-redirect URL), caps responses at 512 KB, and refuses dates in the future or older than 30 days.
- Cache is `~/.cache/gospel-of-the-day/<LANG>/<YYYY-MM-DD>.json`, written atomically via `mkstemp` + `os.replace` at mode 0600. Reads reject symlinks, oversize files, and payloads whose `language`/`date` don't match what was requested.
- Exit codes are part of the contract: 0 ok, 2 usage, 3 network, 4 parse. On network failure a valid cached day is returned instead of an error.
- No network happens until a language is configured (`hasLanguage` gates `loadDay`).

## Keyboard dispatch — a real trap

Keys arrive via the host's `PanelKeyCatcher` (`qs.Ui`), which handles some itself and only forwards the rest to `onTextKey`. It consumes `j`, `k`, `l`, `h` (as `moveRequested`) and `x`/`X` (as `deleteRequested`) **before** `onTextKey` ever sees them. So an `onTextKey` branch for any of those letters is dead code — `Panel.qml` still has one for `"l"`, and `l` works only because `onMoveRequested` routes a nonzero `dx` to `showLanguagePicker()`.

Consequences when touching the keymap:

- Pick shortcut letters outside `j k l h x`. Current bindings: `1` `2` `3` tabs, `r` rite picker, `u` refresh, `c` copy, `t` today, `[` `]` day steps.
- `event.text` is used, so case *is* distinguishable, but this plugin's handlers accept both cases for every letter — keep that convention rather than inventing shift-based bindings.
- Arrow keys and `h`/`l` open the language picker; they do **not** step the day. `[` and `]` step the day.
- Before adding a binding, read the host component (in an omarchy shell checkout, `shell/Ui/PanelKeyCatcher.qml`) to confirm the key actually reaches `onTextKey`. The host QML is not vendored here, and neither `qmllint` nor `omarchy plugin validate` is necessarily installed, so this cannot be caught by running the tests.

## Feed quirks

Evangelizo's XML uses `reading_text1/2/3` for first reading, psalm, and optional second reading, plus `reading_gospel`; each has `_lt` (title) and `_st` (reference) siblings. The liturgical title node is misspelled `litugic_t` upstream — `parse_xml` tries that first and `liturgic_t` as a fallback. When metadata fields come back empty, `apply_fallbacks()` issues extra single-field requests (`type=liturgic_t`, `saint`, `comment_a/s/t`) and strips HTML from them. Fixtures for all of this live in `tests/fixtures/`.

## Rites and language codes

Language is chosen through a rite, not on its own: `RITES` in `Model.js` maps each rite to its languages, and a rite with a single language skips the language picker. `configuredRite` is derived from the stored language code — only `language` is persisted in settings, so the rite is never stored separately.

Internal codes are the feed's, not ISO:

- Roman Ordinary Form: `SP AM FR IT DE PT AR PL NL GR MG` (`AM` = English (US), `SP` = Español, `GR` = Ελληνικά)
- Roman 1962 Missal: `TRA TRS TRF TRD` (English, Español, Français, Deutsch)
- Eastern rites, one language each: `ARM` (Armenian), `BYA` `COA` `MAA` `SYA` (Byzantine, Coptic, Maronite, Syriac — all Arabic)

The full set appears in three places that must stay in sync: `RITES` in `Model.js`, `ALLOWED_LANGS` in `scripts/run-helper.sh`, and `ALLOWED_LANGS` in `scripts/evangelizo.py`. `AR`, `BYA`, `COA`, `MAA`, and `SYA` are RTL and drive `contentAlign`.

## License note

Plugin code is MIT. Liturgical texts and commentaries belong to Evangelizo.org and their authors — don't bundle scripture or commentary data into the repo, and don't redistribute cached text.
