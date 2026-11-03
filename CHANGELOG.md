# Documents Backup - change log

Newest first.

## 1.0.3
- The hidden Windows links inside Documents ("My Music", "My Pictures", "My Videos") are now
  skipped quietly. In 1.0.2 they were reported as "Couldn't read the folder ... Access denied",
  which marked every run as "needs another try" and would have triggered a reminder after 3 days.
- New self-test check: a junction inside Documents is skipped without errors.
- Removed duplicate console lines in setup output.

## 1.0.2
- The install check now starts the real scheduled task and waits for it to finish a full
  check as the normal (non-admin) account, instead of only confirming it launched.

## 1.0.1
- Fix: a helper was named `LP`, which Windows PowerShell resolves to its built-in alias for
  `Out-Printer`, so setup failed at its first step. Renamed to `ToLongPath`; all function
  names were checked against the built-in aliases.

## 1.0.0
- First version: plain, readable "Current Documents" copy plus dated "Previous Versions",
  hourly hidden scheduled task, sign-in self-repair, marker-based drive detection, self-test.

## Where things live on an installed PC
- Backup folder: `<drive>:\<user>'s Documents Backup\` (Current Documents, Previous Versions,
  Backup Status.txt, Backup History.txt, How to Restore.txt)
- Program + logs: `%LOCALAPPDATA%\KnightLogics\DocumentsBackup\`
- Scheduled task: "Knight Logics - Documents Backup" (hourly + at sign-in, wscript hidden launcher)
- Sign-in self-repair: HKCU Run value `KnightLogicsDocumentsBackup`
- To update: run the one-line installer again; it reuses the existing drive and settings.
