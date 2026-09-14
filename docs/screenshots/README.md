# Project cover

The cover renders the production AppKit settings view with synthetic presentation data. It uses the application's default filename format and fixed preview date, a display-only `/Screenshots` path, UTC, and disabled launch at login. The harness never starts `AppController`, a folder watcher, or the login-item manager.

On macOS with a graphical session, Python 3, and Xcode command-line tools:

```sh
make capture-cover
```

The command builds the core module in a temporary directory, compiles the settings view and its supporting types into a capture harness, and renders at double pixel density. No screenshot folder, stored preferences, signing identity, or Screen Recording permission is needed. AppKit styling follows the installed macOS version.

CI regenerates this image from source after verification, uploads it for review, and commits a changed `docs/screenshots/cover.png` on `main`. Pull requests only produce the review artifact. The weekly schedule and manual CI dispatch can refresh the image without an application change. A superseded build does not overwrite a newer source commit.
