# Check for Update

1. Open the Aquarius logo menu and choose **Check for Update**.
2. Enter your administrator password when asked. Reading the system update
   status also needs permission; the window itself stays your normal user.
3. The window reports one of these outcomes:
   - **You're up to date:** the checked image matches your running system.
   - **An update is available:** choose **Update** and approve the password prompt.
   - **Update ready:** an update is already prepared. Save your work, then choose
     **Restart now**, or **Later** to continue working. Nothing restarts automatically.
   - **Permission not given:** choose **Check again** when ready to authorize it.
   - **Couldn't reach the update server:** check your internet and try again.
   - **Couldn't confirm the update status:** try again. The window will never
     call an unreadable or failed check “up to date.” **Details** contains the
     technical explanation if you need help; it stays closed until you open it.

Keep the window open while checking or updating. There is no Cancel button:
interrupting an administrator's update cannot reliably be controlled by a normal
window. You can continue working in other apps. Closing the window is available
again when the operation finishes, including when a password prompt is dismissed.
A second update attempt waits until the first has finished; it cannot replace an
update that is already prepared for restart.

For people who prefer the terminal, `aq update check` and `aq update apply` use
exactly the same checks and password authorization. Neither command reboots.

## What maintainers check

`tests/test-updater.py` exercises digest decisions and failures without touching
the system. The helper uses bootc status format version 1, documented by the
[bootc status manual](https://bootc.dev/bootc/man/bootc-status.8.html). Display
version labels are informational, never the basis for an update decision.

Both image variants must pass the pinned shell's tests. Before publication,
`build_files/check-built-shell.sh` starts the finished image's own labwc and
Quickshell on an invisible display, loading its desktop (including the embedded
lock component) and greeter. Missing source or a load failure stops publication.
This proves they load; logging in, unlocking, and real hardware still need bench
checks.

The installed bootc 1.16.10 has one limitation: its cached update field can
retain an older answer after a registry tag changes back. The helper therefore
uses the complete successful `upgrade --check` result lines from that release's
[implementation](https://github.com/bootc-dev/bootc/blob/v1.16.10/crates/lib/src/cli.rs),
compares the reported digest with structured status, and ignores stale cached
metadata. Unexpected wording stays unknown. A “No changes” response means bootc
already has its configured image; separately pre-pulling an undeployed OSTree
reference outside this updater is not covered by that check. That advanced case
still needs a stronger bootc API before this window can distinguish it.
