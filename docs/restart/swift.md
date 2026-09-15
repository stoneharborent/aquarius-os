# Swift on AquariusOS — what works, and what does not

*Written 2026-09-14 for Phase R8 (FEATURES 022). Assumes you have never used
Linux.*

---

## The one-paragraph version

AquariusOS comes with **Swift** already on it, on both images. Swift is the
programming language Apple made, and it is the language Royce writes on the
Mac. Open a terminal on a brand-new AquariusOS machine, type `swift --version`,
and it answers — no installing, no downloading, no setup. Everything that makes
Swift usable is there: the compiler, the project tool (`swift build`, `swift
run`), the interactive prompt (`swift repl`), the Foundation library, and the
helper that gives an editor autocomplete and red squiggles (`sourcekit-lsp`).

**And there is a real limit, stated up front because it is the whole point of
the page:** Swift on Linux is the *language* and its *general-purpose
libraries*. It is not the part of Swift that draws windows and buttons on a
Mac. The [What does NOT work](#what-does-not-work) section says exactly what
that rules out, including the Aquarius apps on the Mac.

---

## Your first five steps

**1. Open a terminal, and check Swift is there.**

Press the key with the Aquarius mark on it, type "Terminal", press Return. Then
type this and press Return:

```
swift --version
```

It prints something like `Swift version 6.3.2` and the word `Target:`. If it
does, everything on this page works.

**2. Make a new project.**

A "project" here is just a folder Swift knows how to build. Make one and step
into it:

```
mkdir -p ~/Code/hello
cd ~/Code/hello
swift package init --type executable
```

That last command fills the folder with a starter program that prints
"Hello, world!".

**3. Run it.**

```
swift run
```

The first time is slow — it is compiling. After that it is quick. You should
see `Hello, world!`.

**4. Change it, and run it again.**

Open the folder in a text editor (`nautilus .` opens it in Files; double-click
the `.swift` file under `Sources`). Change the words inside the quotation marks,
save, and type `swift run` again. That is the whole loop: edit, `swift run`,
look.

**5. Try the interactive prompt.**

```
swift repl
```

This gives you a `>` where you can type one line of Swift at a time and see the
answer immediately — a calculator that speaks Swift. Type `1 + 1` and press
Return. Type `:quit` to leave.

---

## The handful of commands worth knowing

```
swift --version              which Swift this is
swift package init           start a new project in the folder you are in
   --type executable            ...one that runs (as opposed to a library)
swift build                  compile it, do not run it
swift run                    compile it and run it
swift test                   run the project's tests
swift repl                   the interactive prompt
swift-format                 tidy the layout of a Swift file
sourcekit-lsp                the editor helper (you never run this by hand —
                             your editor starts it for you)
```

---

## What does NOT work

This is the honest half of the page, and it is not a list of things that are
coming later. These are permanent.

### No SwiftUI. No AppKit. No UIKit.

Those three are Apple's libraries for **drawing a user interface** — windows,
buttons, sliders, lists, the lot. They are not part of the Swift language; they
are part of macOS, iOS and iPadOS, and Apple has never released them for any
other operating system. Nothing on this computer can provide them, no package
will install them, and no amount of work on our side changes that.

So Swift on AquariusOS is good for:

- command-line tools and scripts
- servers and web back ends
- anything that reads files, talks over a network, or does arithmetic
- learning and practising the language itself
- the parts of a Mac project that are pure logic with no screen in them

and it cannot compile anything whose job is to put a window on the screen using
Apple's frameworks.

### The Mac Aquarius apps do not run here, and Swift being installed does not change that

This is worth saying plainly, because "Swift is on the OS now" sounds like it
should mean the Mac apps come across. It does not, and that is a standing
decision of this project, quoted faithfully from `CLAUDE.md`, standing decision
number 6:

> **The Swift Aquarius apps cannot be ported as-is.** They use Apple-only
> frameworks. The Linux apps are the Electron Editor and the Tauri Writer;
> anything else comes via its own cross-platform build. Never claim otherwise
> in docs or marketing copy.

The Apple-only frameworks in that sentence are the SwiftUI/AppKit/UIKit above.
A Swift compiler on Linux compiles Swift *code*; it cannot conjure the Apple
libraries that code is written against. The Linux versions of the Aquarius apps
are, and remain, **Aquarius Editor** (Electron) and **Aquarius Writer** (Tauri).

### Other things that are simply not here

- **Xcode.** It is Mac-only software and has no Linux version at all. On
  AquariusOS you use a text editor plus `swift build` — or an editor with a
  Swift extension, which talks to the `sourcekit-lsp` already on this machine.
- **Building iPhone, iPad, Apple Watch or Mac apps.** Those need Apple's SDKs
  and Apple's signing tools, both of which run only on a Mac.
- **Swift Playgrounds.** Mac and iPad only. The `swift repl` above is the
  nearest thing here.

---

## Where the toolchain came from, and why not swift.org's installer

Swift's own website tells you to install `swiftly`, its installer. On Fedora,
`swiftly` stops with **"Unsupported Linux platform"** and refuses to go any
further, and the loose tar files swift.org offers instead are built against
Ubuntu's libraries and are nobody's job to keep working here.

Fedora packages the toolchain itself, as `swift-lang`, and updates it along with
everything else. That is the supported path on this operating system, so that is
the one AquariusOS takes. It arrives with the image and updates with the image:
you never install it, and you never update it by hand.

**If you are ever tempted to "fix" this with a tarball from swift.org: don't.**
It would sit in a folder no AquariusOS update ever touches, and it would drift
out of step with the rest of the machine.

---

## It is big, and that was a deliberate choice

The Swift toolchain is roughly **3 GB** installed — the single largest thing on
the image. That is not waste: a compiler ships its own copy of everything it
needs, including its own clang, its own linker, its own debugger and the whole
standard library.

Royce asked for Swift to be preinstalled knowing that number (FEATURES 022), so
it is baked in rather than offered in the first-login app chooser. The build
step prints the real measured size on every single build, so the cost is always
visible and never a guess.

If the image ever has to get smaller again, this is the first place to look —
and the answer would be to move Swift into the app chooser, not to trim pieces
off a compiler.

---

## If something goes wrong

**`swift: command not found`** — you are on an image built before 14 September
2026. Run `aq update` (or the "Check for Update" item in the Aquarius menu),
restart, and try again.

**`swift build` fails with an error mentioning `ld`, `linker` or a missing
header** — Swift hands the last step of a build to the system's C tools. Those
ship with the image (`gcc`, `glibc-devel`, `gcc-c++`, `libstdc++-devel`), so if
they are genuinely missing something has gone wrong with the image itself, not
with your project. Report it rather than installing things by hand.

**`swift build` fails on a project copied from the Mac** — look for `import
SwiftUI`, `import AppKit` or `import UIKit` near the top of the files it names.
That is the limit described above, not a fault.

**It is very slow the first time** — that is normal. Swift compiles a lot on
the first build of a project and caches the result. The second `swift run` is
much faster.

---

## Where this is built

- The build step: [`../../build_files/84-swift.sh`](../../build_files/84-swift.sh).
  It installs the packages, checks every program by name, prints the version and
  the measured size, and then — the check that actually matters — builds and
  runs a real hello-world with `swift build` and `swift run` inside a throwaway
  folder, which it then deletes.
- The recipe wiring: step **7n** in the `Containerfile`.
- The feature entry and Royce's ask: **FEATURES 022**, one folder above the repo.
