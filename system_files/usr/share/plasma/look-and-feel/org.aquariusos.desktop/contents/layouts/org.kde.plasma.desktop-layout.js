// =============================================================================
// AquariusOS desktop layout
// =============================================================================
// This script builds the AquariusOS desktop: a slim bar across the top, a
// floating dock at the bottom, and desktop icons stacked down the right-hand
// edge. macOS-shaped, on purpose.
//
// WHEN IT RUNS
//   Once, the first time a user logs in — and only if that user has no desktop
//   layout saved yet. KDE checks for an existing layout before running this, so
//   it can never rearrange a desktop somebody has already set up, and an OS
//   update will never move their panels around.
//
//   That also means: to see a change to this file, you need a FRESH user
//   account (or a fresh install). Logging out and back in is not enough.
//
// WHERE THE FILENAME COMES FROM
//   KDE looks for a file at exactly this path and name inside a global theme.
//   It is not configurable. Renaming it means no layout at all.
//
// A NOTE ON `gridUnit`
//   Panel sizes are written as multiples of `gridUnit` rather than as pixel
//   counts. gridUnit is the height of one line of the interface font, so panels
//   scale correctly on a 4K display and on a small laptop without us hardcoding
//   anything. Sizes are rounded to an even number because KDE's own panel
//   settings only offer even heights.
//
// Design source: ../../../../../../../branding/tokens.md
// =============================================================================

var unit = gridUnit;

// -----------------------------------------------------------------------------
// 1. THE TOP BAR
// -----------------------------------------------------------------------------
// Full width, deliberately thin, and translucent so the wallpaper shows through
// as a dark wash. Reading left to right: the AquariusOS logo, the current app's
// menus, a stretch of empty space, then the system tray and the clock pushed to
// the far right.
// -----------------------------------------------------------------------------
var topBar = new Panel;
topBar.location = "top";
topBar.alignment = "left";
topBar.lengthMode = "fill";     // spans the whole width of the screen
topBar.floating = false;        // sits flush against the top edge
topBar.hiding = "none";         // always visible, like a Mac menu bar
topBar.opacity = "translucent";
topBar.height = 2 * Math.ceil(unit * 1.6 / 2);

// The launcher, wearing the AquariusOS mark. That icon is installed by this
// image at /usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg — the name
// below is the filename without its extension.
//
// WHICH LAUNCHER, AND WHY THIS ONE
//   "kickerdash" is KDE's Application Dashboard: click it and a full-screen
//   grid of every app takes over the display, with a search box that is live
//   the moment you start typing. GNOME's app grid and macOS Launchpad are the
//   same idea, so this one choice serves both the GNOME flow we are building
//   and the Mac shape of the rest of this bar.
//
//   It replaces "org.kde.plasma.kickoff", the start-menu-style popup KDE uses
//   by default. Kickoff is a small floating panel of categories; the dashboard
//   is the whole screen. Nothing else about this widget changes — same icon,
//   same position, same click.
//
//   Users who prefer the popup can right-click the bar, choose "Show
//   Alternatives", and pick Application Menu or Application Launcher. We are
//   setting a starting point, not taking anything away.
//
// A NOTE ON THE NAME
//   Confusingly, the dashboard's files are not its own — the widget is a thin
//   wrapper that borrows all of its code from "org.kde.plasma.kicker" and just
//   asks to be drawn full-screen. That is why it is spelled "kickerdash" and
//   not "kickoffdash". It ships in the `kdeplasma-addons` package, which
//   build.sh asks for by name so this line can never point at nothing.
//
// ⚠️ WE ARE DELIBERATELY DIFFERENT FROM THE DESIGN HERE
//   The V2 desktop design (branding/design-system/AquariusOS Desktop Shell.html)
//   removed the launcher and marks this logo as decoration you cannot click.
//   AquariusOS keeps the click. Why:
//     - it looks exactly the same either way — same mark, same size, same spot,
//       so nothing about the design is visibly broken;
//     - on 2026-08-26 we decided the desktop should behave like GNOME, and a
//       full-screen app grid is how GNOME lets you find an app you have not
//       pinned to the dock. Taking it away leaves nothing in its place until
//       the designed search overlay actually exists;
//     - deleting this later is one line, so nothing is being locked in.
//   If Royce would rather match the design exactly, delete the four lines below
//   and add a plain icon widget in their place.
var launcher = topBar.addWidget("org.kde.plasma.kickerdash");
launcher.currentConfigGroup = ["General"];
launcher.writeConfig("icon", "aquarius-logo");
launcher.reloadConfig();

// The name of the app you are using right now, in bold — "Files", "Firefox",
// "Steam". It sits between the logo and the menus, exactly where a Mac puts it,
// and it is the label that tells you which app those File / Edit / View menus
// belong to.
//
// This one is ours. KDE ships no widget that does this, so the image carries a
// small one of its own:
//     system_files/usr/share/plasma/plasmoids/com.aquariusos.appname/
// Nothing to configure — it has no settings. Beginner-facing write-up, including
// what it reads and what it does when no window is focused:
//     docs/app-name-widget.md
topBar.addWidget("com.aquariusos.appname");

// The current application's menus (File, Edit, View…), shown in the bar instead
// of inside the window. This is the piece that makes the top bar feel like a
// Mac menu bar rather than a Windows taskbar.
topBar.addWidget("org.kde.plasma.appmenu");

// A spring. It expands to fill whatever room is left, which is what shoves the
// tray and clock over to the right-hand end.
var topSpacer = topBar.addWidget("org.kde.plasma.panelspacer");
topSpacer.currentConfigGroup = ["General"];
topSpacer.writeConfig("expanding", true);
topSpacer.reloadConfig();

topBar.addWidget("org.kde.plasma.systemtray");

// The clock, at the far right end of the bar.
//
// WHAT THE DESIGN ASKS FOR
//   "Sat Aug 30 21:47" — the date first, then the time, on one line.
//
// HOW THESE FOUR SETTINGS GET THERE
//   showDate           show the date at all. It is on by default; we say it
//                      anyway so the intent is written down.
//   dateFormat         "custom" tells the clock to use our own format string
//                      instead of the one the user's country supplies.
//   customDateFormat   "ddd MMM d" is Qt's spelling for short-day, short-month,
//                      day-without-a-leading-zero → "Sat Aug 30".
//   dateDisplayFormat  0 = Adaptive (the clock decides), 1 = BesideTime,
//                      2 = BelowTime. We want 1, side by side on one line.
//
//   Note the config group is "Appearance", not "General" like the launcher
//   above. Each widget names its own groups and the clock uses that one; using
//   the wrong name writes the settings into a place nothing reads.
//
// WHY THE DATE LANDS ON THE LEFT
//   This is the part worth checking rather than trusting. In the clock's own
//   code, the beside-the-time layout anchors the date label's RIGHT edge to the
//   LEFT edge of the time — "anchors.right: labelsGrid.left" — so the date is
//   drawn before the time, which is the order the design wants. We are not
//   fighting the widget; that is simply how it lays out.
//
// SOURCES (KDE's own code — browsable at lxr.kde.org)
//   plasma-workspace/applets/digital-clock/package/contents/config/main.xml
//     — the setting names, the "Appearance" group, and the Adaptive /
//       BesideTime / BelowTime list in that order.
//   plasma-workspace/applets/digital-clock/package/contents/ui/DigitalClock.qml
//     — the "oneLineDate" state, which is switched on by dateDisplayFormat 1
//       and contains the anchor quoted above.
//
// WHAT WE CANNOT DO FROM A CONFIG FILE, HONESTLY STATED
//   * The design draws the date in the dimmer secondary text colour and the
//     time in the bright one. The clock paints both labels the same colour and
//     offers no setting for it. Making the date dimmer needs a real theme or a
//     replacement widget — that is Tier 2 work, not this file.
//   * The design's mock shows a 24-hour clock (21:47). We do NOT force that
//     here: the 12-vs-24-hour choice follows the country the user picked during
//     setup, which is the right default for a person, and they can change it in
//     the clock's own settings in two clicks. (If we ever did want to force it,
//     the setting is use24hFormat and 2 means 24-hour.)
var clock = topBar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd MMM d");
clock.writeConfig("dateDisplayFormat", 1);
clock.reloadConfig();

// -----------------------------------------------------------------------------
// 2. THE DOCK
// -----------------------------------------------------------------------------
// A floating, centred strip of app icons along the bottom. The three settings
// that make it read as a dock rather than a taskbar are:
//   floating   = true    — it hovers with a gap around it instead of touching
//                          the screen edge
//   alignment  = "center"— it sits in the middle rather than starting at a corner
//   lengthMode = "fit"   — it shrinks to exactly the width of its icons instead
//                          of stretching across the screen
// -----------------------------------------------------------------------------
var dock = new Panel;
dock.location = "bottom";
dock.alignment = "center";
dock.lengthMode = "fit";
dock.floating = true;
dock.opacity = "translucent";
// "dodgewindows": the dock slides out of the way when a window would cover it,
// and comes back when the window moves. Change to "none" for always-on-top, or
// "autohide" for hide-until-you-touch-the-edge.
dock.hiding = "dodgewindows";
dock.height = 2 * Math.ceil(unit * 3 / 2);

// An icons-only task manager: pinned apps and running apps as a single row of
// icons, no text labels.
var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];

// The apps pinned in the dock out of the box.
//
//   "preferred://browser"  whatever the user's default browser is, so this is
//                          still right if they install a different one.
//   "applications:NAME"    a specific app, named by its launcher file. If one of
//                          these apps is not installed, its slot is simply not
//                          shown — a wrong name here cannot break anything.
//
// To find the right name for an app, look in /usr/share/applications/ on a
// running AquariusOS machine and use the filename.
//
// CHECKED 2026-08-30, first bench boot. All five slots appeared in the dock
// with an icon, so all five names resolve — these are the upstream filenames
// and none of them is wrong. What the photo DOES show is that Files, Console
// and Settings draw as pale flat squares with very little colour. That is an
// icon-theme question, not a name question: `kdeglobals` next door asks for
// `breeze-dark`, and whether that theme is actually in the image, and what it
// draws at dock size, can only be answered on the machine —
//     ls /usr/share/icons
// and a close look at the dock. Deliberately not guessed at here; changing a
// name that works would only make it harder to find out.
tasks.writeConfig("launchers", [
    "preferred://browser",
    "applications:steam.desktop",
    "applications:org.kde.dolphin.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:systemsettings.desktop"
]);
// Show windows from every virtual desktop, not just the current one — matches
// how a Mac dock behaves.
tasks.writeConfig("showOnlyCurrentDesktop", false);
tasks.writeConfig("showOnlyCurrentActivity", false);
tasks.reloadConfig();

// -----------------------------------------------------------------------------
// 3. THE DESKTOP ITSELF
// -----------------------------------------------------------------------------
// The wallpaper, and the arrangement of drive and file icons on the desktop.
//
// The two lines that produce the macOS-style right-hand icon column are
// `arrangement` and `alignment`. Both are real, supported settings — this is not
// a trick:
//   arrangement = 1  fill a column downwards, then start a new column
//   alignment   = 1  lay the columns out starting from the RIGHT edge
// Together: icons stack down from the top-right corner, then move leftwards.
// -----------------------------------------------------------------------------
var allDesktops = desktopsForActivity(currentActivity());

for (var i = 0; i < allDesktops.length; i++) {
    var desktop = allDesktops[i];

    // The wallpaper. Setting it here as well as in the global theme's `defaults`
    // file is belt-and-braces: `defaults` covers a brand-new user, this covers
    // the desktop being rebuilt for any other reason.
    desktop.wallpaperPlugin = "org.kde.image";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktop.writeConfig("Image", "file:///usr/share/wallpapers/AquariusThePour/");
    // 2 = scale the picture up until it fills the screen, cropping the overflow.
    // The artwork runs off the edge of the frame by design, so cropping is safe.
    desktop.writeConfig("FillMode", 2);

    // Desktop icons.
    desktop.currentConfigGroup = ["General"];
    desktop.writeConfig("arrangement", 1);    // 0 = rows, 1 = columns
    desktop.writeConfig("alignment", 1);      // 0 = from the left, 1 = from the right
    desktop.writeConfig("sortMode", 1);       // 1 = by name
    desktop.writeConfig("sortDirsFirst", true);
    desktop.writeConfig("iconSize", 2);       // 2 = 48px
    desktop.writeConfig("labelWidth", 1);     // 1 = medium-width label

    desktop.reloadConfig();
}

// =============================================================================
// 4. DRIVE ICONS AND APP ICONS — handled elsewhere, on purpose
// =============================================================================
// Two desktop behaviours Royce asked for on 2026-08-30 are deliberately NOT in
// this file, and it is worth knowing why before somebody tries to add them here.
//
//   * Every mounted drive shows as an icon on the desktop, the system drive
//     included and labelled "AquariusOS", like a Mac.
//   * The desktop never holds application icons.
//
// Neither is something a layout script can do. This script runs ONCE, for a
// brand-new account, and then never again (see "WHEN IT RUNS" at the top) —
// but drives come and go all day, and Royce's existing installs would never see
// a word of it. Both jobs therefore live in a small background program that runs
// for each logged-in person and is switched on for every account, old and new:
//
//     /usr/libexec/aquarius-desktop-volumes
//     /usr/lib/systemd/user/aquarius-desktop-volumes.service
//
// Read the program's comments for the full reasoning, including the honest
// explanation of why "no app icons" is a tidy-up rather than a lock.
//
// ⚠️ WHAT THIS FILE DOES CONTRIBUTE, and must keep contributing: the settings
// written just above are Folder View settings, and Folder View is the component
// that draws files in the Desktop folder as icons. The drive icons ARE files in
// that folder. So if the desktop containment is ever switched from Folder View
// to the plain "Desktop" one, the drive icons stop appearing — and the cause
// would be very hard to guess. Leave it as Folder View.
//
// Also deliberately NOT set here: Folder View's file FILTER (`filterMode`,
// `filterMimeTypes`). Hiding every shortcut file would indeed keep app icons off
// the desktop — and would hide the drive icons with them, because both are the
// same kind of file as far as KDE is concerned. That was checked and rejected;
// the reasoning is written out in the program named above.

// =============================================================================
// TODO — what is deliberately NOT here yet
// =============================================================================
// The genuine macOS top bar also carries the focused window's close / minimise /
// maximise BUTTONS, on the left of the bar.
//
// (The app NAME used to be on this list too. It is now shipped — see the
// com.aquariusos.appname line up in the top bar section.)
//
// KDE Plasma 6 does not ship a widget for the window buttons. The only options
// are third-party add-ons, and the good one is written in C++ and would need a
// compiler stage added to this repo's build. That is a real piece of work with
// real maintenance attached, so it is not being smuggled into a first pass.
//
// When we do want them, the candidate is:
//   - IF-tiger/applet-window-buttons6 (written in C++ — needs a build stage)
