# LinkMover

[中文 README](README.md)

LinkMover is a compact macOS utility for moving large folders to an external drive or another location, then creating a symbolic link at the original path so existing tools and workflows continue to work.

Background: internal storage on work machines is often limited, while development environments can consume a large amount of disk space. This tool helps offload heavy folders to an external SSD and reduce pressure on the internal disk.

## UI

![screenshot](/Volumes/Ext/CodeE/Code_Lab/Dev_Tools/LinkMover/screenshot.png)

## Features

- Select a source folder and a target parent folder
- Preview the final destination path and migration commands
- Check whether the folder exists, is writable, and whether free space is sufficient
- Block migration of critical system paths
- Request administrator privileges when needed
- Automatically create a symbolic link after migration
- Provide logs, rollback, and symbolic-link recreation
- Support both Chinese and English UI

## Typical Use Cases

- Move Xcode-related caches or device support folders to an external SSD
- Relocate large development folders to another disk
- Preserve the original path so existing tools and scripts do not need changes

## How to Use

1. Open the app and choose the source folder to migrate.
2. Choose the target parent folder.
3. Confirm the final folder name, preflight checks, and permission hints.
4. Click `Start Migration`.
5. After migration, the original path becomes a symbolic link to the new location.

If symbolic-link creation fails after the move, the app provides actions to restore the original location or recreate the symbolic link.

## Notes

- Direct migration of the root directory and core system folders is not supported.
- If the target path already exists, the current version blocks the operation for safety.
- Make sure no application is actively using the folder before migration.
- macOS may prompt for administrator authentication when protected locations are involved.

## Build

Open [LinkMover.xcodeproj](/Volumes/Ext/CodeE/Code_Lab/Dev_Tools/LinkMover/LinkMover.xcodeproj) in Xcode and run the `LinkMover` scheme.
