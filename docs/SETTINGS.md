# Settings

## Status and menu bar

The menu-bar icon reports one of these states:

- Running: new screenshots in the selected folder are eligible for renaming
- Paused: monitoring is stopped, and files created during the pause remain untouched after resume
- Folder Access Needed: select the screenshot folder again
- Error: the app could not monitor or safely rename a candidate

The menu provides Pause or Resume, Settings, About, and Quit. The Background operation section separately reports when launch-at-login approval is needed in System Settings. Quitting does not change the launch-at-login preference. Use Prepare for Removal before uninstalling.

## Screenshot folder

Timestamp Only watches one selected folder and only its direct children. It does not recurse into subfolders or retroactively rename existing files. Selecting a folder establishes a baseline so only later file-creation activity is considered.

Use Shift-Command-5 and open Options to confirm where macOS saves screenshots. If that location moves or its permission changes, choose it again in Settings.

## Filename format

The default format is `yyyy-MM-dd HH.mm.ss`. It produces a name such as `2026-09-04 13.05.09.png`.

The field uses Unicode date-format patterns through Apple's `DateFormatter`. Common symbols include:

| Symbol | Meaning | Example |
| --- | --- | --- |
| `yyyy` | Four-digit year | `2026` |
| `MM` | Two-digit month | `09` |
| `dd` | Two-digit day | `04` |
| `HH` | 24-hour hour | `13` |
| `mm` | Minute | `05` |
| `ss` | Second | `09` |

The live preview updates while you type and uses the Gregorian calendar and `en_US_POSIX` locale for stable digits and separators. Local Time follows the Mac's time zone, while UTC always uses UTC. Choose Apply or press Return to save a valid edit. Changing the setting affects future renames only.

The app rejects formats that produce an empty or whitespace-only filename, surrounding whitespace, control characters, `/`, `:`, `.`, `..`, a hidden name beginning with `.`, or a base name too long to leave safe room for the extension and collision suffix. Invalid text is shown inline and never replaces the last valid setting.

## Collisions

If a destination already exists, Timestamp Only tries `-1`, then `-2`, and so on. The rename is exclusive and atomic, so another process creating the same name cannot cause an overwrite between a check and the rename.

## Launch at login

Launch at login defaults to off. On macOS 13 and later, the toggle registers the main app through `SMAppService`; Apple documents that [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) represents the main application as a login item. A fresh installation can initially report that the service was not found because it has not been registered before; the toggle remains available and registration begins only when you turn it on. If macOS requires approval, Settings provides a button to open the Login Items panel.

On macOS 11 and 12, a minimal bundled login item starts the main app and remains idle. It has no screenshot-folder access. Support for those systems is not advertised until the fallback has passed runtime qualification.
