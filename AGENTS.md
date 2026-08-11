# PowerLeft Repository Instructions

## Repository identity

- Treat `ourongxing/powerleft` as an independent repository and the canonical source of truth.
- Do not fetch, compare, merge, cherry-pick, or otherwise synchronize changes from the repository this project was originally forked from.
- Do not preserve upstream compatibility merely for the sake of matching the original project.
- Only inspect or integrate another repository when the user explicitly requests that specific action.

## Product requirements

- Keep the product name as `PowerLeft`; use `余电` as the macOS display name.
- Keep the GitHub repository name lowercase: `powerleft`.
- Never show a disconnected device in the menu or the macOS battery widget.
- Preserve support for JZM5 and Keychron M6 in 2.4 GHz mode.
- Keep the code ready for additional mice and keyboards without adding device-specific logic to the application coordinator.

## Architecture

- Implement each supported device as an independent `BatteryDriver` under `Sources/Drivers`.
- Register drivers only through `DriverRegistry.all` in `Sources/Models.swift`.
- Keep shared HID matching and lifecycle management in `HIDDeviceAccess`.
- Keep menu state, polling, and connection handling generic in `AppDelegate`.
- Publish device metadata through `DeviceDescriptor`; use `Mouse` or `Keyboard` as the accessory category as appropriate.
- Validate battery values before publishing them to macOS.
- Use the `--once` diagnostic mode for hardware regression checks when a supported receiver is available.

## Validation

- Run `git diff --check` before committing.
- Run `./build.sh` after Swift or build-system changes.
- Verify the generated app with `codesign --verify --deep --strict dist/PowerLeft.app`.
- Run `dist/PowerLeft.app/Contents/MacOS/PowerLeft --once` when compatible hardware is connected.

## Git and GitHub

- Write commit messages in English only.
- Use Conventional Commits with a scope: `type(scope): description`.
- Prefer an appropriate type such as `feat`, `fix`, `refactor`, `docs`, `test`, or `chore`; do not force all commits to use `chore`.
- Keep descriptions concise and written in imperative lowercase English.
- Use `ourongxing/powerleft` as `origin`; do not refer to it as a fork or maintain an upstream remote by default.
- Push changes to the current branch on `origin` unless explicitly instructed otherwise.
- Do not create a pull request unless the user explicitly asks for one.
- Do not rewrite published history unless the user explicitly requests it.
