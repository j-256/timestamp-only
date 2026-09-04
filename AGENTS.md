# Repository guidance

## Product safety

Timestamp Only changes user filenames, so preservation is the primary requirement. Never overwrite, delete, copy, decode, or upload screenshot content. A file without a positive Apple screen-capture marker must remain untouched.

Never point development builds or automated tests at Desktop, Documents, Downloads, a configured screenshot destination, or another real user folder. Filesystem tests must create and watch their own temporary directory, synthesize every input, and remove only that temporary directory.

The runtime product is local-only. Do not add telemetry, analytics, uploads, remote configuration, automatic update checks, or network entitlements without an explicit product decision. Any future automatic update check must be opt-in and default to disabled.

## Compatibility

Keep the deployment target at macOS 11 unless a documented and tested product decision changes it. Availability-gate newer APIs and preserve native arm64 and x86_64 release builds. A successful compile is not evidence that an older macOS version works; advertise support only after runtime testing.

Use AppKit APIs that exist at the deployment target. The macOS 13 and later login-item path uses `SMAppService`; the macOS 11 and 12 fallback remains isolated and independently testable.

## Build and test

Use `make check` for formatting, shell lint, unit tests, and temporary-directory integration tests. Use `make check-app` and `make check-dmg` to rebuild and verify ad-hoc development artifacts. The `make verify-app` and `make verify-dmg` targets are deliberately read-only so verification cannot overwrite a notarized candidate.

Use only `make prepare-release` and `make publish-release` for maintainer releases. Preparation may use local signing credentials only after explicit approval, and publication still requires separate approval. Never publish a development artifact or bypass the candidate manifest and immutable-version guards.

Build and packaging scripts are public CLIs. They must support `-h` and `--help`, emit results to stdout and diagnostics to stderr, validate dependencies before work, use exit status 2 for usage errors, and use exit status 3 for missing dependencies.

Do not place signing or notarization credentials in source files, scripts, fixtures, build output, or logs. Release signing and notarization must accept credentials through standard macOS signing facilities and protected environment configuration.

## Repository lifecycle

Keep commits logically scoped and follow Conventional Commits. Inspect complete unstaged and staged diffs before each commit, stage explicit paths, and name those paths on the commit command. Never push, publish a release, publish a Homebrew Cask, alter an external catalog, or change repository visibility without explicit approval.
