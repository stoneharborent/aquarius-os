#!/usr/bin/bash
# ==============================================================================
# STEP 3 — The session floor: everything a desktop needs before it is a desktop
# ==============================================================================
# WHAT THIS STEP IS
#
# There is a layer between "the computer has drivers" and "the computer has a
# desktop" that nobody ever talks about, because on a normal Linux install it
# arrives invisibly with the desktop. On a bare image it does not arrive at all,
# and its absence produces some of the most confusing symptoms in Linux:
#
#   no login screen at all, just a black screen with a cursor
#   apps that cannot open a file picker
#   screen recording that returns a black rectangle
#   fonts that fall back to something that looks like 1998
#
# So: the login screen, the portals, XWayland, Flatpak, fonts, containers.
#
# ONE THING THAT IS NOT HERE: greetd, the small modern login manager the
# Aquarius Session will eventually use. That is Phase R2's job, and it arrives
# with the session it is for. Until then GDM — GNOME's own — is the login
# screen, and GDM is what the fallback desktop expects anyway.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

# ------------------------------------------------------------------------------
# The login screen
# ------------------------------------------------------------------------------
say "The login screen (GDM)"
aq_dnf install gdm

# ------------------------------------------------------------------------------
# Portals
# ------------------------------------------------------------------------------
# A "portal" is the doorway a sandboxed application uses to ask the desktop for
# something it is not allowed to take: open this file, share this screen, print
# this, remember this password. Flatpak apps — which is most of what a creator
# installs — cannot do any of those things without one.
#
# There are three packages and they are not alternatives:
#
#   xdg-desktop-portal         the doorway itself
#   xdg-desktop-portal-gnome   the half that draws GNOME's own dialogs, and the
#                              only one that can do screen sharing on GNOME
#   xdg-desktop-portal-gtk     the fallback for the handful of requests the
#                              GNOME one does not implement
#
# Leaving out the -gnome one is the classic cause of "OBS records a black
# screen", because screen capture on Wayland goes through this and nothing else.
say "Portals (file pickers, screen sharing, printing)"
aq_dnf install \
    xdg-desktop-portal \
    xdg-desktop-portal-gnome \
    xdg-desktop-portal-gtk \
    xdg-user-dirs \
    xdg-user-dirs-gtk

# ------------------------------------------------------------------------------
# XWayland
# ------------------------------------------------------------------------------
# Wayland is the modern display system and it is what AquariusOS runs. Plenty of
# professional software has not moved to it and never will — DaVinci Resolve is
# X11-only on every Linux distribution in 2026. XWayland is the compatibility
# layer that lets those programs run inside a Wayland session without knowing.
#
# It is not optional on a creator machine. Resolve is the reason.
say "XWayland (for X11-only software, including DaVinci Resolve)"
aq_dnf install xorg-x11-server-Xwayland

# ------------------------------------------------------------------------------
# Flatpak and Flathub
# ------------------------------------------------------------------------------
# The creator applications — OBS, Blender, Krita, Kdenlive, Ardour — ship as
# Flatpaks and are installed by the user, not baked into the OS. That decision
# is deliberate (standing decision 4): an app that lives outside the image can
# be updated the day its author releases it, instead of on our build schedule.
#
# ⚠️ HOW THE FLATHUB REMOTE IS ADDED MATTERS, AND THE OBVIOUS WAY IS WRONG.
#
# The obvious way is `flatpak remote-add flathub …` right here in the build. It
# appears to work and it does nothing, because that command writes into
# /var/lib/flatpak, and on an image-based operating system /var is the part of
# the disk that belongs to the machine, not to the image. Everything we write
# there during the build is discarded when a computer boots the image.
#
# The correct way is a small text file in /usr/share/flatpak/remotes.d/. Flatpak
# reads that folder at startup and configures the remote from it. It ships
# inside the image, so it is there on first boot on every machine, and it
# survives every update.
#
# We fetch the file from Flathub rather than typing one out, because it carries
# Flathub's signing key and we should not be hand-copying a key.
say "Flatpak, with Flathub configured system-wide"
# curl is installed here rather than further down because the very next thing
# this script does is use it. The bare bootable image may or may not carry it.
aq_dnf install flatpak curl

AQ_FLATHUB_DIR="/usr/share/flatpak/remotes.d"
AQ_FLATHUB="${AQ_FLATHUB_DIR}/flathub.flatpakrepo"

install -d -m 0755 "${AQ_FLATHUB_DIR}"
if ! curl --retry 3 --retry-delay 5 -fsSL \
    -o "${AQ_FLATHUB}" \
    "https://dl.flathub.org/repo/flathub.flatpakrepo"; then
    echo "AQUARIUS ERROR: could not download Flathub's repository description." >&2
    echo "                Without it the image ships with no app store at all." >&2
    exit 1
fi
chmod 0644 "${AQ_FLATHUB}"

# ------------------------------------------------------------------------------
# Fonts
# ------------------------------------------------------------------------------
# The three AquariusOS typefaces:
#
#   Inter           everything you read in the interface. Fedora calls the
#                   package rsms-inter-fonts, after the designer (Rasmus
#                   Andersson). There is no package called "inter-fonts".
#   JetBrains Mono  the terminal and anything showing code
#   Sora            headlines. Not a package anywhere — it ships as a file in
#                   system_files/ and is copied in by the next step.
#
# Everything else here is the boring floor: Noto covers the world's writing
# systems so a web page in Japanese is not a row of boxes, the colour emoji
# package is why an emoji is an emoji rather than an outline, and Liberation is
# the metric-compatible stand-in for Arial / Times / Courier that makes a Word
# document from a client lay out correctly.
say "Fonts"
aq_dnf install \
    rsms-inter-fonts \
    jetbrains-mono-fonts \
    google-noto-sans-fonts \
    google-noto-serif-fonts \
    google-noto-sans-mono-fonts \
    google-noto-color-emoji-fonts \
    liberation-sans-fonts \
    liberation-serif-fonts \
    liberation-mono-fonts \
    fontconfig

# ------------------------------------------------------------------------------
# Containers
# ------------------------------------------------------------------------------
# On an image-based OS you do not install development tools into the system —
# the system is read-only and replaced wholesale on every update. You put them
# in a container instead, and a container here is not a server thing: it is a
# folder that thinks it is a different Linux distribution, sharing your home
# folder and your screen.
#
# Both tools are here on purpose and they are not the same:
#
#   toolbox     Fedora's own, simple, Fedora-only
#   distrobox   runs ANY distribution — and Phase R3 needs it, because DaVinci
#               Resolve's only supported Linux userland is Rocky Linux, and the
#               plan is to ship a pre-built Rocky container for it
#
# podman is the engine underneath both.
say "Containers (toolbox, distrobox, podman)"
aq_dnf install \
    podman \
    toolbox \
    distrobox

# ------------------------------------------------------------------------------
# The language the machine speaks
# ------------------------------------------------------------------------------
# ⚠️ THIS EXISTS BECAUSE OF THE BENCH, 2026-09-03. Running the shell by hand
# printed:
#
#     Detected locale "C" with character encoding "ANSI_X3.4-1968",
#     which is not UTF-8 ... switched to "C.UTF-8"
#
# A bare Fedora bootc image has NO locale set up. Two things are missing and
# they are different things:
#
#   glibc-langpack-en   the en_US.UTF-8 locale data itself. Without it, that
#                       locale does not exist on the machine and asking for it
#                       does nothing at all. The bare base image ships no
#                       langpack — a downstream flavour like Bazzite would have
#                       brought one in, and this is one of the small floors we
#                       inherited for free before and now lay ourselves.
#   /etc/locale.conf    the file that says which one to USE. systemd reads it,
#                       PAM hands it to every login, and without it every
#                       program falls back to the "C" locale, whose character
#                       set is 1968-era 7-bit ASCII.
#
# The symptoms of leaving it are quiet and slow to diagnose: an accented
# character in a filename drawn as a box, a name truncated at an em dash, a sort
# order that puts "Ångström" after "Zoe". Qt says something; GTK often does not.
#
# en_US.UTF-8 is the default, not a decision about what language anyone must
# use. Changing it is `localectl set-locale LANG=...`, or a personal
# ~/.config/locale.conf, and /usr/bin/aquarius-session honours both.
say "The language the machine speaks (en_US.UTF-8)"
aq_dnf install glibc-langpack-en

# Written here rather than left to first boot, because "first boot sets it up"
# is how a machine ends up with a login session that started before the setup
# ran. In a bootc image /etc is part of the image and merged on update, which is
# exactly what this file wants.
cat > /etc/locale.conf <<'LOCALECONF'
# AquariusOS default. Set by build_files/30-session.sh.
#
# Change it with:  localectl set-locale LANG=de_DE.UTF-8
# (and install that language's data first: rpm-ostree install glibc-langpack-de)
#
# For one user only, put LANG= in ~/.config/locale.conf instead — the Aquarius
# session reads that first, and so does systemd's user manager.
LANG=en_US.UTF-8
LOCALECONF

# ------------------------------------------------------------------------------
# The odds and ends every system needs
# ------------------------------------------------------------------------------
say "Permissions, remote access, and basic tools"
aq_dnf install \
    polkit \
    sudo \
    openssh-server \
    openssh-clients \
    NetworkManager-ssh \
    firewalld \
    htop \
    rsync \
    git \
    unzip \
    zip \
    tar \
    which \
    pciutils \
    usbutils \
    nano \
    vim-enhanced

# ------------------------------------------------------------------------------
# Check the floor
# ------------------------------------------------------------------------------
say "Checking the session floor"

aq_installed \
    gdm \
    glibc-langpack-en \
    xdg-desktop-portal \
    xdg-desktop-portal-gnome \
    xdg-desktop-portal-gtk \
    xorg-x11-server-Xwayland \
    flatpak \
    rsms-inter-fonts \
    jetbrains-mono-fonts \
    google-noto-color-emoji-fonts \
    liberation-sans-fonts \
    podman \
    toolbox \
    distrobox \
    polkit \
    sudo \
    openssh-server

# The locale, read back rather than assumed. Two questions, because they fail
# separately: does the file say what we wrote, and does the locale it names
# actually exist on this machine?
aq_file_has /etc/locale.conf '^LANG=en_US\.UTF-8$' "/etc/locale.conf sets LANG=en_US.UTF-8"

# glibc lists it as "en_US.utf8" in `locale -a` and spells it "en_US.UTF-8" in a
# config file. Same locale, two spellings; this asks about the list's spelling.
if locale -a 2> /dev/null | grep -qix 'en_US.utf8'; then
    ok "the en_US.UTF-8 locale is generated (no more 'not UTF-8' warnings)"
else
    bad "en_US.UTF-8 is named in /etc/locale.conf but is not generated — every program would silently fall back to the 7-bit C locale"
fi

# The Flathub file: does it exist, and does it actually contain a repository
# address and a signing key? A truncated download would leave a file that is
# present and useless.
aq_file_has "${AQ_FLATHUB}" '^\[Flatpak Repo\]' "Flathub file has the right heading"
aq_file_has "${AQ_FLATHUB}" '^Url=https://dl\.flathub\.org/repo/' "Flathub file names the Flathub address"
aq_file_has "${AQ_FLATHUB}" '^GPGKey=' "Flathub file carries Flathub's signing key"

# bootc images keep /var for the machine, not the image. If a Flatpak remote
# ever ends up in there during a build it is a sign somebody used
# `flatpak remote-add`, and it will silently vanish on first boot.
if [ -e /var/lib/flatpak/repo/config ]; then
    bad "a Flatpak remote was written into /var — that is discarded on first boot; use /usr/share/flatpak/remotes.d/ instead"
else
    ok "no Flatpak state written into /var (correct)"
fi

# The two tools Phase R3's Resolve container depends on.
for cmd in distrobox podman flatpak; do
    if aq_have "${cmd}"; then ok "${cmd} is on the path"; else bad "${cmd} is not on the path"; fi
done

aq_finish "Session floor"
