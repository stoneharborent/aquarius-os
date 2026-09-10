# Resolve's “Login via web” button

Resolve runs inside its own Rocky Linux environment. Your web browser runs on
AquariusOS, outside it. The button needs a small bridge between the two.

The September 10 bench inspection found that the environment still had Rocky's
ordinary `xdg-open` command, which looks for a browser inside that environment.
Resolve's installed binary also contains an absolute `/usr/bin/xdg-open` command.
Adding a browser command to PATH alone would not cover that call.

On the next launch after this OS update, AquariusOS installs its browser bridge
at that exact path **inside Resolve's environment**. It preserves the previous
opener at `/usr/libexec/aquarius-original-xdg-open`. Repeated launches do nothing
when the installed bridge already matches the OS version. This also repairs an
existing installation; you do not need to reinstall Resolve or download a new
runtime image.

The bridge asks `distrobox-host-exec` to run the desktop's own `xdg-open`. Your
usual browser choice and file associations therefore apply. Distrobox starts
that command with the desktop's environment, so Resolve's private Qt libraries,
interface scale and hard-coded display name do not follow the browser outside.
The host opener has a different filesystem path in a different environment;
it does not call the container bridge again.

If setup fails, Resolve still starts and a notification explains that browser
integration needs attention. If a link cannot be handed off, a notification asks
you to check your default browser. The bridge never prints the link itself:
sign-in links can contain temporary authentication values.

## What has been checked

- The real installed container can run a harmless command on the host through
  Distrobox's bridge.
- A synthetic URL passed from that container reached a temporary browser stub
  unchanged as one argument. Isolated MIME configuration prevented that test
  from changing the user's browser preference.
- A deliberately wrong container display (`:99`) became the actual desktop's
  display (`:1`). Resolve's library path and Qt scale did not reach the stub.
- Automated checks cover punctuation in links, local paths with spaces,
  generic failure notifications, migration from a file or symlink, repeated
  setup, an updated bridge, and a missing source file. The original opener
  survives all migrations.

## Sign-in still needs a real acceptance check

Click **Login via web** in Resolve, finish Blackmagic's sign-in in the browser,
and confirm Resolve shows the signed-in account. This step needs the account
owner and has not been called complete by the automated tests.

Inspection of the installed program shows OAuth authorization-code and
`redirect_uri` handling, but does not establish which return URL this particular
login flow chooses. We do not register an invented callback protocol or modify
Blackmagic's authentication requests. The existing container shares the host
network, so this fix does not introduce a new network boundary if Blackmagic
uses a local return listener. Opening the browser successfully and completing
account sign-in are separate acceptance checks.

Distrobox documents the supported host-command bridge in its
[host-exec guide](https://distrobox.it/usage/distrobox-host-exec/).
