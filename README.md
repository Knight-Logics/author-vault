# Knight Logics - Documents Backup

A small, self-repairing backup for a Windows Documents folder, kept separate from the Author Vault app.

* **Current Documents** - an exact, readable copy of Documents as of the last backup.
* **Previous Versions** - older copies of changed or deleted files in dated folders
  (hourly for 2 weeks, then daily for 6 months, then weekly).
* Runs invisibly about every hour while signed in (Task Scheduler + a sign-in repair entry).
* Never moves, changes or deletes the originals. Skips files that are open and retries them.
* Finds the backup drive by a marker file, so a changed drive letter doesn't break it.
* Runs a self-test on sample files before switching anything on.

Install (normal PowerShell window, as the person whose Documents should be backed up):

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072;iex(irm https://raw.githubusercontent.com/Knight-Logics/author-vault/documents-backup/i.ps1)
```

Other commands (run `DocumentsBackup.ps1` from `%LOCALAPPDATA%\KnightLogics\DocumentsBackup`):
`-Mode Status`, `-Mode Backup`, `-Mode SelfTest`, `-Mode Uninstall`.
