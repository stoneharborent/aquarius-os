# Files closes when a merge dialog closes

On 10 September 2026, the bench recorded two Files crashes. Both stopped in
GTK 4.22.4's Wayland window-icon cleanup. This is a window-management fault:
it does not show that the Mac drive or its contents are damaged.

GTK frees an icon buffer twice after the desktop releases it. The GTK team
fixed this in [commit 4fb8cf94599c623b563ceea7ad75dca750dd4901](https://github.com/GNOME/gtk/commit/4fb8cf94599c623b563ceea7ad75dca750dd4901)
([merge request 10146](https://gitlab.gnome.org/GNOME/gtk/-/merge_requests/10146)).
The installed Fedora package, `gtk4-4.22.4-2.fc44`, still contains the bad cleanup.

## What AquariusOS changes

Files starts through `/usr/libexec/aquarius-files`, which adds
`xdg_toplevel_icon_manager_v1` to `GDK_WAYLAND_DISABLE`. GTK supports this
variable for disabling individual Wayland protocols. Other disabled protocols
are preserved. Rendering, file permissions and other apps are unchanged.
The desktop can still identify Files through its app ID and desktop icon;
only its optional per-window icon transfer is disabled.

The image routes both the app-menu entry (including New Window) and the
D-Bus service through this launcher. D-Bus is how another app asks Files to
open a folder. Fedora's translations and launch arguments stay intact.
A manually typed `/usr/bin/nautilus` command bypasses the workaround.
An already running Files process must close before it can receive the change.

## What was tested

A disposable headless labwc desktop reproduced a segmentation fault when the
first GTK window with the Files icon closed. With the variable above, the same
probe completed 20 window creation and destruction cycles. No user folders
or running Files windows were used. The protocol log showed that the affected
icon protocol was not bound in the passing run.

This proves the workaround for the recorded GTK fault. The original folder
merge still needs a bench check with disposable source and destination folders.
Copying into a read-only Mac drive can also be rejected for a separate reason.

## Repeating the window test

From the `os-image` folder, run the following on a machine with GTK 4 and labwc.
It creates an invisible test desktop in a temporary folder. It does not touch
your current desktop. The probe prints `PASS` after 20 cycles; a segmentation
fault is a failure even if labwc itself exits successfully.

```bash
probe_dir=$(mktemp -d)
mkdir "$probe_dir/runtime" "$probe_dir/config"
chmod 700 "$probe_dir/runtime"
cp tests/probe-gtk-window-icons.py "$probe_dir/probe.py"
XDG_RUNTIME_DIR="$probe_dir/runtime" WLR_BACKENDS=headless \
WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 \
timeout 15s dbus-run-session labwc -C "$probe_dir/config" \
-S "env GDK_BACKEND=wayland GTK_A11Y=none GSK_RENDERER=cairo GDK_WAYLAND_DISABLE=xdg_toplevel_icon_manager_v1 python3 '$probe_dir/probe.py'"
```

To check the unmodified GTK behavior, repeat the last command with
`GDK_WAYLAND_DISABLE=` (an empty value). On the affected GTK build, that run
crashes. `GSK_RENDERER=cairo` is only for this headless test, not the workaround.
The launcher wiring can be checked without a desktop:
`python3 tests/test-files-launchers.py`.

## When to remove this workaround

Once Fedora ships GTK containing the exact upstream fix linked above, repeat
both window tests. Remove the wrapper, the build step that wires it into the
Fedora entries, and its launcher tests only after the unmodified run passes
and a real Files merge/replace dialog opens and closes successfully on the bench.
Do not use a package timestamp or assume that a higher version includes it.
