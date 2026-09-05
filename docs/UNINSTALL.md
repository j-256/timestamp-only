# Complete removal

## Normal removal without Terminal

1. Open Timestamp Only Settings.
2. Click Prepare for Removal.
3. Confirm Prepare and Quit. The app turns off launch at login, stops monitoring, clears its selected-folder bookmark and settings, and quits.
4. Open Applications in Finder and move Timestamp Only to Trash.

This process does not delete, move, or rename any screenshots.

## If the app was already deleted

Open System Settings, go to General, then Login Items, and disable Timestamp Only if it remains listed. In Finder, choose Go > Go to Folder, enter `~/Library/Containers/dev.j-256.timestamponly`, and move that container to Trash if you want to remove residual preferences. macOS may require confirmation before deleting an app container.

## Homebrew removal

First use Prepare for Removal in Timestamp Only so the app can unregister its login item and clear its folder permission. Then remove the Cask:

```sh
brew uninstall --cask timestamp-only
```

Ordinary Cask removal preserves the sandbox container. To remove that residual container too, use the explicit `--zap` form:

```sh
brew uninstall --cask --zap timestamp-only
```

If the app was removed before Prepare for Removal, follow the System Settings cleanup under "If the app was already deleted" above.

The DMG installs no daemon, privileged helper, kernel or system extension, package receipt, shell profile entry, or file outside the application bundle and sandbox container.
