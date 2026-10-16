# Installing from the handheld USB

The handheld ISO adds AquariusOS artwork, larger text and controller input to the Fedora installer
(the screens shown before AquariusOS is installed). The base and NVIDIA ISOs
keep their existing installer. This change needs a newly built handheld ISO;
updating an installed system does not update an old USB stick.

The installer uses text at 150% size, AquariusOS Ice colors and a Midnight
keyboard. Touch the controls
and text fields directly, or use the handheld controller:

| Control | Action |
| --- | --- |
| Right stick up/down | Previous/next field; moves the highlighted key while the keyboard is open |
| Right stick left/right | Change a choice; moves the highlighted key while the keyboard is open |
| A or right trigger | Select the focused control or type the highlighted key |
| Left stick | Scroll |
| D-pad | Move within lists and choices, or between keyboard keys |
| View | Next field (Tab) |
| Right bumper | Previous field (Shift+Tab) |
| Y | Enter |
| B | Escape |
| X | Backspace |
| Menu or left bumper | Show or hide the on-screen keyboard |

The keyboard opens when a text field gets focus. Move its visible highlight
with the right stick and press A to type, or tap the keys. There is no pointer
to steer. Use its Shift and symbol keys for capitals, numbers and punctuation.
A separate tilt moves one key, so holding the stick cannot run through a row
or repeatedly activate a disk action. The **Keyboard · Menu** button at the top also
shows or hides it. This covers names, passwords and other text fields without
a separate keyboard. Disk selection and the final installation confirmation
still belong to Fedora's installer; read those before proceeding.

## How it is built

The installed OS and the USB installer are separate systems. Adding controller
support to AquariusOS alone does not make the installer support controllers.
After Fedora builds the ISO, `installer/customize.sh` adds GNOME's keyboard and
our small installer session to its live runtime. It copies InputPlumber and
the Ally controller setup from the exact OS image already inside that ISO.
It does not substitute a different controller version from a package server.

The build checks the controller files, shared libraries, effective keyboard
settings, image-format database, AquariusOS artwork and stylesheet, and the
repacked runtime. The dedicated installer shell reserves F1–F9 for controller
commands and F12 for keyboard visibility; physical Tab and arrow keys still
work normally. It preserves the original BIOS and UEFI
boot metadata and recreates the installer's media-check checksum. The embedded
OS and installation choices are unchanged.

## Checks completed

Nine automated tests cover controller discovery/reconnection and safe extraction
from the ISO’s embedded OS. An isolated GNOME 50 session verifies letters,
symbols, Shift, Backspace and canceling a pending press when the keyboard closes.
The actual Fedora installer was also booted in a virtual machine at 1280×800:
controller-equivalent commands navigate fields, focusing the account name opens
the keyboard, and selecting a key types into that field. All four keyboard rows
fit on screen. These checks do not replace testing the physical controller.

## Bench checks before calling this hardware-tested

Use a newly built USB on the ROG Xbox Ally X. Keep a spare keyboard available
for diagnosis during this test; the goal is to finish without using it.

1. Boot from USB and check that the Fedora screens fit the handheld display.
2. With only the controller, choose a language, select the installation disk,
   create the account and password, and reach the final confirmation. Check
   scrolling, previous/next field, visible selection, password punctuation and
   correction. Check Shift, symbols, Backspace and Space on the keyboard.
3. Repeat navigation with touch. Check that the keyboard appears for every
   text field, can be hidden, and leaves the field and next action reachable.
4. Disconnect/reconnect an external controller and confirm navigation returns.
5. Install to a spare test disk, remove USB, and check first boot enters Game
   Mode. This final step erases the selected test disk.

The early firmware boot menu runs before Linux controller support starts;
use the handheld's firmware buttons there. These changes cover Fedora's
graphical setup. Real touchscreen and controller hardware still need the
bench checks above; a virtual machine cannot establish their compatibility.
