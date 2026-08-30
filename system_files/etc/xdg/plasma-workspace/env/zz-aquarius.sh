# shellcheck shell=sh
# ==============================================================================
# AquariusOS — put our settings folder into KDE's search path
# ==============================================================================
# (The line above is not a shebang and this file is not a program. KDE *sources*
# it into a shell it has already started, so it must not have a shebang — that
# one comment is how shellcheck is told which shell to check it as.)
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

# ------------------------------------------------------------------------------
# AND ONE MORE FOLDER, ON HANDHELDS ONLY
# ------------------------------------------------------------------------------
# A handheld needs a couple of settings a desktop PC actively does not want — the
# big one being "turn the game controller into a mouse", which is essential on a
# device with no mouse and a nuisance on one with a mouse already. Those live in
# their own folder next door.
#
# The folder only EXISTS on the handheld image: it is shipped in the repo and
# then deleted again on the two desktop images, in build_files/build.sh. So the
# test below is simply "is this a handheld?", asked in the most direct way
# available to a shell script that runs long before anything else is up.
#
# It goes in FRONT of our normal folder so that, if the two ever set the same
# key, the more specific answer is the one that wins. Today they set different
# keys and the order does not matter; it is written this way so it still reads
# correctly the day they do overlap.
if [ -d /usr/share/aquarius/xdg-handheld ] ; then
    XDG_CONFIG_DIRS=/usr/share/aquarius/xdg-handheld:${XDG_CONFIG_DIRS}
fi

export XDG_CONFIG_DIRS
