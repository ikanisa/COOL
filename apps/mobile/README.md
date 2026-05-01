# Mobile App

Flutter mobile app boundary for Android, iOS, and Flutter web builds.

This directory is a compatibility facade over the existing root Flutter
package. The source files remain reachable from the historical root paths while
`apps/mobile` also behaves like a Flutter package root through symlinks. That
keeps native project, CI, and release tooling compatible while giving the
monorepo a clear mobile app boundary.

## Commands

- `cd apps/mobile && ../../scripts/dev/flutterw analyze`
- `cd apps/mobile && ../../scripts/dev/flutterw test`
- `cd apps/mobile && ../../scripts/dev/flutterw build apk --debug`

Root-level compatibility commands still work while CI and release scripts are
migrated incrementally.

## Boundaries

- Mobile feature code belongs under `lib/features`.
- Shared mobile primitives belong under `lib/core` or `lib/shared` until they
  are extracted into packages with contract tests.
- Native Android/iOS configuration stays owned by this app boundary even while
  root compatibility paths exist.
