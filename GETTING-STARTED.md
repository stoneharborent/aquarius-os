# Getting Started — putting AquariusOS on GitHub

**Who this is for:** you, Royce, with zero Linux or OS experience. Every step is spelled out.
Nothing here can damage your Mac. Nothing here costs money.

**Time:** about 30 minutes of clicking, then ~30–60 minutes of waiting while GitHub builds.

**What you'll have at the end:** a real operating system image, built by GitHub, published
under your account, that you can later turn into a USB installer.

Do the steps in order. If a step's result doesn't match what's described, stop there rather
than pushing on — the next steps assume the previous one worked.

---

## Before you start: two words you'll see constantly

- **Repository (repo)** — a folder of files stored on GitHub. This project is one repo.
- **Push** — uploading your local changes to GitHub. Every push triggers a new OS build.

That's it. That's the vocabulary.

---

## Step 0 — Fill in your GitHub username (2 minutes)

> **Already done in this repo.** These files are set to `stoneharborent`. You only need this
> step if you are starting from a fresh copy of the template, where the files still contain
> the `CHANGEME-github-username` placeholder. Skip to Step 1 otherwise.

Four files have a placeholder that must become your real GitHub username — the part of your
profile URL after `github.com/`. If your profile is `github.com/royceadkins`, your username is
`royceadkins`.

Open a Terminal on your Mac (press `Cmd+Space`, type "Terminal", press Enter), then paste this
**after replacing `YOUR-USERNAME` with your actual username**:

```bash
cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/Workflow/Branches/Apps/AquariusOS/os-image

# ⬇️ Change YOUR-USERNAME on this line only
MYNAME="YOUR-USERNAME"

# Safety check: refuses to run if the line above wasn't edited. Without this, an empty
# MYNAME silently DELETES the placeholder and you get "ghcr.io//aquarius-os" — an
# address with no owner in it, which builds fine but installs the wrong thing.
if [ -z "${MYNAME}" ] || [ "${MYNAME}" = "YOUR-USERNAME" ]; then
  echo "STOP: edit the MYNAME line first. Nothing was changed."
else
  sed -i '' "s/CHANGEME-github-username/${MYNAME}/g" \
    aquarius-os.env \
    disk_config/iso.toml \
    disk_config/iso-kde.toml \
    disk_config/iso-gnome.toml
  echo "Done. Now verify below."
fi
```

Now verify. Paste this **exactly** — it checks for the finished result, not just the absence
of the placeholder:

```bash
grep -rn "ghcr.io/${MYNAME}/aquarius-os" disk_config/ && \
grep -n "REPO_ORGANIZATION" aquarius-os.env
```

You should see your username in all three `disk_config` files plus `aquarius-os.env`.

Finally, confirm nothing was left empty or unreplaced:

```bash
grep -rn "CHANGEME\|ghcr.io//" . --exclude-dir=.git
```

That should print nothing at all. If it prints a line containing `ghcr.io//` (two slashes,
no name between them), the substitution ran with an empty username — re-check the `MYNAME`
line and run the block again.

---

## Step 1 — Create the GitHub repo (5 minutes)

1. Go to **https://github.com/new** (sign in if asked).
2. **Repository name:** type exactly `aquarius-os`
   — lowercase, with the hyphen. This name becomes part of the OS image address, and the
   build config expects it.
3. **Description:** `AquariusOS — the OS for gamers and creators.`
4. **Public or Private:** choose **Public**.
   - Public is free and lets anyone install AquariusOS later. It also means the built OS
     image is publicly downloadable, which is the whole point eventually.
   - Private also works for now, but it makes installing more awkward (users need a login),
     and free-account build minutes are limited on private repos. You can switch later.
5. **Do NOT tick** "Add a README file", "Add .gitignore", or "Choose a license". We already
   have all three. Ticking them creates a conflict you'd have to untangle.
6. Click the green **Create repository** button.

You'll land on a mostly-empty page with setup instructions. Leave this tab open — you need
the URL from it in the next step. It looks like `https://github.com/YOUR-USERNAME/aquarius-os`.

---

## Step 2 — Push this code to that repo (5 minutes)

Back in Terminal. Again, **replace `YOUR-USERNAME`** in the third command:

```bash
cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/Workflow/Branches/Apps/AquariusOS/os-image

# Save the username fix from Step 0 as a commit
git add -A
git commit -m "Set GitHub username in image and ISO config"

# ⬇️ Change YOUR-USERNAME here
git remote add origin https://github.com/YOUR-USERNAME/aquarius-os.git

# Send everything to GitHub
git push -u origin main
```

**What "origin" means:** it's just a nickname for "the copy of this repo that lives on
GitHub." You only set it once.

**If it asks for a username and password:** GitHub no longer accepts your account password
here. Two ways through it, pick one:

- **Easiest — install the GitHub CLI** and let it handle login:
  ```bash
  brew install gh
  gh auth login
  ```
  Answer: `GitHub.com` → `HTTPS` → `Yes` (authenticate Git) → `Login with a web browser`.
  It shows a one-time code, you paste it in the browser it opens. Then re-run the
  `git push -u origin main` command above.

- **Or use a Personal Access Token**: GitHub → your avatar → Settings → Developer settings →
  Personal access tokens → Tokens (classic) → Generate new token, tick the `repo` and
  `write:packages` boxes, and paste the token when git asks for your *password*.

**Confirm it worked:** refresh your repo page in the browser. You should now see
`README.md`, `Containerfile`, `build_files`, and the rest of the files.

---

## Step 3 — Turn on the build robot (Actions) (2 minutes)

GitHub disables automated workflows on a freshly pushed repo until you say yes.

1. On your repo page, click the **Actions** tab (top row: Code, Issues, Pull requests, Actions…).
2. You'll see a message about workflows existing in this repository. Click the green button —
   it says something like **"I understand my workflows, go ahead and enable them"**.
3. You should now see three workflows listed in the left sidebar:
   - **Build AquariusOS image** — the main one; builds the OS
   - **Build AquariusOS ISO (Titanoboa)** — makes the USB installer; you run this manually later
   - **Build AquariusOS disk images** — makes a virtual-machine disk for testing; also manual

---

## Step 4 — Set up image signing (10 minutes) — do this before the first build

**What signing is, plainly:** a cryptographic signature that proves an AquariusOS image really
came from you and wasn't tampered with in transit. Universal Blue images all do this, and the
build workflow we inherited includes a signing step.

**Why you can't skip it:** the build's final step runs the signing command. With no key
configured, that step fails and the run shows a **red X** — even though the image itself was
built and published fine. Set the key up now and the build goes green.

### 4a. Install cosign (the signing tool) on your Mac

```bash
brew install cosign
```

(If `brew` isn't found, install Homebrew first from https://brew.sh — one paste-in command.)

### 4b. Generate your key pair

```bash
cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/Workflow/Branches/Apps/AquariusOS/os-image
COSIGN_PASSWORD="" cosign generate-key-pair
```

This creates two files:
- `cosign.key` — **the private key. Secret. Never share it, never commit it.**
- `cosign.pub` — the public key. Safe to share; that's the point of it.

The `COSIGN_PASSWORD=""` part makes the key password-free, which is required for GitHub's
robot to be able to use it unattended.

> ⚠️ `cosign.key` is already listed in `.gitignore`, so git will refuse to commit it by
> accident. Don't work around that. If it ever does get pushed publicly, delete the repo's
> key, generate a new pair, and replace the secret.

### 4c. Give the private key to GitHub as a secret

1. Go to your repo → **Settings** (the far-right tab) → in the left sidebar,
   **Secrets and variables** → **Actions**.
2. Click the green **New repository secret**.
3. **Name:** `SIGNING_SECRET` — exactly that, all caps with the underscore.
4. **Secret:** paste the *entire* contents of `cosign.key`. To copy it to your clipboard:
   ```bash
   cat cosign.key | pbcopy
   ```
   Then press `Cmd+V` in the box. It should start with `-----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----`.
   **Make sure it's the `.key` file, not the `.pub` file.**
5. Click **Add secret**.

### 4d. Commit the public key

The public key is meant to be public — commit it so others can verify our images later:

```bash
git add cosign.pub
git commit -m "Add cosign public key"
git push
```

> Note: pushing this also kicks off your first build. That's fine — head to Step 5.

---

## Step 5 — Watch the first build (30–60 minutes, mostly waiting)

If the push in step 4d didn't start a build, start one by hand:

1. Repo → **Actions** tab → click **Build AquariusOS image** in the left sidebar.
2. On the right, click **Run workflow** → keep the branch as `main` → click the green
   **Run workflow** button.
3. Wait ~10 seconds and refresh. A new run appears at the top with a **yellow dot** (running).

Click into the run. You'll see **two jobs**, not one:

- **Build and push image (base)** — the AMD/Intel AquariusOS
- **Build and push image (nvidia)** — the NVIDIA one

They run at the same time and are independent. Click either to watch its live log.

**What you're looking at:** each line is one step. The big one is "Build Image" — that's
GitHub downloading Bazzite (several GB) and running our build script on top of it. The
"Rechunk" step afterwards is repackaging and is normally the slowest part. This is why we
don't build on your Mac.

**If one job is green and the other is red**, that's deliberate — they're set up so a problem
with one can't stop the other from shipping. Read the red one's log; the green one's output
is fine and already published.

**When it finishes:**
- ✅ **Green checkmark** — it worked. The OS exists. Go to Step 6.
- ❌ **Red X** — click the failed step to expand its log; the actual error is usually in the
  last 20 lines. Common first-time causes:
  - *"Error: no such secret SIGNING_SECRET" / cosign errors* → Step 4 wasn't finished.
  - *`dnf5` can't find a package* → a typo in `build_files/build.sh`.
  - *A network/timeout error partway through* → not your fault. Click **Re-run all jobs**.

A first build taking 30–60 minutes is normal. Later builds are faster.

---

## Step 6 — Where the OS actually lives

Your built OS is published to **GitHub Container Registry (GHCR)** — GitHub's storage for
container images. Every run produces **two** packages, because there are two AquariusOS
images (see "Which image do I pick?" just below):

```
ghcr.io/YOUR-USERNAME/aquarius-os:latest          ← AMD / Intel graphics
ghcr.io/YOUR-USERNAME/aquarius-os-nvidia:latest   ← NVIDIA graphics
```

To see them: go to your **GitHub profile page** (not the repo) → the **Packages** tab. You'll
see both listed, with tags and publish dates.

**Make each one public** (do this once per package, or nobody can install it):
On the package page → **Package settings** (right side) → scroll to **Danger Zone** →
**Change package visibility** → **Public**.

> ⚠️ These are two separate packages. Making `aquarius-os` public does **not** make
> `aquarius-os-nvidia` public. Do it twice. The first time the NVIDIA image is built, a new
> package appears in that list and starts out private, same as the first one did.

This is not yet a thing you can burn to a USB stick — it's the OS in "container" form. Two
ways to actually run it:

- **On a machine already running Bazzite/Bluefin/Aurora**, one command switches it to ours:
  ```bash
  sudo bootc switch ghcr.io/YOUR-USERNAME/aquarius-os:latest
  ```
  Then reboot. (And if you hate it: `sudo bootc rollback`, reboot, you're back.)
- **On a fresh machine**, you need an installer ISO — that's Step 7.

---

## Step 6.5 — Which image do I pick?

Two AquariusOS images exist. Same operating system, same apps, same settings — the only
difference is which graphics driver is built in. Pick by **what graphics card is in the
machine**:

| Graphics card in the machine | Use this image |
|---|---|
| **NVIDIA** — any RTX card (RTX 5090 included), or GTX 16-series | `aquarius-os-nvidia` |
| **AMD or Intel** — including the built-in graphics in most laptops and handhelds | `aquarius-os` |

Not sure? It's AMD or Intel. An NVIDIA card is something you buy on purpose.

**Why there have to be two.** NVIDIA cards need NVIDIA's own driver built into the operating
system, and that driver can't be present on machines without the card. Bazzite splits its
images for exactly this reason, and we inherit the split. Nothing that we add is different
between them.

Picking wrong isn't dangerous — an NVIDIA machine running the AMD/Intel image usually boots
to a low-resolution desktop with no game performance, rather than exploding. Fix it by
switching, below.

### Switching between the two images

If you installed the wrong one, or you swapped the graphics card in a machine, you don't
reinstall. On the AquariusOS machine itself (not your Mac), open a terminal and run **one**
of these:

```bash
# Moving TO an NVIDIA card:
sudo bootc switch ghcr.io/YOUR-USERNAME/aquarius-os-nvidia:latest

# Moving BACK to AMD / Intel:
sudo bootc switch ghcr.io/YOUR-USERNAME/aquarius-os:latest
```

Then reboot. It downloads the other image, and on the next start-up you're on it.

**If `bootc` isn't found**, the machine is on an older toolset — use this instead, which does
the same job:

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/YOUR-USERNAME/aquarius-os-nvidia:latest
```

**Changed your mind after rebooting?** `sudo bootc rollback`, then reboot. You're back on the
previous one. That's the whole point of an atomic OS — the old version is still sitting
there, and it's also in the boot menu if the new one won't start at all.

**One thing to know:** a switch downloads a full OS image, so expect several GB and a few
minutes on a normal connection. Nothing in your home folder, files, or settings is touched.

---

## Step 7 — Building an installer ISO (when you're ready to test on real hardware)

An ISO is the file you write to a USB stick to install an OS on a blank machine. It has its
own workflow, and it only runs when you ask.

**Prerequisite:** Step 5 must have succeeded at least once, and the package should be public
(Step 6). The ISO builder downloads your published image — it can't build from nothing.

### 7a. Run the ISO workflow

1. Repo → **Actions** tab → **Build AquariusOS ISO (Titanoboa)** in the left sidebar.
2. Click the **Run workflow** button on the right.
3. There are two boxes:
   - **Which AquariusOS?** — pick `nvidia` if the PC you're installing on has an NVIDIA
     graphics card, `base` if it has AMD or Intel. (See Step 6.5.) This is the only one you
     normally touch.
   - **Advanced: a specific image instead** — **leave this blank.** It's an escape hatch for
     building an ISO of an older dated tag, and the choice above is ignored if you type in it.
4. Click the green **Run workflow**. This one is slow — plan on an hour. You can close the
   tab; it keeps running on GitHub's machines.

   One run makes **one** ISO. Need both? Run it twice.
5. When it finishes, click into the run and scroll to the bottom. Under **Artifacts** there's
   a downloadable `.zip` containing:
   - the **`.iso`** — the USB installer
   - a **`-CHECKSUM`** text file — proof the download didn't get corrupted (safe to ignore)

Artifacts are kept for 7 days, then GitHub deletes them. Download it when you need it; you
can always run the workflow again.

**What it's actually doing** (useful when you're staring at a progress bar for an hour): the
run has two halves. First it builds an *installer image* out of the `installer/` folder — a
small live desktop with the Fedora installer on it, with a copy of AquariusOS tucked inside
so installing works even with the network unplugged. Then it squashes that into the `.iso`.

If it fails, the last step prints a plain-English guide to which half broke and what the
usual causes are. Deeper background lives in `installer/README.md`.

> **Heads up:** the ISO pipeline is new and has not yet been booted on a real PC. If the
> stick doesn't boot, that's worth reporting rather than assuming you did it wrong.

### 7b. Write the ISO to a USB stick

Unzip the artifact first, so you have the plain `.iso` file. Then either:

- **Fedora Media Writer** (recommended, free — https://fedoraproject.org/tools/): install it,
  open it, choose **Select .iso file**, pick your ISO, pick the USB drive, click **Write**.
- **balenaEtcher** (free, also fine — https://etcher.balena.io): drag the ISO in, pick the
  USB drive, click **Flash**.

Either one **erases the USB stick completely**. Use a stick you don't care about, 8 GB or
larger, and double-check you picked the USB drive and not an external hard disk.

Then boot the target PC from that USB stick (usually F12 or Del at power-on) and follow the
installer.

### What about the other workflow?

**Build AquariusOS disk images** now only makes a `.qcow2` — a virtual-machine disk, useful
for testing in a VM, not for USB sticks. Run it the same way (Actions → Run workflow →
leave **Upload to S3** as `false`, choose **amd64** for platform).

It always uses the AMD/Intel image, and there's no variant option on it on purpose: a virtual
machine has no real NVIDIA card to talk to, so an NVIDIA VM disk would prove nothing. The
NVIDIA image gets tested on the actual PC, via a USB stick.

> **Heads up on testing:** your Mac is Apple Silicon, so it can only *emulate* an x86 PC,
> which is painfully slow and not a fair test. Real testing means a spare x86 PC or handheld,
> or a cheap cloud VM. Don't judge AquariusOS by how it runs under emulation on the Mac.

**More depth on ISOs and custom images:** https://docs.bazzite.gg/Advanced/creating_custom_image/

---

## Step 8 — The everyday loop from here on

Once it's set up, changing the OS looks like this:

```bash
cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/Workflow/Branches/Apps/AquariusOS/os-image

# 1. Edit build_files/build.sh (or whatever you're changing)
# 2. Save the change with a description of what you did:
git add -A
git commit -m "Describe what you changed here"

# 3. Send it to GitHub, which starts a new build automatically:
git push
```

Then watch the Actions tab. Green means a new version of AquariusOS exists. Users get it with
`sudo bootc upgrade` on their machine.

There's also a **nightly build at 10:05am UTC** so AquariusOS picks up Bazzite's security
updates even on days you don't touch anything.

---

## Known gaps — things deliberately not done yet

| Gap | Status |
|---|---|
| The OS still says "Bazzite", not "AquariusOS", in About This System | Open TODO, Phase 3. There's no supported mechanism in the template for this and it should not be improvised — see `branding/README.md`. |
| No wallpaper, logo, or boot splash | Phase 3. `branding/` is an empty placeholder. |
| No creator apps (Resolve, OBS, Krita, Blender…) | Phase 2. Commented-out stubs are in `build_files/build.sh` so the shape is visible. |
| Signing key | You create it in Step 4 — it can't be created for you, it's yours. |
| S3 hosting for ISO downloads | Not set up. ISOs come out as GitHub artifacts instead, which is fine until there's a public download page. |
| ISO built, but never tested on real hardware | Open. The pieces are all in place (Step 7), but nobody has yet booted the resulting USB stick on an actual PC. Until someone does, treat the first ISO as unproven. |
| The NVIDIA image has never been built or booted | Open, and newer than everything else here. `aquarius-os-nvidia` is wired up end to end (build, publish, sign, ISO) but the first green run and the first boot on the RTX PC are both still to come. Assume nothing about it until then. |
| Live session still looks like Bazzite | Cosmetic, Phase 3. The installer USB shows plain Bazzite KDE with an AquariusOS terminal greeting — we didn't carry over Bazzite's wallpaper, panel layout or login popups. See `installer/README.md`. |
| Updates aren't signature-checked after install | Open. Bazzite tells a freshly installed machine to verify image signatures on every update. AquariusOS can't yet, because it doesn't ship a signing policy for `ghcr.io/stoneharborent` — so that check is switched off. Noted in `installer/titanoboa_hook_postrootfs.sh`; turn it on the day the policy exists. |
| Artifacthub listing | Optional, ignored. See `artifacthub-repo.yml`. |

---

## If you get stuck

The Universal Blue community is genuinely friendly to beginners and answers this exact class
of question daily:

- Forums: https://universal-blue.discourse.group/
- Discord: https://discord.gg/WEu6BdFEtp

Say you're building a custom image from `ublue-os/image-template` on a Bazzite base, and
paste the failing log. That's all the context they need.
