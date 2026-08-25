# ResidueSweep

ResidueSweep is a focused, open-source Windows cleanup tool for caches and
residual files that are easy to miss in normal storage settings.

It scans first, shows the exact paths and estimated space, and only cleans the
latest reviewed snapshot. Recoverable files are moved to a quarantine folder
under `%LOCALAPPDATA%\ResidueSweep\Quarantine` before they can be permanently
deleted.

## Highlights

- User and Windows temporary files
- Windows Update and Delivery Optimization caches
- DirectX and NVIDIA `DXCache`, `GLCache`, and `NV_Cache`
- Thumbnail, icon, Recent Items, and Jump List caches
- Crash dumps, WER reports, diagnostic and setup logs
- Browser cache, GPU cache, code cache, and service-worker cache
- NuGet, npm, pip, and Yarn download caches
- Microsoft Store, DNS, ARP, font, and clipboard cache actions
- Recycle Bin reporting by drive
- Detection-only checks for installer orphans, old drivers, downloads,
  recovered fragments, and uninstall residue
- Traditional Chinese and English interface with light and dark themes

## Run

Double-click `ResidueSweep.cmd`. Windows may request administrator approval so
the app can inspect protected system locations. The launcher opens the GUI
directly.

## Safety model

1. Select cleanup areas.
2. Run a read-only scan.
3. Review every path and estimated size.
4. Confirm cleanup.
5. Restore the latest quarantine if needed.

Locked files and configured exclusions are skipped. Detection-only findings
are never automatically removed. Recycle Bin cleanup is the one explicitly
irreversible action and requires confirmation.

RAMMap memory release is optional and requires the official Sysinternals
`RAMMap.exe` in `Tools`, or in a standard Sysinternals installation path.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1

## Attribution and license

ResidueSweep is MIT licensed. Its initial cleanup and safety core was derived
from the MIT-licensed Win11Debloat project by Raphire and the independently
developed WinWin cleanup work. See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).
