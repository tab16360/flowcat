# FlowCat User Guide

[简体中文](guide.zh-CN.md)

FlowCat runs on Apple Silicon Macs with macOS 13 or later. Each Mac records its own traffic and disk activity.

## Install and first run

1. Drag FlowCat into the Applications folder in Finder.
2. Open it. FlowCat lives in the menu bar only and has no Dock icon.
3. Click the cat in the menu bar to open the panel. Right-click (or Control-click) the cat for a quick menu: open the panel, pause or resume, menu bar options, Launch at Login, export, Settings and Quit.
4. Turn on **Launch at Login** in the More menu (⋯) or in Settings (⌘,) so recording starts after you log in. If macOS asks you to approve the login item, confirm it in System Settings.
5. Use **Export CSV** to save history for Numbers or Excel.

To uninstall, turn off Launch at Login, quit FlowCat and move the app to the Trash. Keep the history folder if you might reinstall.

## The panel

The panel has three tabs: **Network**, **Disk Activity** and **Disk Health** (⌘1, ⌘2, ⌘3). ⌘F focuses search, Esc closes the panel.

- The bell in the header opens **Disk Write Alerts**. A dot means alerts fired today.
- The More menu (⋯) holds Pause Recording, menu bar options, Include LAN in Totals, Launch at Login, exports, Settings, Check for Updates and Quit.
- While recording is paused a banner at the top says so, with a Resume button.
- Hover a ranking row to reveal ⋯ for **Show in Finder** (and, on disk rows, **Write Alert Settings…**). Right-click works too. Click a disk row to expand its path.
- Explanations live behind the ⓘ buttons.

## Settings

Open Settings with ⌘, or from the More menu.

- **Menu Bar:** show today's total, network speed and disk read/write speed independently. Changes apply immediately. By default only the icon and network speed are shown.
- **Network:** Include LAN in totals (see below).
- **General:** Language (System default, English or 简体中文), Launch at login, Disk write alerts, version and Check for Updates.
- **Sponsor:** opens the GitHub Sponsors page.

## Menu bar readout

"Today" is the sum of upload and download across all networks today and follows the Include LAN setting; with LAN excluded and no estimate yet it shows "—". When total and speed are both on they stack in one column; disk read and write get their own column. The item measures a fixed-width template so it doesn't shift as numbers change.

## Updates

Choose **Check for Updates**. When a new version is available, choose **Install and Relaunch**. FlowCat downloads, verifies and replaces itself, then relaunches; history and settings are kept and the download can be cancelled.

- FlowCat checks the official URL, download size, SHA-256, ZIP paths, app identity, version and code signature. Once a signing team is established it refuses a different team or an unsigned build.
- The updater waits for the new version to confirm it started. If replacing or launching fails, the previous version is restored. A copy of the previous app is kept at `~/Library/Caches/local.gww.trafficledger/Updates/previous.app`.
- The install folder must be writable. If FlowCat runs from a disk image, App Translocation or a read-only folder, move it to Applications first. FlowCat never asks for admin rights.
- Version 1.3.x can only update through the browser; install 1.4.0 once, then in-app updates work.
- Checks only happen when you ask and only contact GitHub. FlowCat is ad-hoc signed; these checks are not Apple notarization.

## Include LAN in totals

The setting is in the More menu, the menu bar right-click menu and Settings. It is on by default and saved automatically. When off, the total shows a "LAN excluded · estimate" label. It only affects totals; app and proxy rankings always show full counters.

When off, recognized LAN bytes from the same sampling interval are subtracted from the physical interface counters, clamping download and upload at zero separately. LAN traffic is recognized from the physical interface subnets plus private and link-local addresses. It does not depend on Clash, proxy APIs or any third-party configuration.

This is an estimate: short connections, protocol overhead and traffic inside a VPN may remain, so it is not a precise internet total or a carrier bill. LAN-excluded totals are recorded from version 1.5.4; older history is not recalculated.

## Wi-Fi networks

- Networks use the real Wi-Fi SSID. There are no preset categories, renames or manual labels.
- If FlowCat can't read the Wi-Fi name and macOS hasn't decided yet, it requests location permission, which macOS uses to gate SSID access. You can decline. FlowCat never requests or stores coordinates.
- Without permission, on Ethernet or when reading fails, FlowCat shows "All networks" only and keeps recording.
- The network menu lists All networks, the current Wi-Fi first and every recorded SSID.
- Intervals that span a network switch are skipped to avoid mixing networks, so up to one sample may be missed.
- If several physical interfaces carry traffic in the same sample, it only counts toward All networks.

## What the network numbers mean

- **Totals** are deltas from the `en*` interfaces (Wi-Fi, Ethernet, USB networking). `lo0` and VPN tunnels are excluded to avoid double counting.
- **Apps and proxies:** apps are shown by default; recognized proxy cores and VPNs have their own list. The split is display-only; history, filters, raw counters and CSV are unchanged. Unrecognized relays may still appear as apps, and the two lists must not be added together.
- **Per-process data** comes from `nettop`. When a path is available, an app's helper processes are merged into the app.
- Process data may include loopback, proxy and VPN relays, so **ranking rows don't add up to a billable total**.
- FlowCat samples every 10 seconds, saves every minute and saves again on quit. A crash can lose up to the last minute.
- **Only time FlowCat is running and not paused is recorded.** Earlier, quit and sleep periods can't be recovered.
- The first 10 seconds build a baseline. Short-lived processes and counter resets can be missed; this is sampling, not a billing audit.
- Day boundaries are accurate to about one sample and follow the Mac's time zone. "Recorded" shows real sampling coverage.
- Hourly charts start with version 1.7; earlier hours show as gray.

Proxy history cannot be split back into the original apps because only per-process totals are stored.

## Disk activity and health

Choose **Disk Activity** or **Disk Health** at the top. Disk activity covers today, 7 days, 30 days, all time and any single day; the arrows next to the calendar step one day at a time, and the selected day appears in the period control. Processes are sorted by writes by default; you can search, change the sort, click a row for its path and export the current period as CSV. Disk history is stored separately in `disk-ledger.json`.

Process counters cover all disks with app helpers merged. Only observed deltas are counted; the first run builds a baseline and sleep, pauses and missed samples are never filled with zeros. Some system and short-lived processes can't be fully covered.

Disk health is shown per physical disk, with whatever fields the hardware provides. "Not provided" is not a fault and is never shown as 0. "SMART OK" is the drive's own report, not a guarantee; rated endurance used is not remaining life. Lifetime host writes and FlowCat's process writes measure different things and shouldn't be subtracted from each other. External drives depend on the enclosure. No third-party drivers or disabled protections are needed.

Health data is read on demand, then about every 10 minutes, or when you click Refresh. Pausing stops process sampling but you can still read health data.

## Disk write alerts

Open alerts from the bell, the More menu, ⋯ on a disk row or the menu bar right-click menu. Alerts are off by default; once on, they reuse the existing 10-second sampling. System notifications are optional; alerts are kept in the window either way.

- **Sustained writes:** default 1 MB/s. At least 9.5 of the last 10 full minutes must be observed, at least 8 of them above the threshold, with continuous sampling. Sleep, pauses and missing counters never count as recovery.
- **Hourly budget:** default 2 GB per app, counting only writes observed in the last hour.
- **Daily budget:** default 10 GB per app, including today's history. Alerts once per local day.
- Any rule can be turned off. Each app can use custom thresholds and be set to **On**, **Pause 1 hour** or **Mute**. Changing settings restarts the minute window; history is unchanged.
- No repeated notifications in one episode. Sustained and hourly rules re-arm after 5 minutes below the threshold and at least 1 hour since the last alert; cooldowns survive restarts.
- Curves are kept per app path for the last hour only, for up to 512 recently writing apps. Gray gaps mean "not observed", not zero.

An alert only means observed writes crossed a threshold. It can't prove wasted writes, failed syncs, disk damage or which files were written. Minute curves are cleared when FlowCat quits; daily totals remain. Only settings, the latest 40 alerts and cooldowns are saved. FlowCat never tracks file names or contents.

## Data and privacy

All history stays on your Mac:

```
~/Library/Application Support/流量账本/ledger.json
~/Library/Application Support/流量账本/disk-ledger.json
```

The folder name is kept from earlier versions so upgrades keep your data. No account, no upload, no traffic contents, and no changes to proxies, firewalls or connections.

## Building from source

`Sources/` contains the Swift code and a small native IOKit C bridge. With the Xcode Command Line Tools installed:

```sh
bash scripts/build.sh
bash scripts/test.sh
```
