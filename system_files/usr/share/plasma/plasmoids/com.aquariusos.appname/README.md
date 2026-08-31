# com.aquariusos.appname — the app name in the top bar

The small bold word near the left of the AquariusOS top bar that says which app
you are using: **Dolphin**, **Firefox**, **Steam**. It sits between the
AquariusOS logo and the File / Edit / View menus, exactly where macOS puts it.

The full write-up — why we wrote our own instead of adopting a community widget,
which KDE source every claim was checked against, and how to test it on a real
machine — is at **`docs/app-name-widget.md`** in the repository root.

## What is in this folder

| File | What it is |
|---|---|
| `metadata.json` | The widget's name, id and licence. KDE reads this to know the widget exists. |
| `contents/ui/main.qml` | The widget itself. About forty lines of actual code, and a lot of comments explaining them. |

## Two things worth knowing before you change anything

1. **The folder name is the widget's id.** It must stay
   `com.aquariusos.appname`, and it must keep matching the `"Id"` line inside
   `metadata.json`. The desktop layout script asks for the widget by that id:
   `system_files/usr/share/plasma/look-and-feel/org.aquariusos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js`
   Rename one without the others and the top bar simply comes up without an app
   name, with nothing on screen to say why.

2. **There is nothing to compile.** This is QML — text files that KDE reads at
   login. Changing them needs no build step and no new packages, which is the
   main reason the widget is shaped this way. To try a change on a running
   machine, copy this folder to `~/.local/share/plasma/plasmoids/` and restart
   the shell with `systemctl --user restart plasma-plasmashell`.
