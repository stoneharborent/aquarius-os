# Taking the real names

*The restart becomes the actual AquariusOS. Six clicks and one command, in
order. Assumes no Linux and no GitHub experience.*

---

## What this is

For two days there were two AquariusOSes.

The old one was built on Bazzite. It published six images and it was what the
`main` branch built. The new one — this one, built from scratch on bare Fedora —
had to live somewhere that could not tread on it, so it published under
temporary names ending in **`-next`**, from a branch called
`restart/fedora-bootc`.

The new one has now overtaken the old one on every count, so it takes over. That
means two things swap places:

| | Before | After |
| --- | --- | --- |
| The branch the OS is built from | `restart/fedora-bootc` | `main` |
| The branch the Bazzite line is on | `main` | `bazzite-archive` |
| The image for AMD/Intel graphics | `aquarius-os-next` | `aquarius-os` |
| The image for NVIDIA graphics | `aquarius-os-next-nvidia` | `aquarius-os-nvidia` |

The code half is done and merged. **What is left is the part only you can do,
because it happens in the GitHub website's settings, not in a file.**

Set aside about twenty minutes, most of which is waiting for a build.

---

## Read this before you start

**Nothing here can lose the old operating system.** Step 3 gives all six Bazzite
images a permanent second name, `bazzite-final`, before anything else touches
them. After that, any of them is one command away, forever.

**The order matters and the build enforces it.** A container registry has no
undo: the moment the new build publishes `aquarius-os:latest`, the old image of
that name stops being findable by name. So the build workflow now *refuses to
publish* until the `bazzite-final` tags exist. If you do the steps out of order,
you get a red build with a message telling you what to do — not a lost image.

**One step is expected to fail.** Step 1 below ends in a red ✗, on purpose. It
is the safety catch above, doing its job. Do not go looking for a bug.

---

## Step 1 — the merge (Fable does this, not you)

The code changes land on `restart/fedora-bootc`. GitHub starts a build of both
images.

**Expect that build to go red at the very end**, at a step called *"Check the
Bazzite images were archived first"*. Everything before it — the whole image,
every check — passes. It stops at the doorstep because Step 3 has not happened
yet.

That red run is the safety catch working. Nothing was published. Carry on.

---

## Step 2 — rename the two branches

Both renames are on the same page.

**2a. Rename the old line out of the way.**

1. Go to <https://github.com/stoneharborent/aquarius-os>
2. **Settings** (the tab along the top, on the right)
3. **Branches** (in the left-hand menu)
4. Find **`main`** in the list. Click the **pencil** icon beside it.
5. Type **`bazzite-archive`** and press **Rename branch**.

GitHub will warn you that this is the default branch and that some things will
break. Read it, then continue — the things it lists are covered at the bottom of
this page.

> **What just happened:** `bazzite-archive` is now the default branch, because a
> renamed default branch stays the default under its new name. That is fine and
> it lasts about thirty seconds.

**2b. Give the name to the new line.**

1. Same page. Find **`restart/fedora-bootc`** in the list.
2. Click its **pencil** icon.
3. Type **`main`** and press **Rename branch**.

**2c. Make it the default.**

⚠️ **This does not happen by itself.** GitHub kept `bazzite-archive` as the
default in step 2a, and renaming a *non-default* branch in step 2b does not
change which branch is default. You have to say so:

1. **Settings** → **General** (the first item in the left-hand menu)
2. Scroll to **Default branch**
3. Click the **⇄** (switch) button beside the branch name
4. Choose **`main`** and press **Update**, then confirm.

**How to know it worked:** go back to the repository's front page. The branch
button near the top-left should say **`main`**, and the README you see below it
should be the AquariusOS one that talks about Fedora — not the Bazzite one.

---

## Step 3 — save the Bazzite images

This gives each of the six old images a permanent second name so none of them
can be lost when the new build publishes.

**3a. The dry run — changes nothing.**

1. **Actions** (the tab along the top)
2. **Archive the Bazzite image tags** in the left-hand list
3. **Run workflow** (the grey button on the right)
4. Leave the **Dry run** box **ticked**. Press the green **Run workflow**.

It finishes in under a minute. Open the run and read the table at the top of the
summary. Six rows, each saying *would be archived*. If a row says **no `latest`
found**, stop and say so before going further.

> If "Archive the Bazzite image tags" is not in the left-hand list, Step 2c did
> not take. GitHub only offers the Run-workflow button for workflows on the
> default branch. Go back and set `main` as the default.

**3b. For real.**

Same four clicks, but **untick Dry run** before pressing the green button.

Read the table again. Six rows saying *archived now*, and a green ✓. From this
moment the old operating system is permanently recoverable:

```bash
sudo bootc switch ghcr.io/stoneharborent/aquarius-os-gnome-nvidia:bazzite-final
```

Running it a second time is harmless — anything already archived is left exactly
as it is, never overwritten.

---

## Step 4 — build and publish under the real names

1. **Actions** → **Build AquariusOS** → **Run workflow**
2. Make sure the branch box says **`main`**. Press the green **Run workflow**.

Twenty to forty minutes for both images. The safety catch from Step 1 now passes
in a couple of seconds, and the run goes all the way through to publishing.

**How to know it worked:** the run is green, and its summary says it published
to `ghcr.io/stoneharborent/aquarius-os` and
`ghcr.io/stoneharborent/aquarius-os-nvidia`.

> **New packages start out private.** If Step 5 comes back saying *unauthorized*
> or *manifest unknown*, that is what happened — but it should not, because
> these two package names already exist and are already public from the Bazzite
> days. If it does: <https://github.com/orgs/stoneharborent/packages> → click the
> package → **Package settings → Danger Zone → Change visibility → Public**.

---

## Step 5 — move the bench onto the real name

On the bench PC (**not** on the Mac):

```bash
sudo bootc switch ghcr.io/stoneharborent/aquarius-os-nvidia:latest
sudo systemctl reboot
```

It downloads, stages, and nothing changes until the reboot. Afterwards, check
you are where you think you are:

```bash
bootc status
```

The booted image should read
`ghcr.io/stoneharborent/aquarius-os-nvidia:latest`.

**If you do not like it:** `sudo bootc rollback`, then reboot. The previous
system is still on the disk, whole. The longer walk-through of all of this is
[`bench-rebase.md`](bench-rebase.md).

---

## What happens to the `-next` images

Nothing, and that is the intention.

`aquarius-os-next` and `aquarius-os-next-nvidia` stay in the registry, frozen at
their last build (4 September 2026). Nothing publishes to them again, so
`latest` on either one will simply never move.

A machine still following one of them keeps working and stops receiving updates.
The only such machine is the bench, and Step 5 moves it. If another ever turns
up, the fix is the same one command with the new name in it.

They are not deleted. A tag that nothing points at costs nothing, and deleting
things is how you find out a week later that something pointed at them.

---

## Afterwards — what changes on its own

**The Bazzite nightly build stops.** It was a scheduled build, and GitHub only
runs scheduled builds on the *default* branch. The moment `main` became the new
line, the old workflow stopped being on the default branch, so it stops running.
There is nothing to switch off and no file to edit on `bazzite-archive` — which
is good, because that branch is meant to stay exactly as it was on its last day.

> Worth knowing: between Step 2a and Step 2c, `bazzite-archive` *is* the default
> branch, so its nightly is still armed. Do the three parts of Step 2 in one
> sitting rather than leaving it overnight.

**Old Bazzite runs appear under the new names in the Actions list.** GitHub
files runs by the workflow's *file path*, and both lines happen to use
`.github/workflows/build.yml`. So the left-hand list shows **Build AquariusOS**,
and its history includes the Bazzite builds from before today. Nothing is wrong;
the run pages themselves still say which branch and which commit they were.

**The ISO button appears.** *Build AquariusOS ISO* can now be started from the
Actions tab like any other workflow. Until today the only way in was pushing a
git tag, for the same default-branch reason. The tag still works.

**Open pull requests move with the branch.** Anything targeting the old `main`
(the automatic dependency-update PRs, mostly) is re-pointed at
`bazzite-archive` by GitHub. They are updates to the frozen line and can be
closed.

**Anyone with a local copy has to fix it up.** GitHub redirects web links, but
not `git pull`. On any machine with a clone of this repository:

```bash
git fetch origin
git remote set-head origin -a
git checkout main
```

---

## If something goes wrong

| What you see | What it means | What to do |
| --- | --- | --- |
| The build stops at *"Check the Bazzite images were archived first"* | Step 3 has not been done, or did not finish | Do Step 3, then re-run the build |
| *Archive the Bazzite image tags* is not in the Actions list | `main` is not the default branch yet | Step 2c |
| The archive run says **no `latest` found** for an image | That image was never published, or its package was deleted | Stop and say so — do not run the build |
| The archive run says *already archived (latest has moved on since)* | It was already saved, and the name has since been reused. This is correct | Nothing. The archive is never overwritten |
| The repository front page still shows the Bazzite README | The default branch did not change | Step 2c |
| `bootc status` on the bench still shows a `-next` name | The switch was staged but you booted the old entry | Reboot and pick the top entry in the boot menu |

---

## Where the names live now

One file decides, and everything else reads it: **`aquarius-os.env`**, at the
top of this repository. `IMAGE_NAME` and `NVIDIA_IMAGE_NAME`. Nothing else
hard-codes an image name, and a check in the build (*"The old image names have
not come back"*) fails if a retired name reappears anywhere except the handful
of documents whose job is to record the history — this one included.
