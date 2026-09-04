# Contributing

Contributions are welcome after the repository opens for public development. Please discuss changes that affect screenshot detection, permissions, background operation, supported systems, update behavior, or distribution before implementing them because small-looking changes in those areas can alter the app's safety or trust model.

## Development

Use Xcode command-line tools and Swift Package Manager on macOS:

```sh
make check
make check-app
make check-dmg
```

Filesystem tests must create and watch their own temporary directory. Never run a development build against Desktop, Documents, Downloads, an actual screenshot destination, or retained screenshots.

Every rename path must preserve these invariants:

- Require a positive Apple still-screen-capture marker
- Fail closed when metadata is missing or unreadable
- Never infer screenshot identity from an English filename prefix
- Never overwrite, delete, copy, open, decode, or upload screenshot content
- Use exclusive atomic rename behavior or report that the volume is unsupported
- Exclude screen recordings

Keep runtime dependencies at zero unless a proposed dependency provides a clear product benefit. New networking, telemetry, automatic update behavior, or entitlements require an explicit product decision.

`make verify-app` and `make verify-dmg` inspect existing artifacts without rebuilding them. Use `make check-app` and `make check-dmg` when development artifacts should be rebuilt first. Ad-hoc development artifacts are never release candidates.

Maintainer releases use the local two-phase workflow documented in [docs/RELEASE.md](docs/RELEASE.md). GitHub Actions runs secretless checks and development packaging; it never receives Developer ID or Apple notarization credentials.

## Style and commits

Run the full test and packaging checks for changes that affect runtime behavior. Use Conventional Commits and keep each commit focused on one coherent change with its tests and documentation.

By contributing, you agree that your contribution is licensed under AGPL-3.0-only.
