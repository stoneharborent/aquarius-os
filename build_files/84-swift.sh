#!/usr/bin/bash
# ==============================================================================
# STEP 84 — Swift, the programming language, comes with the OS
# ==============================================================================
# WHAT THIS STEP IS FOR, IN PLAIN ENGLISH
#
# Royce asked (2026-09-14, FEATURES 022) that Swift be on AquariusOS out of the
# box: open a terminal on a brand-new machine, type
#
#     swift --version
#
# and get an answer, the same way `python3 --version` already answers. Swift is
# the language Apple's own tools are written in, and it is the language Royce
# writes on the Mac. This step is what puts the whole toolchain on the image —
# the compiler, the thing that builds a project (`swift build`), the thing that
# runs it (`swift run`), the interactive prompt (`swift repl`), the Foundation
# library, and the editor helper (`sourcekit-lsp`) that gives an editor
# autocomplete and red squiggles.
#
# Plain-language guide for a person using it: docs/restart/swift.md.
#
# ------------------------------------------------------------------------------
# ⚠️ THE INSTALLER FROM SWIFT.ORG IS NOT AN OPTION, AND THAT IS WHY WE USE AN RPM
# ------------------------------------------------------------------------------
# Swift's own website tells you to install `swiftly`, its installer. On Fedora,
# swiftly stops with "Unsupported Linux platform" and refuses to go further, and
# the loose tar files swift.org offers instead are built against Ubuntu's
# libraries and are nobody's job to keep working here.
#
# Fedora packages the toolchain itself, as `swift-lang`, and that is the
# supported path on this operating system. So that is the one we take. Do not
# "fix" this later by downloading a tarball from swift.org.
#
# ------------------------------------------------------------------------------
# ⚠️ THIS IS THE LARGEST SINGLE THING ON THE IMAGE, AND ROYCE SAID YES ANYWAY
# ------------------------------------------------------------------------------
# A compiler ships a copy of everything it needs to compile with — its own
# clang, its own linker, its own debugger, and a standard library. Fedora's
# figure for `swift-lang` alone is about 3 GB installed, and this step prints
# the real number it finds, every build, so the cost is never a surprise and
# never a guess. Royce accepted that cost knowingly when he asked for it
# (FEATURES 022: "Honest cost: the toolchain is large ... Royce accepted the
# preinstall").
#
# For scale: taking Aquarius Editor OUT of the image on 2026-09-04 saved about
# 4 GB. This puts roughly three quarters of that back. If the image size ever
# has to come down again, THIS is the first thing to look at, and the way to do
# it would be to move Swift into the first-login app chooser rather than to
# trim pieces off a compiler.
#
# ------------------------------------------------------------------------------
# WHAT FEDORA 44 ACTUALLY SHIPS, WHICH IS LESS SPLIT-UP THAN YOU MIGHT EXPECT
# ------------------------------------------------------------------------------
# Fedora builds exactly TWO packages out of Swift (checked against Fedora's own
# package index for Fedora 44, swift-lang 6.3.2-3.fc44, on 2026-09-14):
#
#   swift-lang          the compiler, SwiftPM (`swift build` / `run` / `test` /
#                       `package`), the REPL, `swift-format`, `sourcekit-lsp`,
#                       lldb, and the Swift standard library and Foundation
#   swift-lang-runtime  the small set of shared libraries a Swift PROGRAM needs
#                       in order to run, split out so that a machine which only
#                       runs Swift software does not need the compiler
#
# There is no separate `sourcekit-lsp` package and no separate documentation
# package to skip — everything in the list Royce asked for is in `swift-lang`.
# The step checks that below by asking for each program by name, so the day
# Fedora DOES split one of them out, this build says so instead of shipping an
# image with a missing piece.
#
# ------------------------------------------------------------------------------
# THE FOUR EXTRA PACKAGES, AND WHY THEY ARE NAMED HERE RATHER THAN ASSUMED
# ------------------------------------------------------------------------------
# A Swift compiler on Linux does not link a finished program by itself. It hands
# the last step to the system's C toolchain, and it reads the system's C headers
# to know what the operating system offers.
#
#   gcc, glibc-devel            `swift-lang` REQUIRES these, so they arrive on
#                               their own. They are named again here so that the
#                               read-back proves they are present: without them
#                               `swift build` fails at the very last moment,
#                               with a linker error that reads like a bug in
#                               your code.
#   gcc-c++, libstdc++-devel    `swift-lang` only RECOMMENDS these. A recommend
#                               is installed by default and silently skipped the
#                               moment anybody adds `--setopt=install_weak_deps=
#                               False` to a build. They are what Swift's C++
#                               interoperability needs, and they cost little, so
#                               they are asked for by name and never left to a
#                               default that could change under us.
#
# ------------------------------------------------------------------------------
# THE CHECK THAT ACTUALLY MATTERS
# ------------------------------------------------------------------------------
# `swift --version` printing a number proves almost nothing: a toolchain can
# print its version happily and then fail to compile one line of code. So this
# step builds a real hello-world program with the real `swift build`, in a
# throwaway folder, inside the finished image, and insists on seeing the
# greeting come back out of `swift run`.
#
# If that cannot run here (a build sandbox that forbids something SwiftPM
# needs), the step falls back to compiling and running a single file with
# `swiftc` — and SAYS SO LOUDLY rather than passing quietly, because "the
# package manager was never tested" is exactly the kind of thing that is
# discovered by a person on the bench three weeks later.
#
# Everything the test writes goes in a throwaway folder under /tmp, with HOME
# pointed at it too — SwiftPM writes caches into HOME, and none of that belongs
# in the finished operating system.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

# ------------------------------------------------------------------------------
# 1. Install it
# ------------------------------------------------------------------------------
say "Installing the Swift toolchain from Fedora's own packages"
aq_dnf install \
    swift-lang \
    swift-lang-runtime \
    gcc \
    gcc-c++ \
    glibc-devel \
    libstdc++-devel

aq_installed swift-lang swift-lang-runtime gcc gcc-c++ glibc-devel libstdc++-devel

# ------------------------------------------------------------------------------
# 2. Every program Royce asked for, by name
# ------------------------------------------------------------------------------
# Asked for one at a time, and by the name a person would type, so that a future
# Fedora which moves one of these into a package we are not installing fails the
# build here with the name of the missing thing.
say "The programs the toolchain is supposed to give us"
for prog in swift swiftc swift-build swift-run swift-test swift-package \
    swift-format sourcekit-lsp; do
    if [ -x "/usr/bin/${prog}" ]; then
        ok "/usr/bin/${prog} is present"
    else
        bad "/usr/bin/${prog} is MISSING — Fedora may have split it into a"
        bad "     package we are not installing. Check packages.fedoraproject.org."
    fi
done

# `swift repl` is not a file of its own. Typing it starts the interactive prompt,
# which is the debugger driving a small helper program, so the two things that
# have to exist are that helper and lldb.
say "The interactive prompt (swift repl)"
# /usr/bin/swiftc is a signpost pointing into the toolchain's real folder, which
# is named after the version (/usr/libexec/swift/6.3.2/bin). Following the
# signpost is how we find that folder without hard-coding a version number that
# changes every Fedora release. If it is ever not a signpost, fall back to
# looking for the folder directly rather than checking /usr/bin for files that
# were never meant to be there.
SWIFT_LIBEXEC="$(dirname "$(readlink -f /usr/bin/swiftc)")"
if [ "${SWIFT_LIBEXEC}" = "/usr/bin" ]; then
    SWIFT_LIBEXEC="$(find /usr/libexec/swift -mindepth 2 -maxdepth 2 -type d \
        -name bin 2> /dev/null | head -n 1 || true)"
fi
if [ -d "${SWIFT_LIBEXEC}" ]; then
    echo "  the toolchain's own folder is ${SWIFT_LIBEXEC}"
else
    bad "could not find the toolchain's own folder under /usr/libexec/swift"
    SWIFT_LIBEXEC="/nonexistent"
fi
for prog in repl_swift lldb swift-frontend; do
    if [ -x "${SWIFT_LIBEXEC}/${prog}" ]; then
        ok "${SWIFT_LIBEXEC}/${prog} is present"
    else
        bad "${SWIFT_LIBEXEC}/${prog} is missing — 'swift repl' would not start"
    fi
done
# And the front door itself admits the subcommand exists. `swift repl` with no
# terminal would sit there waiting for typing, so this asks for its help text,
# which prints and exits.
if aq_output_has 'repl' /usr/bin/swift repl --help; then
    ok "'swift repl --help' answers, so the subcommand is really there"
else
    bad "'swift repl --help' said nothing about a repl — the interactive prompt"
    bad "     may not start on a real machine."
fi

# ------------------------------------------------------------------------------
# 3. What version, and how big
# ------------------------------------------------------------------------------
say "Which Swift this is"
if /usr/bin/swift --version > /tmp/aq-swift-version.txt 2>&1; then
    ok "'swift --version' runs"
    sed 's/^/       /' /tmp/aq-swift-version.txt
else
    bad "'swift --version' failed — the compiler is on the image but cannot start:"
    sed 's/^/       /' /tmp/aq-swift-version.txt
fi
# The version line must name Swift and a number. A toolchain that is half
# unpacked can print an error and still exit 0.
aq_file_has /tmp/aq-swift-version.txt 'Swift version [0-9]+\.[0-9]+' \
    "the version line names Swift and a version number"
rm -f /tmp/aq-swift-version.txt

if aq_output_has 'Swift version' /usr/bin/sourcekit-lsp --version; then
    ok "'sourcekit-lsp --version' answers — an editor can get autocomplete"
else
    # Not fatal on its own: some versions print their version to stderr or use a
    # different word. The file being present and runnable is the real check, and
    # step 2 above already made it. This is said, not failed.
    echo "  NOTE: 'sourcekit-lsp --version' printed nothing recognisable. The"
    echo "        program is present and runnable (checked above); this is worth"
    echo "        a look on the bench, not worth stopping a build for."
fi

# ------------------------------------------------------------------------------
# 4. The size, out loud, every build
# ------------------------------------------------------------------------------
# Two numbers, because they answer different questions. `rpm` says what the
# package database thinks it installed; `du` says what is really on the disk.
# They should agree closely, and a large disagreement is worth noticing.
say "How much room Swift takes up (Royce accepted this cost — FEATURES 022)"
rpm -q --queryformat \
    '  %{NAME}-%{VERSION}-%{RELEASE}  %{SIZE} bytes\n' \
    swift-lang swift-lang-runtime
SWIFT_BYTES="$(rpm -q --queryformat '%{SIZE}\n' swift-lang swift-lang-runtime \
    | awk '{ total += $1 } END { print total+0 }')"
echo "  ---"
echo "  Package database total: $((SWIFT_BYTES / 1024 / 1024)) MB"
echo "  On disk, measured:"
du -sh /usr/libexec/swift /usr/lib64/swift 2> /dev/null | sed 's/^/    /' || true
# Nothing here fails the build. The number is information Royce asked to see,
# not a limit — but a toolchain that suddenly measures 20 MB has not unpacked.
if [ "${SWIFT_BYTES}" -gt 500000000 ]; then
    ok "the toolchain is really on the image (over 500 MB of it)"
else
    bad "swift-lang measures only $((SWIFT_BYTES / 1024 / 1024)) MB. A Swift"
    bad "     toolchain is gigabytes. Something did not unpack."
fi

# ------------------------------------------------------------------------------
# 5. THE REAL CHECK: build and run a hello-world, here, now
# ------------------------------------------------------------------------------
say "Building and running a real hello-world with swift build / swift run"

SWIFT_TRY="$(mktemp -d /tmp/aq-swift-try-XXXXXX)"
# SwiftPM writes caches and configuration into HOME. Pointing HOME here keeps
# every byte of that inside the folder we delete at the end of this step.
export HOME="${SWIFT_TRY}/home"
export TMPDIR="${SWIFT_TRY}/tmp"
mkdir -p "${HOME}" "${TMPDIR}"

SWIFT_PKG="${SWIFT_TRY}/hello"
mkdir -p "${SWIFT_PKG}"

SWIFTPM_OK=0
if (
    cd "${SWIFT_PKG}" \
        && /usr/bin/swift package init --type executable --name hello
) > "${SWIFT_TRY}/init.log" 2>&1; then
    ok "'swift package init --type executable' made a project"
else
    bad "'swift package init' failed:"
    sed 's/^/       /' "${SWIFT_TRY}/init.log"
fi

# `swift package init` writes a main file that prints "Hello, world!" already,
# but a greeting we wrote ourselves proves the compiler read OUR source rather
# than something left in a cache.
GREETING="Hello from AquariusOS Swift"
#
# ⚠️ DO NOT "TIDY" THIS BY WRITING Sources/main.swift AND DELETING THE REST.
# Where SwiftPM puts the starter file, and what it is allowed to contain, have
# both moved between Swift versions: some versions write `Sources/main.swift`
# holding plain top-level code, others write `Sources/hello/hello.swift`
# holding an `@main` structure. Swift REFUSES `@main` in a file called
# main.swift, and refuses top-level code anywhere else. So this finds whichever
# file the toolchain in THIS image actually wrote, and replaces it in the shape
# that file's own name allows.
SWIFT_SRC="$(find "${SWIFT_PKG}/Sources" -name '*.swift' -type f 2> /dev/null \
    | head -n 1 || true)"
if [ -n "${SWIFT_SRC}" ]; then
    echo "  the starter file SwiftPM wrote is ${SWIFT_SRC#"${SWIFT_PKG}/"}"
    if [ "$(basename "${SWIFT_SRC}")" = "main.swift" ]; then
        cat > "${SWIFT_SRC}" << EOF
// Written by build_files/84-swift.sh. Foundation is imported deliberately: it
// is the library Swift code on Linux leans on most, and importing it proves
// more than printing a string does.
import Foundation
print("${GREETING}, \(ProcessInfo.processInfo.processorCount) cores")
EOF
    else
        cat > "${SWIFT_SRC}" << EOF
// Written by build_files/84-swift.sh. See the note about main.swift in there.
import Foundation

@main
struct Hello {
    static func main() {
        print("${GREETING}, \(ProcessInfo.processInfo.processorCount) cores")
    }
}
EOF
    fi
else
    bad "'swift package init' left no Swift file behind to build"
fi

if (cd "${SWIFT_PKG}" && /usr/bin/swift build) > "${SWIFT_TRY}/build.log" 2>&1; then
    ok "'swift build' compiled it"
    if (cd "${SWIFT_PKG}" && /usr/bin/swift run) > "${SWIFT_TRY}/run.log" 2>&1; then
        if grep -q "${GREETING}" "${SWIFT_TRY}/run.log"; then
            SWIFTPM_OK=1
            ok "'swift run' printed our greeting — the toolchain really works:"
            sed 's/^/       /' "${SWIFT_TRY}/run.log"
        else
            bad "'swift run' ran but did not print our greeting. It printed:"
            sed 's/^/       /' "${SWIFT_TRY}/run.log"
        fi
    else
        bad "'swift run' failed:"
        sed 's/^/       /' "${SWIFT_TRY}/run.log"
    fi
else
    echo "  NOTE: 'swift build' did not finish here. Its output:"
    sed 's/^/       /' "${SWIFT_TRY}/build.log"
fi

# ------------------------------------------------------------------------------
# 5b. If SwiftPM could not run here, fall back — and say so loudly
# ------------------------------------------------------------------------------
if [ "${SWIFTPM_OK}" = "1" ]; then
    ok "the package manager was tested for real; no fallback was needed"
else
    say "⚠️ FALLING BACK TO A COMPILE-ONLY CHECK — READ THIS"
    echo "  'swift build' / 'swift run' could NOT be tested inside this build"
    echo "  container. The output above says why. This step is now only proving"
    echo "  that the COMPILER works, with a single file and no package manager."
    echo
    echo "  ⚠️ WHAT THAT MEANS FOR ANYBODY READING THIS LOG: 'swift build' and"
    echo "     'swift run' on a real AquariusOS machine are UNTESTED by this"
    echo "     build. They are the first two things to try on the bench —"
    echo "     docs/restart/swift.md has the five steps."
    echo

    cat > "${SWIFT_TRY}/solo.swift" << EOF
import Foundation
print("${GREETING}")
EOF
    if (cd "${SWIFT_TRY}" && /usr/bin/swiftc solo.swift -o solo) \
        > "${SWIFT_TRY}/swiftc.log" 2>&1; then
        ok "'swiftc' compiled a single file (so the compiler and the linker work)"
        if "${SWIFT_TRY}/solo" | grep -q "${GREETING}"; then
            ok "and the program it produced ran and printed the greeting"
        else
            bad "the compiled program did not print the greeting"
        fi
    else
        bad "'swiftc' could not compile one file either. Swift is on the image"
        bad "     but cannot compile anything — this is a broken toolchain:"
        sed 's/^/       /' "${SWIFT_TRY}/swiftc.log"
    fi
fi

# ------------------------------------------------------------------------------
# 6. Leave nothing behind
# ------------------------------------------------------------------------------
# Everything the test made lives under one folder, including HOME. It goes.
rm -rf "${SWIFT_TRY}"
unset HOME TMPDIR
if [ -e "${SWIFT_TRY}" ]; then
    bad "${SWIFT_TRY} survived — the build left build rubbish in the image"
else
    ok "the throwaway project, its caches and its HOME are gone"
fi

aq_finish "Swift comes with the OS"
