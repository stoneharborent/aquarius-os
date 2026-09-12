#!/usr/bin/bash
# Build our menu-size adapter in a disposable Rocky 9 workshop. Resolve loads
# it with its own Qt 5 libraries inside the app container. The host only stores
# this file; no Fedora app receives it and no extra Qt libraries are shipped.
source "$(dirname "$0")/aq-lib.sh"

say "Building Resolve's menu adapter for Rocky Linux 9"
# Qt's development dependencies can use Rocky's CRB repository, disabled in the
# plain base image. Enable it for this workshop's package transaction only.
dnf -y --enablerepo=crb install gcc-c++ qt5-qtbase-devel pkgconf-pkg-config binutils

AQ_MENU_SOURCE="$(dirname "$0")/resolve-menu/menu.cpp"
AQ_MENU_LIBRARY=/aq-stage/usr/lib64/aquarius/libaquarius-resolve-menu.so
install -d "$(dirname "$AQ_MENU_LIBRARY")"
# pkg-config supplies separate compiler/linker arguments, so expansion here is
# intentional. All headers come from the build container's packaged Qt 5.
# shellcheck disable=SC2046
g++ -std=c++17 -O2 -fPIC -shared -Wall -Wextra -Werror \
    -Wl,-z,relro,-z,now,-z,defs \
    -o "$AQ_MENU_LIBRARY" "$AQ_MENU_SOURCE" \
    $(pkg-config --cflags --libs Qt5Widgets) -ldl
strip --strip-unneeded "$AQ_MENU_LIBRARY"
chmod 0755 "$AQ_MENU_LIBRARY"

# Read the compiled file back. A successful compiler alone does not prove the
# result can load in Resolve's older container or use Resolve's bundled Qt.
readelf --dyn-syms --wide "$AQ_MENU_LIBRARY" > /tmp/aq-menu-symbols
readelf --dynamic "$AQ_MENU_LIBRARY" > /tmp/aq-menu-dynamic
readelf --version-info "$AQ_MENU_LIBRARY" > /tmp/aq-menu-versions
if grep -Eq 'GLOBAL +DEFAULT +[0-9]+ +_ZN12QApplication4execEv$' /tmp/aq-menu-symbols; then
    ok "The Qt event-loop adapter is exported"
else
    bad "The Qt event-loop adapter is missing"
fi
if grep -Eq '\((RPATH|RUNPATH)\)|Qt6' /tmp/aq-menu-dynamic ||
        grep -q 'Qt_5_PRIVATE_API' /tmp/aq-menu-versions; then
    bad "The adapter requests a private Qt API, Qt 6, or a build-machine library path"
else
    ok "The adapter uses public Qt 5 interfaces without a fixed library path"
fi
# EL9 provides glibc 2.34. Refuse a silently newer build environment rather
# than discovering the incompatible binary when a user opens Resolve.
AQ_MENU_GLIBC=$(grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' /tmp/aq-menu-versions | sort -Vu | tail -n 1)
if [[ -n "$AQ_MENU_GLIBC" ]] &&
        [[ $(printf '%s\n' "$AQ_MENU_GLIBC" GLIBC_2.34 | sort -V | tail -n 1) == GLIBC_2.34 ]]; then
    ok "C library requirements fit Rocky 9 ($AQ_MENU_GLIBC)"
else
    bad "Unexpected C library requirement: $AQ_MENU_GLIBC"
fi
AQ_MENU_GLIBCXX=$(grep -oE 'GLIBCXX_[0-9]+(\.[0-9]+)+' /tmp/aq-menu-versions | sort -Vu | tail -n 1)
if [[ -n "$AQ_MENU_GLIBCXX" ]] &&
        [[ $(printf '%s\n' "$AQ_MENU_GLIBCXX" GLIBCXX_3.4.29 | sort -V | tail -n 1) == GLIBCXX_3.4.29 ]]; then
    ok "C++ library requirements fit Rocky 9 ($AQ_MENU_GLIBCXX)"
else
    bad "Unexpected C++ library requirement: $AQ_MENU_GLIBCXX"
fi

# Exercise the actual adapter in a tiny Qt app without a screen. This checks
# menu height, text, action handling, and the surrounding UI. It also starts a
# child process to prove the adapter does not leak into the web browser.
# shellcheck disable=SC2046
g++ -std=c++17 -fPIC -no-pie -Wall -Wextra -Werror \
    -o /tmp/aq-test-resolve-menu "$(dirname "$0")/resolve-menu/test-menu.cpp" \
    $(pkg-config --cflags --libs Qt5Widgets)
QT_QPA_PLATFORM=offscreen LD_PRELOAD="$AQ_MENU_LIBRARY" /tmp/aq-test-resolve-menu
QT_QPA_PLATFORM=offscreen LD_PRELOAD="$AQ_MENU_LIBRARY:libm.so.6" \
    /tmp/aq-test-resolve-menu libm.so.6
ok "Menu sizing and child-process isolation passed in a real Qt application"
aq_finish "Resolve menu adapter"
