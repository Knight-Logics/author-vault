# Author Vault — Windows download

**[Download Author-Vault-Setup.exe](https://github.com/Knight-Logics/author-vault/releases/latest/download/Author-Vault-Setup.exe)**

Open the download and choose **Install / Open Author Vault 1.4**. It includes the full app and creates an **Author Vault 1.4** desktop icon. Windows 10/11 users do not need to install developer tools or manage support folders.

[Full ZIP alternative](https://github.com/Knight-Logics/author-vault/releases/latest/download/Author-Vault-Universal-Windows.zip) · [Release notes and checksums](https://github.com/Knight-Logics/author-vault/releases/latest) · [Instructions and troubleshooting](USER-GUIDE.md)

## Updating an existing installation

Close older Author Vault windows, open the new version, review **Folders & drive**, and **Save backup plan**. Add missing Music, Pictures and Videos folders. Existing passphrase, originals and backup history are preserved. Follow the current-step button through backup, restored-file verification and scheduling again.

## Four setup steps

1. Select the actual document AND media folders and a separate external HDD. Save the plan and record the recovery passphrase separately.
2. Back up. Review the per-folder music/image/video counts.
3. Restore a file and open the restored copy to check it.
4. Enable daily protection. The app verifies Windows' actual task definition and an actual task launch before reporting success.

**A manual backup alone does not enable scheduling.** The updated interface shows the current stage and what remains.

The HDD contains encrypted archives; normal JPG/MP3/MP4/documents are recovered through **Restore & history**. They are not ordinary browsable mirror copies on the HDD.

## Version 1.4 improvements

- Media-folder selection in both interfaces, per-folder file/type counts, and support for empty selected folders when the plan contains other saved files.
- A guided restore check that advances from stage 3 to scheduling.
- Read-back of actual Windows tasks, task-launch testing, and detection/repair of changed daily schedules.
- A self-contained installer with embedded-package and extracted-file integrity checks.
- Clear version/mode identification and preservation of existing plans/history during updates.

303 automated checks passed across backup safety, mixed-media recovery, task registration/launch/repair, native GUI flow, final ZIP extraction and the installer. Both backup modes completed actual scheduled backup and recovery using synthetic files. Tests ran on current Windows, including the x86 Classic app. Actual Windows 7/8 hardware was unavailable; see the guide for compatibility limits.

## Privacy and security

Only application downloads and documentation are distributed here. No manuscripts, media, client settings or passwords are uploaded. Backup contents stay local and encrypted; saved credentials use Windows DPAPI. Originals and old versions are preserved. Restores create new folders. The app does not format drives or prune history to clear space.

Keep the PC awake, the same account signed in and the HDD connected/unlocked. Missing/full/failing drives, unsaved edits, online-only files or Windows permissions can still require attention. Keep the recovery passphrase separately. No software can guarantee that hardware never fails.

The executable is currently unsigned. Verify the official release and SHA-256 checksums. Do not disable antivirus to run an unverified file.

Modern mode normally serves Windows 10/11 x64. Classic serves 32-bit/older compatible installations and existing Classic plans. The interfaces and archive formats differ; BIOS age and RAM do not choose the mode. Full details, dependencies, third-party licenses and upstream engine source links are in the guide and package.

Built by Knight Logics. This repository distributes releases and user instructions; development source is maintained separately.
