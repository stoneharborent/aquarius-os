# =============================================================================
# aquarius_ui — the pieces every AquariusOS window is built out of
# =============================================================================
# PLAIN ENGLISH
#
# AquariusOS has a small family of windows that all do the same shape of job:
# explain something, do it while showing a list of steps and a bar, and say how
# it went. Today that is three windows:
#
#   /usr/libexec/aquarius-creator-apps        "Your creator apps"
#   /usr/libexec/aquarius-resolve-installer   "Install DaVinci Resolve"
#   /usr/libexec/aquarius-resolve-uninstaller "Remove DaVinci Resolve"
#
# They were written one after another and by the third one there were roughly
# two hundred lines of the same code in three places — the step row with its
# spinner and tick, the Details log that follows its own tail, the Copy button,
# the Aquarius mark at the top. Three copies of a thing is three places for it
# to drift, and a window that looks slightly different from its neighbour looks
# like a different operating system.
#
# So the shared pieces live here, once. NOTHING IN THIS FILE DECIDES ANYTHING.
# It has no idea what Resolve is or what a Flatpak is; it draws rows, logs and
# labels. Every decision stays in the window that owns it.
#
# ------------------------------------------------------------------------------
# HOW A WINDOW USES IT
# ------------------------------------------------------------------------------
# This folder is not on Python's search path, so each window says where it is:
#
#     import sys
#     sys.path.insert(0, "/usr/lib/aquarius/python")
#     import aquarius_ui
#
# ⚠️ IMPORT IT LATE, NOT AT THE TOP OF THE FILE, IF THE WINDOW HAS A --dry-run.
#    Importing this pulls GTK in, and the whole point of the chooser's --dry-run
#    is that it works in a build container with no screen and no GTK. The
#    chooser imports it inside the function that draws things, and the build
#    depends on that still being true.
#
# ------------------------------------------------------------------------------
# WHY NO COLOURS ARE SET ANYWHERE IN HERE
# ------------------------------------------------------------------------------
# libadwaita follows the system light/dark setting on its own, and AquariusOS
# sets its accent at the desktop level. A window that paints nothing itself is
# automatically an AquariusOS-coloured window, in Ice and in Midnight, for free.
# branding/tokens.md is the law for anything that ever does need a literal
# colour — and nothing here does.
# =============================================================================

import os

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, GLib, GObject, Gtk  # noqa: E402

# The Aquarius mark, as the image installs it.
MARK = "/usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg"

# The four states a step can be in. Written as numbers rather than strings
# because they are compared, never printed.
PENDING, ACTIVE, DONE, FAILED = range(4)


class StepRow(Adw.ActionRow):
    """One line in a list of steps, with a spinner or a tick in front of it.

    A step that has not been reached shows NOTHING in front of it rather than a
    third icon: an empty box beside a dimmed label reads as "not yet" without
    having to be learnt.

    The icon names are from the Adwaita icon theme, which this image always has.
    """

    def __init__(self, title):
        super().__init__(title=title)
        self.set_title_lines(0)
        self._spinner = Gtk.Spinner()
        self._icon = Gtk.Image()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        box.set_size_request(20, -1)
        box.set_valign(Gtk.Align.CENTER)
        box.append(self._spinner)
        box.append(self._icon)
        self.add_prefix(box)
        self._state = PENDING
        self.set_state(PENDING)

    @property
    def state(self):
        return self._state

    def set_state(self, state):
        self._state = state
        self._spinner.set_visible(state == ACTIVE)
        if state == ACTIVE:
            self._spinner.start()
        else:
            self._spinner.stop()
        self._icon.set_visible(state in (DONE, FAILED))
        if state == DONE:
            self._icon.set_from_icon_name("emblem-ok-symbolic")
            self._icon.remove_css_class("error")
            self._icon.add_css_class("success")
        elif state == FAILED:
            self._icon.set_from_icon_name("dialog-error-symbolic")
            self._icon.remove_css_class("success")
            self._icon.add_css_class("error")
        # Steps not reached yet are dimmed, so the eye lands on the live one.
        if state == PENDING:
            self.add_css_class("dim-label")
        else:
            self.remove_css_class("dim-label")


class LogPane:
    """The "Details" expander and the log inside it.

    Everything a window's underlying script says goes in here, unchanged, in a
    monospaced font, following its own tail the way a terminal does. It is shut
    by default and opens itself when something goes wrong, because the moment
    somebody needs it is the moment they have not been told what to look at.

    `widget` is the expander to put in a page. `lines` is every line so far,
    which is what the Copy button and any "what went wrong" test read.
    """

    def __init__(self, label="Details", height=220):
        self.lines = []

        self.view = Gtk.TextView()
        self.view.set_editable(False)
        self.view.set_cursor_visible(False)
        self.view.set_monospace(True)
        self.view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.view.set_left_margin(8)
        self.view.set_right_margin(8)
        self.view.set_top_margin(6)
        self.view.set_bottom_margin(6)

        self.scroll = Gtk.ScrolledWindow()
        self.scroll.set_child(self.view)
        self.scroll.set_min_content_height(height)
        self.scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        self.scroll.add_css_class("card")

        self.widget = Gtk.Expander(label=label)
        self.widget.set_child(self.scroll)
        self.widget.set_margin_top(4)

    def append(self, text):
        """Add a line. Safe to hand to GLib.idle_add from a reading thread."""
        self.lines.append(text)
        buf = self.view.get_buffer()
        buf.insert(buf.get_end_iter(), text if text.endswith("\n") else text + "\n")
        mark = buf.create_mark(None, buf.get_end_iter(), False)
        self.view.scroll_to_mark(mark, 0.0, True, 0.0, 1.0)
        buf.delete_mark(mark)
        return GLib.SOURCE_REMOVE

    def clear(self):
        self.lines = []
        self.view.get_buffer().set_text("")

    def text(self):
        return "".join(
            line if line.endswith("\n") else line + "\n" for line in self.lines
        )

    def set_expanded(self, expanded):
        self.widget.set_expanded(expanded)


def copy_to_clipboard(text):
    """Put text on the clipboard.

    ⚠️ NOT clipboard.set(text). That is a C macro with no introspection data, so
    it is not there to call from Python at all — the call simply fails. This is
    the real one, and it is the sort of thing worth having in exactly one place.
    """
    display = Gdk.Display.get_default()
    if display is None:
        return False
    value = GObject.Value(str, text)
    display.get_clipboard().set_content(Gdk.ContentProvider.new_for_value(value))
    return True


def copy_button(label, get_text, tooltip="Copy the whole log to the clipboard"):
    """A Copy button that says "Copied" for two seconds and then changes back."""
    button = Gtk.Button(label=label)
    button.set_tooltip_text(tooltip)

    def clicked(_button):
        copy_to_clipboard(get_text())
        _button.set_label("Copied")
        GLib.timeout_add_seconds(2, lambda: (_button.set_label(label), False)[1])

    button.connect("clicked", clicked)
    return button


def mark_image(pixel_size=64, fallback="applications-multimedia"):
    """The Aquarius mark at the top of a page — or a sensible icon if it is not
    installed, because a window with a hole where a logo should be looks broken
    in a way a generic icon does not."""
    image = Gtk.Image()
    if os.path.exists(MARK):
        image.set_from_file(MARK)
    else:
        image.set_from_icon_name(fallback)
    image.set_pixel_size(pixel_size)
    image.set_margin_top(8)
    return image


def title_label(text, style="title-1"):
    label = Gtk.Label(label=text)
    label.add_css_class(style)
    label.set_wrap(True)
    label.set_justify(Gtk.Justification.CENTER)
    return label


def body_label(text, dim=True, centre=True):
    label = Gtk.Label(label=text)
    label.set_wrap(True)
    if centre:
        label.set_justify(Gtk.Justification.CENTER)
    if dim:
        label.add_css_class("dim-label")
    return label


def page(widgets, maximum_size=560, spacing=16):
    """The standard page: a column of things, clamped to a readable width, in a
    scroller so that a small screen can still reach the buttons at the bottom."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=spacing)
    box.set_margin_top(24)
    box.set_margin_bottom(24)
    box.set_margin_start(18)
    box.set_margin_end(18)
    for widget in widgets:
        box.append(widget)
    clamp = Adw.Clamp(maximum_size=maximum_size)
    clamp.set_child(box)
    scroller = Gtk.ScrolledWindow(vexpand=True)
    scroller.set_child(clamp)
    return scroller


def button_row(buttons, spacing=12, margin_top=8):
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=spacing)
    box.set_halign(Gtk.Align.CENTER)
    box.set_margin_top(margin_top)
    for button in buttons:
        box.append(button)
    return box


def pill_button(label, suggested=False, destructive=False):
    button = Gtk.Button(label=label)
    button.add_css_class("pill")
    if suggested:
        button.add_css_class("suggested-action")
    if destructive:
        button.add_css_class("destructive-action")
    return button


def expander_note(title, text):
    """A section somebody can open if they want it and ignore if they do not.

    Used for the honest small print — the sort of paragraph that has to be in a
    window somewhere but must not be the first thing a person reads.
    """
    label = body_label(text, dim=True, centre=False)
    label.set_margin_top(8)
    label.set_margin_start(4)
    label.set_margin_end(4)
    label.set_margin_bottom(8)
    label.set_xalign(0.0)
    expander = Gtk.Expander(label=title)
    expander.set_child(label)
    return expander


def numbered_steps(items):
    """A short "what will happen" walkthrough: 1, 2, 3, 4 down the left.

    Deliberately not the same widget as StepRow. These are a promise made before
    anything starts; StepRow is a report on something happening now, and making
    them look identical would say the first one was already under way.
    """
    group = Adw.PreferencesGroup()
    for number, (title, subtitle) in enumerate(items, start=1):
        row = Adw.ActionRow(title=title)
        row.set_title_lines(0)
        if subtitle:
            row.set_subtitle(subtitle)
            row.set_subtitle_lines(0)
        badge = Gtk.Label(label=str(number))
        badge.add_css_class("dim-label")
        badge.add_css_class("numeric")
        badge.set_valign(Gtk.Align.CENTER)
        badge.set_size_request(20, -1)
        row.add_prefix(badge)
        group.add(row)
    return group


def link_button(uri, label, tooltip=None):
    """A button that opens a web page in the person's browser.

    Gtk.LinkButton does the opening itself, through the desktop's own handler,
    which is the same thing xdg-open would do and needs no code of ours.
    """
    button = Gtk.LinkButton(uri=uri, label=label)
    if tooltip:
        button.set_tooltip_text(tooltip)
    return button
