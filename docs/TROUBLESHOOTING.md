# Troubleshooting

## Status says Folder Access Needed

Open Settings and choose the screenshot folder again. Use Shift-Command-5, open Options, and confirm the destination macOS is using. Timestamp Only cannot silently recover access to a different folder because the sandbox requires an explicit selection.

## A new file was not renamed

Confirm that Timestamp Only says Running, that the file appeared directly inside the selected folder after monitoring began, and that it was created by Apple's screenshot tool. Existing files, files created while paused, files inside subfolders, third-party images, and files without the positive Apple capture marker stay untouched.

Screen recordings are intentionally excluded. Still screenshots with a verified marker can use PNG, JPEG, TIFF, HEIC, other still-image types recognized by macOS, or PDF.

If macOS writes the file and its metadata in several steps, the app waits for stable size and filesystem dates and retries briefly for a delayed capture marker. A later relevant filesystem event can reconsider a candidate after retries expire.

## Launch at login needs approval

Click Open Login Items Settings in Timestamp Only Settings, enable Timestamp Only in the macOS Login Items panel, and reopen Settings to confirm the state. Apple requires user approval for some login-item changes.

## A filename format is rejected

Read the inline error and preview. Avoid `/`, `:`, control characters, hidden names, and surrounding whitespace; ensure the format produces more than `.` or `..`; and shorten long literal text. The last valid setting remains active until the new format is valid.

## A volume does not support safe renaming

Timestamp Only requires exclusive rename support so it can guarantee that an existing destination will not be replaced. If a selected network, removable, or unusual filesystem does not support `RENAME_EXCL`, choose a supported local folder. Apple exposes this filesystem capability as [`volumeSupportsExclusiveRenaming`](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumesupportsexclusiverenaming).

## View diagnostics

Open Console, search for `Timestamp Only`, and reproduce the problem. Filenames are marked private in unified logging. Do not include real filenames, paths, screenshots, signing material, or other personal information in a public issue.
