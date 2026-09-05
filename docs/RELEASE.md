# Release process

This document describes the guarded maintainer workflow. It is not authorization to use signing credentials, submit software to Apple, push a tag, publish a GitHub Release, create a Homebrew Cask, or alter an external catalog.

## Release identity

Timestamp Only uses two version values:

| File | Bundle key | Meaning |
| --- | --- | --- |
| `VERSION` | `CFBundleShortVersionString` | Public numeric SemVer such as `0.1.0` |
| `BUILD_NUMBER` | `CFBundleVersion` | Positive integer that increases for every published build |

The host app and embedded login item carry identical values. Never reuse a public version, build number, Git tag, or release asset. A correction after publication is a new version and build, even if the prior download existed only briefly.

`VERSION` must contain exactly three dot-separated integers because it is written directly into Apple bundle metadata. Use the GitHub prerelease state, rather than a suffix in `VERSION`, when a future release needs prerelease labeling.

## Prerequisites

- A clean `main` that exactly matches `origin/main`
- A successful GitHub `CI` run for that exact commit
- Completed runtime and UX qualification appropriate to the advertised compatibility
- One Developer ID Application identity in the login Keychain, or an explicitly selected identity
- A valid `notarytool` profile named `timestamp-only-notary`, unless another profile is selected explicitly
- GitHub CLI authentication with permission to push the version tag and manage Releases

The primary DMG does not need a Developer ID Installer identity because it contains an ordinary application bundle and Applications shortcut rather than an installer package.

Never print, export, upload, or commit certificate private keys, Apple app-specific passwords, App Store Connect private keys, Keychain-profile contents, or other signing credentials. GitHub Actions does not receive release credentials.

## Prepare tracked version files

Whenever the tracked version or build must advance, run the guarded version command from a clean `main`:

```sh
make version V=0.1.1
```

This runs the complete source checks, updates `VERSION`, and increments `BUILD_NUMBER`. Select an explicit larger build with `BUILD=<integer>`, including when replacing an unpublished candidate without changing its public version. It does not commit, tag, push, or publish.

Review and commit only the two version files, then push `main` normally and wait for CI to pass:

```sh
git diff -- VERSION BUILD_NUMBER
git add VERSION BUILD_NUMBER
git commit -m "chore(release): prepare 0.1.1" -- VERSION BUILD_NUMBER
git push origin main
```

Do not prepare the signed artifact from an unpushed commit. Requiring successful CI for the exact remote commit makes the source associated with a release independently visible before signing begins.

## Prepare the local release candidate

After explicit approval to use the signing and notarization credentials, run:

```sh
make prepare-release
```

The guard performs these operations in order:

1. Confirm clean synchronized `main`, successful CI, increasing version and build, and absence of the version tag and GitHub Release.
2. Select one Developer ID Application identity and derive its Team ID without exporting the private key.
3. Authenticate `timestamp-only-notary` from the login Keychain.
4. Run formatting, shell checks, unit tests, temporary-directory integration tests, release command tests, and Thread Sanitizer.
5. Build fresh universal arm64 and x86_64 host and login-item executables with the tracked version and build.
6. Sign the login item before the host app with the hardened runtime, release entitlements, secure timestamps, and the selected Developer ID identity.
7. Verify bundle structure, versions, architectures, deployment targets, entitlements, privacy manifest, signer authority, Team ID, and timestamps.
8. Create and sign the DMG, submit it to Apple, save and inspect the result and log, staple the accepted ticket, assess it with Gatekeeper, and generate the checksum after stapling.
9. Independently reverify the final read-only DMG and write a manifest tying its digest and notarization submission to the exact Git commit.

The completed candidate is stored under `release-candidates/v<VERSION>-<BUILD_NUMBER>/`. This ignored directory is deliberately outside `build/`, so `make clean` cannot delete the notarized artifact. Preparation never creates a tag, pushes, creates a GitHub Release, or updates Homebrew. An existing candidate is never overwritten.

If more than one Developer ID identity is installed, select one explicitly:

```sh
scripts/release prepare --signing-identity "Developer ID Application: Example (TEAMID)"
```

## Qualify the candidate

The automated checks do not replace interaction testing. Before public release, exercise the exact candidate and cover at least:

- Opening the DMG and dragging the app to Applications
- First launch and the folder picker against a synthetic temporary folder
- Running, paused, permission-recovery, and error states
- Launch-at-login registration, approval guidance, logout/login relaunch, and disable
- Replacement upgrade with settings and the selected-folder bookmark preserved
- Prepare for Removal, app deletion, and documented residual-container behavior
- Keyboard navigation, VoiceOver, text scaling, contrast, reduced motion, light and dark appearance, and a crowded menu bar

Never aim a release candidate at a real screenshot destination or retained screenshots during qualification. A deployment target and cross-architecture compilation do not prove runtime behavior on an older macOS release. Describe untested versions accurately until they receive runtime coverage.

## Stage and publish the GitHub Release

After explicit publication approval, run from an interactive terminal:

```sh
make publish-release
```

The publication guard rereads the candidate manifest, confirms the exact source commit and successful CI, verifies the candidate again, and asks before creating or pushing the annotated version tag. It creates a draft GitHub Release, uploads only the DMG and checksum, downloads both assets into a fresh temporary directory, compares them byte for byte with the candidate, and reruns release verification on the downloaded DMG.

After the draft assets pass, the command prints the draft URL and pauses before making it public. Download the draft DMG through a browser so macOS applies quarantine, complete the clean-install checklist with those exact bytes, and then answer the final prompt. Answering no leaves the draft private and resumable.

Publication is resumable only when existing local and remote state is exact. An annotated tag must resolve to the candidate commit, existing assets must match byte for byte, and a published release must contain only the expected DMG and checksum. The guard never force-moves a tag, deletes a release, or replaces an asset.

## Recovery

| Failure point | State | Recovery |
| --- | --- | --- |
| Source, CI, identity, or profile preflight | No release mutation | Correct the reported condition and rerun preparation |
| Build or test | Incomplete ignored staging is removed | Fix the source, commit and push it, wait for CI, then prepare again |
| Apple rejects submission | No tag or GitHub Release | Inspect the printed Apple log, fix the source or signing configuration, and prepare again |
| Candidate already exists | Existing candidate is preserved | Publish it, or use a new version and build rather than overwriting it |
| Tag push fails | Exact local annotated tag may remain | Rerun publication; exact state resumes and conflicting state fails |
| Draft creation or asset upload fails | Exact remote tag or partial draft may remain | Rerun publication; missing assets are added, but differing assets are never replaced |
| Download verification fails | Draft remains private | Do not publish; investigate the disagreement and use a new version if any remote bytes must change |
| Final approval is declined | Verified draft remains private | Complete testing and rerun publication when ready |

Do not run `make dmg` after preparing a release and mistake its replaceable development artifact for the candidate. `make verify-app` and `make verify-dmg` are read-only; `make check-app` and `make check-dmg` explicitly rebuild ad-hoc development artifacts before verifying them.

## Homebrew Cask

The Cask token is `timestamp-only`. Update it only after the public GitHub asset has been downloaded and independently verified. The Cask must use the same notarized DMG and published checksum, declare `app "Timestamp Only.app"`, and document a conservative `zap` stanza for `~/Library/Containers/dev.j-256.timestamponly`.

Ordinary Cask uninstall should preserve the sandbox container and user preferences. `zap` is the explicit complete-removal path. The Cask must not install a package, shell script, LaunchAgent, or a separately built application.

## Future updater

An updater is deferred. If implemented, it must validate signed release metadata and the downloaded code signature, coexist with direct and Cask installations without surprise, and expose an opt-in automatic-check preference that defaults to off. Adding the updater, its network entitlement, feed, keys, and privacy documentation is a separately reviewed feature and release checkpoint.
