# ZIP files unpack beside the original

Double-click a ZIP in Files. Its contents unpack in the background into a new
folder beside it. For example, `Downloads/Footage.zip` creates
`Downloads/Footage/`. If that name already exists, the new folder is
`Footage (2)`, then `Footage (3)`. Existing files are never merged or replaced.
The original ZIP stays where it is.

Every ZIP gets its own folder, even if it already contains a single folder.
This keeps the result predictable and avoids spreading files across Downloads.
The completion notification includes **Show extracted files**. Click it to open
the new folder in Files. Dismissing it leaves your windows alone. If you extract
several ZIPs, waiting to click one notification does not hold up the next ZIP.

A password-protected
ZIP shows Archive Manager's password prompt. An error produces a notification;
any partial output stays in the new folder and is described as incomplete.
A full drive produces a clear message to free up space or copy the ZIP to
another drive. A read-only drive produces a message to copy the ZIP somewhere
writable first. A folder you cannot write to has its own permission message.
The original ZIP is preserved in all these cases.

To look inside a ZIP without extracting, right-click it and choose
**Open With → Archive Manager**. Other archive types keep their existing opener.
Your personal Open With preference takes priority over this system default;
updates do not reset it. On the current bench, neither personal mimeapps file
contained an explicit ZIP preference when this change was prepared.

## How it works

`aquarius-extract-zip.desktop` claims only ZIP file types. The default lives in
`/etc/xdg/mimeapps.list`, alongside the Installer's defaults. The Installer
continues not to claim ZIPs.

The small `/usr/libexec/aquarius-extract-zip` helper creates the destination
folder with an atomic directory-creation operation. Existing files, directories
and symlinks all count as occupied names, including simultaneous double-clicks.
It asks the installed File Roller service to extract using the
`org.gnome.ArchiveManager1.Extract` D-Bus method, with its progress-window option
set to false. The actual extraction, password handling and archive safety checks
remain File Roller's job. This helper does not implement an archive decoder.

The D-Bus call uses GDBus's no-timeout setting, so a large video archive is not
stopped after the default 25 seconds. The desktop entry never opens a terminal
or archive-browsing window. Extraction errors and completion return to the helper. A separate notification
worker uses the desktop's normal notification action protocol and opens the
folder through its default handler only after **Show extracted files** is
clicked. File paths are passed as file URIs, never shell commands. If the drive
was disconnected or the folder was moved, the action reports that instead.

We deliberately do not use File Roller's `--extract-here`: it can select an
existing destination. Its `--notify` option also shows a completion dialog in
File Roller 44.7, which would interrupt the requested background flow.

## Checks

Run `python3 tests/test-extract-zip.py` from the image repository. It checks
collision naming, existing symlinks, input validation, the D-Bus contract and
success/error feedback, filesystem error messages, action dismissal and folder
opening. `python3 tests/test-extract-zip-notification.py` creates a private
notification bus and checks real `notify-send` action registration and delivery;
it does not contact your desktop or open a window. Image step 65 also asks GIO which app actually opens
each ZIP MIME type and verifies the executable is present.

For the real engine check, use an isolated desktop and bus so no existing Files
or Archive Manager process participates:

```bash
zip_test=$(mktemp -d)
mkdir "$zip_test/runtime" "$zip_test/config"
chmod 700 "$zip_test/runtime"
XDG_CONFIG_HOME="$zip_test/config" XDG_RUNTIME_DIR="$zip_test/runtime" \
WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman \
WLR_LIBINPUT_NO_DEVICES=1 timeout 20s dbus-run-session labwc \
-C "$zip_test/config" -S "python3 '$PWD/tests/test-extract-zip.py' --engine"
```

The test must print `OK`; a timeout or a desktop that exits before the tests
finish is not a pass. Fixtures use temporary folders only. The real-engine
check covers ordinary extraction, repeated extraction to a second destination,
parent-path traversal, absolute paths and a ZIP symlink-parent payload. None may
write outside the destination. The test deadline applies only to tiny fixtures,
not production extraction. On the bench's File Roller 44.7, all passed.

The next bench check is a double-click through Files, including a password ZIP,
a damaged ZIP, and extraction beside real footage on a writable drive.
