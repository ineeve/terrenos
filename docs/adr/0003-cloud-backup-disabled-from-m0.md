# 0003 — Android cloud backup disabled from the first build

- **Status:** accepted (M0)
- **Changes:** PLAN.md (BAK-4 was scheduled for M5, T5.5)

## Decision

The Android backup rules from SPEC.md BAK-4 ship in M0 instead of M5:

- Android 12+: `dataExtractionRules` excludes everything from cloud backup and
  leaves device-to-device transfer allowed.
- Android 11 and older: `fullBackupContent` excludes everything, because those
  versions use the same rules for cloud backup and device transfer.

## Why

Android's default is to upload app data to the user's Google Drive. Waiting
until M5 would have let test data reach a server from the first internal
build, against SPEC.md D1 and the privacy requirements in §10.

## Consequences

On Android 11 and older, moving to a new phone doesn't copy the app's data;
users move it with the backup file (BAK-1) instead.
