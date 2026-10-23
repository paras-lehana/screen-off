# Screen Off desktop UI

## Version 1.13

Covers give the instant "screens off" look; true standby waits until the lighting apps are done,
because Armoury Crate cannot work during standby. Wake mirrors it: display on behind covers,
lights restored, covers lifted. Window positions are saved and restored around standby.

## Version 1.12

User experience order: off = screens first, then lights and apps unseen; wake = lights and apps
first while dark, then the screens. The notice has no Cancel button; Esc is the only cancel, the wake key a plain wake.

## Version 1.11

The Lighting tab lists every lighting system as its own checkbox, with Corsair device types in a
three-column grid that is disabled while Corsair is unticked. "Check ticked systems" runs probes in
the background and fills in one line per system. The window was compacted to 941 px tall at 150%
scaling so Save/Cancel stay visible on a 1080p work area (1008 px); screenshots of all three tabs
were inspected. Tray hover lists the lighting systems in use.

## Version1.8 current UI

Aura / notice adds notification lifetime, profile/SDK choice, wake effect and previous
effect preference. Activation has an independent30s timer with no countdown delay;
the standby covers obscure it when active. ASUS Aura is the controller label since
the selected method may use UI Automation instead of the SDK. Hover includes the method.
All defaults/selectors have named top-level constants and comments in source.

Actual native settings screenshot logs/settings-1.8.png was inspected at524x659;
controls and Save/Cancel fit. Corrected the tab's ampersand mnemonic afterward to
Aura / notice. Native invalid-key/duration feedback, Save, INI persistence and visible
saved-toast test passed23:09:42 (logs/settings-live-1.8.out). No browser/mobile surface.
Activation notice timing during real standby and the new wake-effect restoration remain
untried. Existing contrast tokens and icon assets are unchanged. History follows.

Job: show what will happen before the room goes dark, and make keys and RGB
choices easy to inspect/change. Native Windows utility, not a web application.

The mark is a monitor with a crescent. Teal means ready, amber means off. State
also appears in text. Six icon sizes (16/20/24/32/48/64) come from build-icons.ps1;
no external artwork. Segoe UI, native keyboard navigation/focus, labelled controls,
inline invalid-key feedback and Save/Cancel. The off notification does not steal
focus. A black full-monitor cover hides the desktop during Windows wake/re-off.

Colors: background #F4F7FB; headings #10263A; text #34495E; helper #526476;
error #A42230. Measured contrast: headings14.37:1, text8.65:1, helper5.68:1, error6.86:1.
No animation, tracking, web dependencies, boot startup or remote UI.

Validation: inspected actual settings-preview.png and64px icon; ran real native
control invalid-key/Save/toast test. The panel is494x517 at current desktop scaling,
with all labels/buttons visible. Native desktop checks replace web/mobile checks.
Actual overnight flash and sustained RGB appearance await the owner in the morning.

Version1.5 adds a lock-on-wake checkbox and hover state. The prior screenshot is1.4; new checkbox layout was not exercised live because the owner requested no trials. RGB hardware state remains unresolved; UI labels configure requests, not proof of physical darkness.
# Version1.6 native settings follow-up

Controls and Lighting tabs replace the increasingly tall single form. Existing
Segoe UI and #F4F7FB/#10263A/#34495E/#526476/#A42230 tokens remain. Backend dropdown
has four explicit choices; prerequisite text and read-only diagnostics distinguish
selection from actual availability. OpenRGB port is enabled only for OpenRGB;
separate K100 is disabled for other controllers that may own the same keyboard.
Recovery explanation now states restore first, lock only on software confirmation,
and skip automatic lock on timeout. The toast measures itself before bottom-right
placement so longer recovery errors fit the work area. No new animation or raster
asset was needed. Syntax and pure state checks passed; visible layout, tab navigation
and button operation were not tried under the continuing no-live-trial instruction.
Previous screenshots/contrast results describe1.4 and are not a1.6 visual pass.

## Version1.7 persistent preparation notice

The existing nonactivating notice stays visible through RGB startup and the subsequent
30-second countdown. Only its detail text updates once per second; the window is not
recreated. A labelled Cancel (Esc) button and contextual Esc shortcut cancel while the
desktop remains usable. Normal notices retain4.5s duration; destroying a notice also
clears its timer so it cannot later dismiss a preparation notice. Existing colours,
fonts and tray icon remain. The countdown text describes commands/timing rather than
claiming the LEDs are physically off. New notice layout and button/keyboard behavior
were not exercised live under the continuing no-trial instruction; fake-clock tests
validate timing/cancellation only. Browser/mobile tests do not apply to this native UI.

