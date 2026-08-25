# ==============================================================================
# AquariusOS — put our settings folder into KDE's search path
# ==============================================================================
# This eight-line file is what makes /usr/share/aquarius/xdg/kdeglobals count
# for anything. KDE only reads settings from folders listed in a variable called
# XDG_CONFIG_DIRS; this script adds ours to the FRONT of that list, which means
# "check here first".
#
# KDE runs every .sh file in this folder as the desktop starts up, in
# alphabetical order.
#
# ⚠️ THE FILENAME MATTERS. It starts with "zz-" so that it sorts AFTER the file
# called env.sh that Fedora ships in this same folder. env.sh only fills in the
# default list "if the list is currently empty" — so if our script ran FIRST we
# would set the variable, env.sh would then see a non-empty list, skip its own
# work, and Fedora's settings folder would silently vanish from the search path.
# Renaming this file to anything sorting before "env.sh" (for example
# "50-aquarius.sh") would break the desktop in a way that is very hard to spot.
# Do not rename it.
#
# The "if" block below is a copy of env.sh's own fallback. It is here so that
# this script is still correct even if the ordering above ever changes.
# ==============================================================================

if [ -z "${XDG_CONFIG_DIRS}" ] ; then
    XDG_CONFIG_DIRS=/etc/xdg:/usr/share/kde-settings/kde-profile/default/xdg
fi

XDG_CONFIG_DIRS=/usr/share/aquarius/xdg:${XDG_CONFIG_DIRS}
export XDG_CONFIG_DIRS
