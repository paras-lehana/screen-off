# Contributing

Thanks for helping. The most useful contributions are **device reports** (does it work on your
monitors and RGB hardware?) and **new lighting systems**.

## Report a device

Open a [device report](https://github.com/paras-lehana/screen-off/issues/new?template=device-report.yml).
Include the monitor or RGB device model, how it is connected, the software versions, which
lighting system you ticked, and what you saw with your own eyes: did it go dark, stay dark for
the whole standby, and come back the way it was? Attach the relevant `logs\rgb-*.log` file if
something failed. Please remove serial numbers first.

Software reporting success is not the same as the lights being off; reports say which one you
observed.

## Develop

1. Install AutoHotkey v2 (see [README](README.md#install)).
2. Run `.\Test-ScreenOff.ps1` before and after your change. It must stay green and it never turns
   screens or lights off.
3. Keep comments short and explain *why*. Match the surrounding style.
4. New behaviour needs an offline test where possible (pure functions and fake controllers, like
   `test-lighting-set.ahk`). Hardware behaviour needs a person to watch it; say so in the PR.

### Rules that protect people's hardware

- **Never send DDC/CI power-off (VCP D6 = 04 or 05)** or any other monitor power write. Screens are
  switched off only through Windows standby. See [recovery/README.md](recovery/README.md).
- Do not write unknown or vendor-specific monitor codes. Some monitors answer reads with the
  previous request's reply, so "read, change, read back" is not a safe way to explore.
- Lighting workers must always release control in `finally`, and must exit after restoring.
- No automatic installs of third-party software, drivers or services.

## Adding a lighting system

1. Write a worker (PowerShell or a `LightingHost` backend) that takes a parent process id and a
   state-file prefix. It writes `<prefix>.status`:
   - `APPLIED|<devices>` once black has been submitted,
   - `RESTORED|<detail>` after releasing control,
   - `ERROR|<reason>` on failure,
   and `AVAILABLE|<devices>` in a read-only `-Probe` mode that changes no colours.
   It restores when `<prefix>.stop` appears or the parent process exits.
2. Add the kind to `LightingController` in `Lighting.ahk` and to `LightingSet`.
3. Add a setting in `Configuration.ahk` (Load, Validate, Save, Override, Describe) with tests in
   `test-configuration.ahk`. If it can drive the same LEDs as an existing system, make Validate
   refuse the combination.
4. Add a checkbox in `DesktopUi.ahk` and a row in [SUPPORT.md](SUPPORT.md) marked *Implemented*.

## Pull requests

Describe what changed, why, which tests ran, and what (if anything) was observed on hardware.
Small focused PRs are easiest to review.
