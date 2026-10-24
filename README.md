# Author Vault — Windows download

**[Download Author-Vault-Setup.exe](https://github.com/Knight-Logics/author-vault/releases/latest/download/Author-Vault-Setup.exe)**

Close Author Vault and let any backup finish. Open this download and choose **Install / Open Author Vault 1.5** once. Then use the **Author Vault** desktop icon. The installer includes the full app; Windows 10/11 users need no developer tools or separate support-folder setup.

[Full ZIP alternative](https://github.com/Knight-Logics/author-vault/releases/latest/download/Author-Vault-Universal-Windows.zip) · [Release notes and checksums](https://github.com/Knight-Logics/author-vault/releases/latest) · [Full instructions](USER-GUIDE.md)

## What version 1.5 changes

- Future signed updates install automatically while Author Vault is closed and no backup is running. A small watcher checks the official release about once daily, independently of whether backup setup has finished.
- Program updates preserve the folder plan, recovery passphrase, restore verification, enabled/paused state, backup history and registered Windows task. Program replacement has checksum checks, a rollback copy and an interruption journal.
- **Updates & status for Nick** lets you check/install updates and copy a report covering version, backup time, schedule/launch verification and update status. No filenames, source paths, passwords or file contents are included or sent automatically.
- Recovery of files ending in `.zip`, `.tar` or similar names uses normal file output instead of letting the engine infer archive output from the filename.
- All saved regular file formats are included inside selected folders. Music, Pictures and Videos need their actual folders selected if outside Documents. Unknown extensions and files without extensions are included too.

**Install 1.5 manually once to add the automatic updater.** Older copies cannot acquire a feature they do not yet have. Update downloads require internet; backups remain local and work offline. The first installer remains unsigned by Authenticode; the updater's pinned RSA signature verification is separate.

## First setup or adding missing folders

1. Select document AND media folders and a separate external HDD. Save the plan and record the recovery passphrase separately.
2. Back up. Review per-folder file and media counts.
3. Restore a file, open the restored copy and check it.
4. Enable daily protection. The app reads back Windows' task definition and verifies an actual task launch before reporting success.

**Manual backup alone does not enable scheduling.** Follow the current-step button. Adding folders changes the plan and requires a fresh backup and recovery check; a program-only update preserves existing activation.

Use **Check schedule** and **Test Windows task launch**, then **Updates & status for Nick → Copy status for Nick** to share results privately. No automatic client telemetry is collected.

## Validation and limits

376 automated checks passed across encryption/recovery, mixed media and arbitrary file formats, original-file preservation, actual Windows task registration/launch/repair, native GUI flow, installer extraction, program upgrades and signed-update rejection/rollback safeguards. The upgrade tests preserved daily task definitions and launched both upgraded worker modes through Windows. The isolated idle update watcher used about 32 MB of memory in the installer trial.

Tests used synthetic data on current Windows, including the x86 Classic app. Stephen's exact computers and older Windows installations were not physically tested. The app cannot back up an off/asleep PC, an absent/unlocked-required HDD, unsaved edits or online-only files that have not been downloaded. No software can guarantee hardware or Windows never fails. Keep the account signed in, the HDD connected/unlocked and the recovery passphrase separately; maintain another independent copy.

Originals and old versions are preserved. Restore creates new folders. The app never formats drives or prunes backup history to clear space. The HDD contains encrypted archives, which are recovered through **Restore & history**.

Modern mode normally serves Windows 10/11 x64. Classic serves 32-bit/older compatible installations and existing Classic plans. The modes use different interfaces and archive formats. BIOS age and RAM do not choose the mode. See the guide for compatibility and upstream engine licenses/source links.

This repository distributes only releases and user instructions. Client files, credentials and development-only materials are not uploaded. Built by Knight Logics.
