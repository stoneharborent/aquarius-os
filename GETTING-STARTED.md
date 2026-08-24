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

Three files have a placeholder that must become your real GitHub username — the part of your
profile URL after `github.com/`. If your profile is `github.com/royceadkins`, your username is
`royceadkins`.

Open a Terminal on your Mac (press `Cmd+Space`, type "Terminal", press Enter), then paste this
**after replacing `YOUR-USERNAME` with your actual username**:

```bash
cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/Workflow/Branches/Apps/AquariusOS/os-image

# ⬇️ Change YOUR-USERNAME on this line only
MYNAME="YOUR-USERNAME"

sed -i '' "s/CHANGEME-github-username/${MYNAME}/g" \
  aquarius-os.env \
  disk_config/iso.toml \
  disk_config/iso-kde.toml \
  disk_config/iso-gnome.toml

grep -rn "${MYNAME}" aquarius-os.env disk_config/
```

The last command prints the lines it changed. You should see your username in four files and
**no remaining `CHANGEME`**. To double-check:

```bash
grep -rn "CHANGEME" . --exclude-dir=.git
```

That should print nothing at all.

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
3. You should now see two workflows listed in the left sidebar:
   - **Build AquariusOS image** — the main one; builds the OS
   - **Build AquariusOS disk images** — makes the installer ISO; you run this manually later

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

Click into the run, then click the **Build and push image** job to watch the live log.

**What you're looking at:** each line is one step. The big one is "Build Image" — that's
GitHub downloading Bazzite (several GB) and running our build script on top of it. The
"Rechunk" step afterwards is repackaging and is normally the slowest part. This is why we
don't build on your Mac.

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
container images. Its address is:

```
ghcr.io/YOUR-USERNAME/aquarius-os:latest
```

To see it: go to your **GitHub profile page** (not the repo) → the **Packages** tab →
`aquarius-os`. You'll see the tags and the publish date.

**Make it public** (do this once, or nobody can install it):
On the package page → **Package settings** (right side) → scroll to **Danger Zone** →
**Change package visibility** → **Public**.

This is not yet a thing you can burn to a USB stick — it's the OS in "container" form. Two
ways to actually run it:

- **On a machine already running Bazzite/Bluefin/Aurora**, one command switches it to ours:
  ```bash
  sudo bootc switch ghcr.io/YOUR-USERNAME/aquarius-os:latest
  ```
  Then reboot. (And if you hate it: `sudo bootc rollback`, reboot, you're back.)
- **On a fresh machine**, you need an installer ISO — that's Step 7.

---

## Step 7 — Building an installer ISO (when you're ready to test on real hardware)

An ISO is the file you write to a USB stick to install an OS on a blank machine. There's a
second workflow for it, and it only runs when you ask.

**Prerequisite:** Step 5 must have succeeded at least once, and the package should be public
(Step 6). The ISO builder downloads your published image — it can't build from nothing.

1. Repo → **Actions** tab → **Build AquariusOS disk images** in the left sidebar.
2. Click **Run workflow**. You'll get two options:
   - **Upload to S3** — leave as `false`. (That's for hosting downloads on cloud storage;
     we don't have a bucket and don't need one yet.)
   - **platform** — choose **amd64**. That's normal PCs, gaming desktops and handhelds.
     `arm64` is a different kind of chip and is not our target (Roadmap Phase 6).
3. Click the green **Run workflow**. This one is slow — plan on an hour.
4. When it's green, open the finished run and scroll to the bottom. Under **Artifacts**
   there's a downloadable `.zip` containing:
   - an **`install.iso`** — the USB installer
   - a **`.qcow2`** — a virtual machine disk, for testing in a VM

> **Heads up on testing:** your Mac is Apple Silicon, so it can only *emulate* an x86 PC,
> which is painfully slow and not a fair test. Real testing means a spare x86 PC or handheld,
> or a cheap cloud VM. Don't judge AquariusOS by how it runs under emulation on the Mac.

**To write the ISO to a USB stick:** use https://etcher.balena.io (free, Mac app, drag the
ISO in, pick the USB drive, click Flash). Note this **erases the USB stick** completely.

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
| Artifacthub listing | Optional, ignored. See `artifacthub-repo.yml`. |

---

## If you get stuck

The Universal Blue community is genuinely friendly to beginners and answers this exact class
of question daily:

- Forums: https://universal-blue.discourse.group/
- Discord: https://discord.gg/WEu6BdFEtp

Say you're building a custom image from `ublue-os/image-template` on a Bazzite base, and
paste the failing log. That's all the context they need.
