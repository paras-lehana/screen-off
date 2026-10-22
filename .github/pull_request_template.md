## What and why

## Tests
- [ ] `.\Test-ScreenOff.ps1` passes
- [ ] New or changed behaviour has an offline test where possible

## Hardware observed
<!-- Which monitors/RGB devices you watched, and what you saw. "Not tested on hardware" is fine; say so. -->

## Safety
- [ ] No monitor power writes (DDC/CI VCP D6) or unknown vendor codes
- [ ] Lighting workers release control in `finally` and exit after restoring
