# Gospel of the Day

A Catholic Omarchy bar plugin for the daily Mass readings: first reading, psalm, optional second reading, Gospel, and commentary.

It is meant for everyday use — a quiet place on the desktop to pray with the liturgy of the day.

Readings come from **[Evangelizo.org](https://www.evangelizo.org)** (Evangelio del día / Daily Gospel) through the official Reader Evangelizo feed. Scripture and commentary remain the property of their authors and of Evangelizo. This plugin does not bundle a Bible or commentary database.

## Features

- Latin cross on the Omarchy bar; the panel opens under the icon
- Liturgical title plus the saint or celebration of the day
- Readings, Gospel, and Commentary as separate tabs
- Select and copy the readings, or copy the open tab
- Several Catholic calendars: Roman Ordinary Form, Roman 1962 Missal (Extraordinary Form), Armenian, Byzantine, Coptic, Maronite, and Syriac
- Roman Ordinary Calendar languages: Español, English (US), Français, Italiano, Deutsch, Português, العربية, Polski, Nederlands, Ελληνικά, Malagasy; the 1962 Missal in English, Español, Français, and Deutsch
- Arabic and other right-to-left text is shown right-to-left
- Previous / next day (up to 30 days) and a Today button
- Rite and language chips always visible
- Local cache for the current day; refresh when you ask for it
- No network until a rite and language are chosen

## Install

From this folder:

```bash
omarchy plugin validate .
omarchy-shell shell rescanPlugins
omarchy plugin enable jonathan.gospel-of-the-day --section right
```

Or add the git repository with `omarchy plugin add <git-url>` and enable it when you are ready.

## Use

Click ✝ to open the panel. The first time, pick a rite, then a language (rites with a single language skip that step). Switching rite keeps your language when the new rite offers it. After that:

| Input | Action |
| --- | --- |
| Click ✝ | Open or close |
| Rite chip | Change rite |
| Language chip | Change language |
| Today | Jump to today |
| Refresh | Fetch again, skip cache |
| Copy / `c` | Copy the open tab |
| Middle-click ✝ | Refresh |
| `1` `2` `3` | Readings, Gospel, Commentary |
| `j` `k` / ↑ ↓ | Scroll, or move the cursor in a picker |
| `l` `h` / ← → | Language list |
| `r` | Rite (calendar) list |
| `[` `]` | Previous or next day |
| `t` | Today |
| `u` | Refresh |
| Escape | Close |

Source line in the panel: **Evangelizo.org**.

## Cache

Daily JSON is stored at:

```text
~/.cache/gospel-of-the-day/<LANG>/<YYYY-MM-DD>.json
```

Opening the panel uses the cache when it exists. Refresh bypasses it. If the network fails, a saved copy is shown when available.

## Develop

```bash
python3 tests/test_evangelizo.py
node tests/model-test.js
omarchy plugin validate .
```

The backend is `scripts/evangelizo.py` (Python standard library only). It talks only to `https://feed.evangelizo.org`.

## License

Plugin code is MIT. See [LICENSE](LICENSE).

Liturgical texts and commentaries are provided by Evangelizo.org and are not covered by that license. Do not redistribute those texts from the cache as if they were part of this project.
