# ==============================================================================
# "Mac or Windows" — the AquariusOS page in KDE's System Settings
# ==============================================================================
# WHAT THIS BUILDS
#
# One small plugin, kcm_aquariuskeys.so, which KDE's System Settings app loads
# to draw a page under "Appearance & Style". The page offers the same two
# choices as everything else in AquariusOS — Mac keys or Windows keys — and
# applies them by running `aq keys mac` or `aq keys windows`, exactly as a
# person would type in a terminal.
#
# ------------------------------------------------------------------------------
# ⚠️ WHY THIS HAS TO BE COMPILED AT ALL. IT WAS CHECKED, NOT ASSUMED.
# ------------------------------------------------------------------------------
# A page made only of QML text files, with nothing to compile, would be far
# nicer to ship. On Plasma 5 that existed. On Plasma 6 it does not, and this was
# verified against the actual Fedora 44 packages on 2026-09-16 rather than
# remembered:
#
#   * every settings page Plasma itself ships is a compiled .so file in
#     /usr/lib64/qt6/plugins/plasma/kcms/systemsettings/ — there is not one
#     QML-only page among them;
#   * the old QML-only route went through KPackage, and KF6's kcmutils no
#     longer installs a "kcms" KPackage structure for it. The only packages on
#     Fedora 44 that still provide one are kf5-plasma (the old, dead line) and
#     a wallpaper plugin.
#
# So: a compiled plugin it is. It is about a hundred kilobytes, and none of the
# compiler that built it goes anywhere near the finished operating system —
# see build_files/73-keys-kcm-build.sh, which builds this in a throwaway
# container, the same way xremap is built.
#
# ------------------------------------------------------------------------------
# WHAT EACH PIECE DOES
# ------------------------------------------------------------------------------
#   kcm_aquariuskeys.h/.cpp   the plugin: reads the mode, runs `aq`
#   kcm_aquariuskeys.json     the page's name, icon, search words, and WHERE IN
#                             SYSTEM SETTINGS IT APPEARS
#   ui/main.qml               what the page looks like. The "ui" folder name is
#                             not a choice — KDE's own build macro looks for
#                             exactly that folder and bakes what it finds into
#                             the plugin.
# ==============================================================================

cmake_minimum_required(VERSION 3.20)

project(aquarius-keys-kcm VERSION 1.0)

# The versions AquariusOS is built against. These are floors, not pins: Fedora
# 44 shipped KF6 6.30 and Qt 6.11 when this was written (2026-09-16). The pin
# that matters is the Fedora version, which lives in the Containerfile.
set(QT_MIN_VERSION "6.6.0")
set(KF6_MIN_VERSION "6.0.0")

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Qml Quick)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    CoreAddons     # KPluginFactory — how KDE loads a plugin at all
    I18n           # the wrapper KDE pages use for their text
    KCMUtils       # what a settings page IS
)

# kcmutils_add_qml_kcm is KDE's own macro for "a settings page written in QML".
# It does three things we would otherwise have to get right by hand: installs
# the plugin into plasma/kcms/systemsettings (which is the ONLY folder System
# Settings looks in), reads kcm_aquariuskeys.json as the page's description,
# and bakes everything in the ui/ folder into the plugin so the page cannot
# lose its own interface.
#
# DISABLE_DESKTOP_FILE_GENERATION is deliberate, and it is the one line here
# that is about GNOME. The macro would otherwise write a menu entry for this
# page into /usr/share/applications/ — the folder BOTH desktops read — and a
# KDE-only settings page must never turn up in GNOME's app grid. We ship no
# menu entry at all, and nothing is lost by it: System Settings finds the page
# from the plugin's own description (kcm_aquariuskeys.json), its search box
# reads the keywords from the same place, and `kcmshell6 kcm_aquariuskeys`
# opens it on its own from a terminal.
# (The macro itself arrives with find_package(KF6 ... KCMUtils) above — its
# config file pulls in KF6KCMUtilsMacros.cmake, so there is nothing to include
# here by hand.)
add_definitions(-DTRANSLATION_DOMAIN=\"kcm_aquariuskeys\")

kcmutils_add_qml_kcm(kcm_aquariuskeys DISABLE_DESKTOP_FILE_GENERATION)

target_sources(kcm_aquariuskeys PRIVATE
    kcm_aquariuskeys.cpp
    kcm_aquariuskeys.h
)

target_link_libraries(kcm_aquariuskeys PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    KF6::CoreAddons
    KF6::I18n
    KF6::KCMUtils
    KF6::KCMUtilsQuick
)
