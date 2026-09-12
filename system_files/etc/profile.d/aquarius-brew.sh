# ==============================================================================
# AquariusOS — make the `brew` command work in every terminal
# ==============================================================================
# PLAIN ENGLISH
#
# AquariusOS ships Homebrew, the `brew` command. Installing it is not enough:
# the shell has to be told where it is, or typing `brew` gets you
# "command not found" from a machine that has it.
#
# Every file in /etc/profile.d/ is read by the shell when you open a terminal.
# This is the one that points it at Homebrew.
#
# ⚠️ THIS FILE IS IN /etc, UNLIKE OUR SYSTEMD LINKS, AND THAT IS CORRECT.
# There is no /usr/lib/profile.d — the shell only reads /etc/profile.d, so
# there is no choice to make. It is also the right half of the machine for
# this: it is a preference, and somebody who wants a different one should be
# able to edit it and keep the change through every update.
#
# ------------------------------------------------------------------------------
# ⚠️ THE ONE THING IN HERE THAT LOOKS WRONG AND IS NOT: brew goes at the END
# ------------------------------------------------------------------------------
# The obvious way to write this is the line Homebrew's own instructions give:
#
#     eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
#
# and it puts Homebrew's folder at the FRONT of PATH, so Homebrew's copy of any
# program wins over the system's copy. On a Mac that is exactly right, because
# the whole point there is to get a newer version than Apple ships.
#
# On this operating system it is a trap. Homebrew will happily install its own
# `bash`, its own `systemd`, its own `dbus`, its own `rpm` — usually because
# something else depended on them — and those copies are built for Homebrew, not
# for Fedora. If one of them wins on PATH, the results run from "this behaves
# oddly" to "I cannot log in". It is a real failure that Universal Blue hit and
# wrote up before we did.
#
# So this file does what they now do: it asks brew where everything is, throws
# away the PATH line it suggests, and then adds Homebrew's folders to the END —
# where they are found when nothing else provides the program, and never
# otherwise. The tools you install with brew work exactly as you expect; the
# operating system's own copies keep winning, which is what you want.
#
# ------------------------------------------------------------------------------
# WHAT ABOUT PROGRAMS STARTED BY CLICKING AN ICON?
# ------------------------------------------------------------------------------
# They never read this file — no shell is involved. That is what
# /usr/lib/environment.d/70-aquarius-brew.conf is for, and it follows the same
# end-of-PATH rule for the same reason.
#
# ------------------------------------------------------------------------------
# AND FISH
# ------------------------------------------------------------------------------
# AquariusOS ships no fish shell, so there is no fish version of this file. If
# you install fish yourself, docs/restart/homebrew.md has the two lines to put
# in your own ~/.config/fish/config.fish.
# ==============================================================================

# Everything below is inside one guard, and the guard is the important part: on
# a machine where the first-boot unpack has not happened yet, or where somebody
# has removed Homebrew, this file must do absolutely nothing rather than print
# an error before every prompt.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then

    # Ask brew itself where its folders are, rather than writing the paths out
    # here — that way this file cannot drift out of step with a future Homebrew
    # that moves something.
    #
    # `grep -v` drops brew's own PATH line. See the long note above: we want
    # every variable it sets EXCEPT its idea of where PATH should point.
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv | grep -v '^export PATH=')"

    # brew shellenv sets this; the fallback is for a future version that stops.
    HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}"
    export HOMEBREW_PREFIX

    # And now PATH, our way: appended, so the system always wins. The `case`
    # keeps a nested shell (a terminal inside a terminal, `su -`, tmux) from
    # adding the same folders a second and third time.
    case ":${PATH}:" in
        *":${HOMEBREW_PREFIX}/bin:"*) ;;
        *) PATH="${PATH}:${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin" ;;
    esac
    export PATH

fi
