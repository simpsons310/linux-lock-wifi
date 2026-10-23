# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single Bash script, `lock-wifi.sh`, that calls itself `wifi-ap`. It wraps NetworkManager's `nmcli` to list the Wi-Fi access points (BSSIDs) of a network and to lock a saved connection profile to one of them by setting `802-11-wireless.bssid`. Unlocking clears that property. It needs `nmcli`; `fzf` is needed only for the interactive paths (the menu, `lock` without `-b`, and `unlock` when not connected).

```txt
./lock-wifi.sh                     # fzf menu
./lock-wifi.sh list [-a] [CONN]
./lock-wifi.sh lock [-b] [CONN]
./lock-wifi.sh unlock [CONN]
./lock-wifi.sh status [CONN]
```

There is no build step and there are no tests. Syntax-check with `bash -n lock-wifi.sh`, and lint with `shellcheck lock-wifi.sh` if it is installed. `lock` and `unlock` change real NetworkManager profiles and reconnect, so they will drop the current Wi-Fi link; `list` and `status` only read.

## Things that span the script

- **Usage text comes from the header comment.** `usage()` prints lines 2–11 of the file. If you change the header comment or add lines above it, update that `sed -n '2,11p'` range.
- **nmcli escaping.** In `-t` (terse) output, a `:` inside a value is escaped as `\:`, and BSSIDs and SSIDs contain colons. `unescape_terse` swaps `\:` for the `SEP` byte (`\x1f`) before the line is split on `:`, and `restore` turns `SEP` back into `:` for each field. `-g` output uses a different escaping, which `unescape_get` handles. Any new `nmcli -t` parsing must follow the same pattern.
- **Data flow for the table.** `scan_aps` emits tab-separated `bssid ssid chan freq signal security inuse`. `render_table` filters on SSID with awk (`$2`), sorts on signal (`-k5,5nr`), and formats rows with `FMT`. `cmd_lock` then takes the BSSID as the text before the first space of the chosen row (`${choice%% *}`), and `-b` takes the first row (the strongest signal). BSSID therefore has to stay the first column of `FMT`, and the scan field order has to stay in step with the awk and sort column numbers.
- **stdout vs stderr.** `info` and `die` write to stderr, so stdout carries only data (table rows, status lines). Helpers are called through `$(...)`, which relies on this split.
- **Errors.** The script uses `set -uo pipefail` without `-e`. Failures are handled explicitly with `|| die ...` or `|| exit 1`, and `resolve_conn` is always called as `conn=$(resolve_conn ...) || exit 1` because `die` inside a subshell exits only that subshell.
- **Connection resolution.** When CONN is omitted, `active_conn` picks the first active `802-11-wireless` profile. `resolve_conn` checks that an explicitly given name exists as a saved profile, using `nmcli -g connection.id connection show NAME`. Do not use `-f NAME` there: in the per-profile detail view `NAME` is not a valid field, nmcli exits with an error, and every name would be reported as missing.

## README.md

`README.md` is the user-facing documentation, written in Vietnamese and meant to be pushed to a public git repo.

- Keep it generic. Use placeholders (`MyCafe`, `AA:BB:CC:00:00:0x`, `<iface>`, `<SSID>`) instead of real network names, BSSIDs, interface names or machine details.
- Headings are numbered (`## 1. ...`, `### 1.1. ...`), and the "Mục lục" list at the top links to each one. When you add, remove, rename or renumber a heading, update the numbering and the table of contents together. Anchors follow GitHub's slug rules: lowercase, Vietnamese letters kept, dots and other punctuation dropped, spaces turned into `-` (for example `### 1.2. Nguyên nhân thường gặp` becomes `#12-nguyên-nhân-thường-gặp`).
- Section 3 (Cách dùng) repeats the command list from the script's header comment. Update both when commands or flags change, and update the examples in section 3.1 when the table output changes.
- Section 6 (TODO) is the roadmap: new commands, a smoother terminal UI, a GNOME UI, and auto-lock through the NetworkManager dispatcher. When you implement an item, tick it off or remove it, and document the feature in section 3.
