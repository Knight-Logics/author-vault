# Author Vault 1.4

Download the **Author-Vault-Setup.exe** release asset from the Knight Logics repository. Open it and choose **Install / Open Author Vault 1.4**. It includes the entire application; no separate tools, terminal or developer installation is needed on Windows 10/11. The installer creates **Author Vault 1.4** on the desktop.

The alternative **Author-Vault-Universal-Windows.zip** contains the same app. Extract the entire folder and open **Open Author Vault.exe**. Keep the support folder together. The ZIP also includes the Classic compatibility route for Windows 7 SP1/8/8.1, provided the required Windows desktop framework is present. Those older operating systems were not physically tested. The single EXE installer requires .NET Framework 4.5 or newer, included with Windows 10.

## Updating a computer that already has Author Vault

Close existing Author Vault windows. Run the new installer, then use the new **Author Vault 1.4** desktop icon. Do not use the old icon until the update has been saved.

The app loads the existing plan for the current Windows account. Open **Folders & drive**, review the selected paths, add any missing media folders, confirm the connected external HDD, and **Save backup plan**. This copies the new program into its permanent location while preserving the existing recovery passphrase, originals and backup history. Program files that change are retained in a program-history folder. If an update cannot finish, automatic protection stays pending and the error is shown; retry after closing other app windows.

Saving a plan requires a fresh backup and restored-file check. The app deliberately does not silently enable a changed plan.

## Four setup steps — follow the current-step button

1. **Choose folders and a separate backup HDD.** Use **Add Documents + media folders** (Classic: **Add Documents + media**) to include Documents, Desktop, Downloads, Music, Pictures and Videos. Review the actual paths. Files elsewhere, another Windows user's files, Public folders, library locations, camera cards or another internal drive require their own selection. Nothing outside the selected folders is implicitly included. Confirm you are using the correct Windows account, that documents are saved and closed, and that you have recorded the recovery passphrase separately. Save the plan.
2. **Back up selected folders.** Wait for completion. Review the per-folder file, music, image and video counts. An empty selected folder no longer blocks a backup when other selected folders contain files. A plan with no saved regular files cannot complete setup. Unknown file types are still backed up; media categories are counted by extension.
3. **Restore a file to check.** The current-step button selects a saved file automatically, restores it into a new folder and compares its bytes with the original. Open the restored copy in its normal application and check its contents. You may also use **Verify a restored file** to select a specific manuscript or media file. Do not edit the original during this check.
4. **Enable and test the schedule.** Confirm that you opened the restored copy. The app registers its Windows tasks, reads back their actual definitions, and asks Windows to launch the registered backup task in a harmless probe. Setup reports success only after a fresh receipt from that task. This probe checks task launch, not another full backup. The actual scheduled-backup path was also tested with synthetic files in both modes.

**A manual backup does not enable daily scheduling.** The overview now shows the current step and whether the schedule is enabled. In **Protection & help**, use **Check schedule** to read the actual Windows registration or **Test Windows task launch** to verify launch. Use **Resume / check now** to repair this app's own missing, disabled or changed tasks.

## Where are the files on the HDD?

Backups are encrypted archives, not ordinary browsable copies of the Music/Pictures/Videos folders. You will not see normal JPG/MP3/MP4 files in the backup repository. Use **Restore & history**, select the folder/version, and restore into a NEW folder to see and open normal files again.

Modern mode uses a Kopia filesystem repository. Classic mode uses dated encrypted `.7z` archives. These formats differ; keep the app and recovery passphrase. The launcher keeps an existing Classic plan in Classic so it does not silently switch archive formats. A modern plan cannot be recovered by the Classic archive reader. Each computer has its own plan; sharing a backup HDD does not merge their settings.

## Why are the interfaces different?

The title/account area shows **1.4**, Windows/build, bitness, and the selected mode. Windows 10/11 with 64-bit Windows normally uses modern mode. 32-bit Windows or older compatible installations use Classic. A modern component compatibility failure is explained before Classic opens, and an existing modern plan is not silently switched to a different archive engine. CPU speed, installed RAM and BIOS date do not choose the interface.

## Daily use and recovery

Keep the PC on and awake, the same Windows account signed in (a locked screen is fine), and the same external HDD connected and unlocked. It cannot back up while the PC is off or asleep. Sign-in/catch-up and the lightweight monitor retry recoverable conditions. Drive disconnection, full or failing storage, denied permissions, missing local files or a stopped Windows service can still require attention; no software can guarantee that hardware never fails.

Save and close applications before the first full backup and recovery test. Unsaved edits, online-only placeholders and files outside selected folders are not ordinary saved local files. Download online-only files locally first. Links and junctions need their actual data location selected; the inventory flags unresolved links, and Classic refuses them rather than silently claiming their target data was copied. Disk or file-access errors are shown rather than marked successful.

Originals are not moved, mirrored or automatically deleted. Historical backup versions are not pruned to clear space. Recovery writes new folders and refuses to overwrite originals. Classic creates full archives and can consume more disk space; a larger HDD may eventually be needed. The app never formats a drive.

Keep the recovery passphrase separately: losing the PC's saved Windows credential without the passphrase can make encrypted backups unrecoverable. It is protected locally with Windows DPAPI; it is not placed in task arguments. There is no cloud backup or manuscript upload. Downloading the app from GitHub uploads none of your files or settings. Public release files contain program files and documentation only.

## If setup fails

Read the visible error before retrying. Confirm the correct account, external HDD identity, free space and saved local folders. For step 3, choose a saved file INSIDE a protected folder, or use the automatic current-step button. For step 4, check that Windows Task Scheduler is available and that the account may create its own tasks. The app does not need the Windows login password for scheduling and does not ask you to disable Windows security.

Do not call setup complete while it shows an error or pending step. Manual **Back up now** remains available if activation fails. In modern mode, **View local logs** opens the local diagnostic files. In Classic, **Open installed folder** contains `state`, including the actual task definition and readable status. Reports can contain local filenames, so review them before sharing; never share `password.dpapi` or the Classic `plan.xml` credential.

The executable is not digitally signed. Windows may show an unknown-publisher/SmartScreen notice; verify the official release and published SHA-256 checksum. Do not disable antivirus or run a package whose identity you cannot verify.

## Locations

- Packaged application: `%LOCALAPPDATA%\KnightLogics\AuthorVaultPackages\1.4.0`
- Modern installed runtime/settings: `%LOCALAPPDATA%\KnightLogics\LocalAuthorBackup`
- Classic installed runtime/settings: `%LOCALAPPDATA%\KnightLogics\AuthorVaultClassic`
- Modern HDD data: `KnightLogics-Author-Backups\<unique plan location>`
- Classic HDD data: `KnightLogics-Author-Classic\<unique plan location>`

Do not delete these locations while relying on the backup. The download/installer itself can be removed after the installed app has been tested and all four setup steps have finished.

## Third-party engines

The package includes unmodified [Kopia 0.23.1](https://github.com/kopia/kopia/releases/tag/v0.23.1) and [7-Zip 26.05](https://github.com/ip7z/7zip/releases/tag/26.05), with their license/provenance files. Engine hashes are checked before use. Original upstream source and license terms are available at those links.
