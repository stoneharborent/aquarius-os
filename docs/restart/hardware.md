# Firmware — the programs that live inside your hardware

*Written 5 September 2026, the day the bench PC said it had no Wi-Fi.*

This is the plain-language guide to the one part of AquariusOS that decides
whether the machine can talk to the outside world at all. You do not need to
know any Linux to read it.

---

## What went wrong

Royce booted the new AquariusOS image on the bench PC. GNOME's settings said:

> **No Wi-Fi Adapter Found**

The PC is an **MSI X870 Tomahawk WIFI**. It has Wi-Fi. The Wi-Fi chip is a
**MediaTek MT7925** — Wi-Fi 7 and Bluetooth on one piece of silicon — and it was
sitting on the motherboard the whole time, working perfectly.

The operating system could not use it, and then told him it did not exist.

**This fault is still open.** The first suspect was missing firmware; the checks
described here proved that wrong, and the story of how is further down. Read
*Checking it on a real machine* at the end — those three commands are what will
identify the real cause.

---

## What firmware actually is

A Wi-Fi chip is a tiny computer. So is a graphics card. So is the little
amplifier that drives a laptop's speakers, and the sensor board behind a
laptop's webcam.

None of them leave the factory with a program in them.

Every time you switch the machine on, Linux hands each one its program — a
small file from a folder called `/usr/lib/firmware`. Those files are called
**firmware**, or "blobs", and they are written by the chip's manufacturer.

So making Wi-Fi work takes **two** things, not one:

| The half | What it is | Where it lives |
|----------|-----------|----------------|
| The **driver** | The Linux code that knows how to talk to that family of chip | Inside the kernel |
| The **firmware** | The manufacturer's program that gets loaded *into* the chip | `/usr/lib/firmware` |

AquariusOS had the first half and not the second. The kernel loaded its
`mt7925e` driver, went to `/usr/lib/firmware/mediatek/mt7925/` to fetch the
MT7925's program, found an empty shelf, and gave up.

**And this is the cruel part:** when the driver gives up, the chip never
registers itself as a network device. So the desktop, which only sees
registered devices, honestly reports that there is no Wi-Fi adapter. Nothing
in the interface can tell you the difference between "the firmware file is
missing" and "there is no card in this computer". They look identical.

---

## What we thought was wrong, and what the build actually found

The obvious suspect was missing firmware, and the reasoning was sound: Fedora
used to ship **one** package called `linux-firmware` containing every
manufacturer's blobs, and it does not any more. Today it is about **thirty**
separate packages, one per manufacturer, and the one *still called*
`linux-firmware` is only the leftovers — about 50 MB of odds and ends with **no
Wi-Fi in it at all**. Our build asked for `linux-firmware` plus two Intel
packages and nothing else, which certainly *looks* like an image with no
MediaTek firmware in it.

> ### ⚠️ It wasn't that.
>
> The first build with these checks in it proved the MediaTek firmware was
> **already in the image Royce booted** — all three MT7925 files, exactly where
> the kernel looks for them.
>
> The reason is a detail nobody had checked: the split `linux-firmware` package
> *suggests* the vendor packages (in packaging terms it "Recommends" them), and
> suggestions are switched **on** in this build. So the Fedora base image we
> start from already carries thirteen of them, MediaTek included, without
> anyone asking.

So the bench's "No Wi-Fi Adapter Found" has a different cause, and it is still
open. What is ruled out now, on both images, is the entire firmware half of the
problem — the packages are named, the blobs are counted, and the build goes red
if either changes.

### What actually changed on 5 September 2026

Four firmware packages really were absent, because they are **not** in the
suggestions list and so nothing was bringing them: `mediatek-firmware`,
`libertas-firmware`, `iwlegacy-firmware` and `intel-vsc-firmware`. About 14 MB.
None of them is the MT7925.

The other twenty-one names in the list were already arriving. Writing them down
anyway is the real point of the change:

**A suggestion is not a promise.** It is somebody else's default. It can be
dropped upstream, switched off by one option anywhere in our build, or vanish
when the base image is re-cut — and every one of those is **silent**. Nothing
goes red; the image just ships without a radio, and the first anyone hears of
it is a machine claiming its Wi-Fi card does not exist. Naming the packages and
counting their files turns that silent failure into a failed build.

---

## What AquariusOS ships now

Every radio, from every manufacturer. Not just MediaTek.

The reason is simple: naming only the chip in Royce's bench PC would fix Royce's
bench PC and break the next machine. Whichever Wi-Fi chip a laptop has is
whichever one its manufacturer got a good price on that quarter, and a laptop
that boots with no Wi-Fi cannot download the fix for having no Wi-Fi. Each of
these packages is between 1 and 60 MB. The whole radio set costs about 105 MB.
That is a cheap insurance policy.

**Wi-Fi, Bluetooth and mobile broadband — all vendors**

| Package | Size | Whose chips |
|---------|------|-------------|
| `mt7xxx-firmware` | 31 MB | MediaTek MT7921/7922/**7925**/7927/7996 — **the bench board** |
| `mediatek-firmware` | 5 MB | The rest of MediaTek |
| `atheros-firmware` | 45 MB | Qualcomm Atheros (ath9k/10k/11k/12k) + QCA Bluetooth |
| `realtek-firmware` | 7 MB | Realtek Wi-Fi + Bluetooth |
| `brcmfmac-firmware` | 10 MB | Broadcom and Cypress |
| `iwlwifi-mvm-firmware` | 63 MB | Intel, current generation |
| `iwlwifi-mld-firmware` | 20 MB | Intel Wi-Fi 7 |
| `iwlwifi-dvm-firmware` | 2 MB | Intel, older |
| `iwlegacy-firmware` | 1 MB | Intel, much older |
| `nxpwireless-firmware` | 2 MB | NXP |
| `tiwilink-firmware` | 5 MB | Texas Instruments |
| `libertas-firmware` | 1 MB | Marvell |
| `qcom-wwan-firmware` | 1 MB | Qualcomm mobile-broadband modems (the SIM slot) |

**Graphics — all three vendors, on both images**

| Package | Size | Why |
|---------|------|-----|
| `amd-gpu-firmware` | 27 MB | A modern Radeon card or Ryzen APU will not start without it. The AMD/Intel image was shipping without the firmware for the hardware it is named after. |
| `intel-gpu-firmware` | 12 MB | Intel's built-in graphics and Arc cards |
| `nvidia-gpu-firmware` | 101 MB | The open `nouveau` driver, including the newer cards' GSP. This is what puts a picture on screen if someone installs the AMD/Intel image on an NVIDIA machine — the one situation where they cannot download the fix. |

**Sound, cameras and processors**

| Package | Size | Why |
|---------|------|-----|
| `cirrus-audio-firmware` | 3 MB | Laptop speaker amplifiers. Without it, headphones work and the speakers are silent. |
| `intel-audio-firmware` | 3 MB | Intel's audio processors |
| `alsa-sof-firmware` | — | The audio processor in nearly every modern laptop *(already shipped)* |
| `intel-vsc-firmware` | 8 MB | The webcam in most 2023-and-newer laptops |
| `amd-ucode-firmware` | 1 MB | AMD processor fixes, loaded at boot |
| `microcode_ctl` | 16 MB | The same for Intel, plus the tool that loads both |

**What all that costs: almost nothing.** The list above is about 275 MB of
firmware in total, but roughly 260 MB of it was already arriving as a
suggestion, so the image grew by about **14 MB** — from 6.85 GB to 6.87 GB on
the AMD/Intel image, and 8.74 GB to 8.76 GB on the NVIDIA one. Both are far
under their ceilings (9 GB and 12 GB). `/usr/lib/firmware` ends up 438 MB on
the AMD/Intel image and 546 MB on the NVIDIA one, the difference being the
NVIDIA driver's own firmware.

### What we deliberately leave out

About 350 MB of firmware, all of it for equipment that is not a personal
computer and cannot appear inside one:

| Skipped | Size | What it actually is |
|---------|------|---------------------|
| `qcom-firmware` | 148 MB | Qualcomm Snapdragon phone/tablet chips. AquariusOS is x86_64 only. |
| `mlxsw_spectrum-firmware` | 102 MB | Mellanox **network switch** silicon — a rack appliance, not a PC |
| `mrvlprestera-firmware` | 71 MB | Marvell network switch silicon, same thing |
| `qcom-accel-firmware` | 11 MB | Qualcomm datacentre AI accelerators |
| `qed-firmware` | 10 MB | Marvell 25/40/100-gigabit server network cards |
| `netronome-firmware` | 4 MB | Datacentre SmartNICs |
| `liquidio-firmware` | 1 MB | Cavium server adapters |
| `dvb-firmware` | 1 MB | Broadcast-TV tuner cards. Worth naming because it *sounds* like video-capture hardware and is not — an Elgato or Blackmagic capture card does not use this. |

> ⚠️ **A name trap worth remembering.** `qcom-firmware` — the big one we skip —
> is Qualcomm's *phone chip* firmware. Qualcomm's **Wi-Fi** firmware is in
> `atheros-firmware`, which we absolutely do ship. Skipping the first does not
> cost anybody their Wi-Fi.

---

## How the build proves it

Three checks, because they catch different mistakes, and all of them run on
**both** images.

1. **`rpm -q` on every package.** Proves each one is really installed. Most of
   them arrive as a suggestion rather than because we asked, so this is the
   check that goes red the day a suggestion quietly stops being made.

2. **Counting the actual files on disk.** Proves the blobs landed in the folders
   the kernel will look in. "The package is installed and the shelf is empty"
   looks identical from the package database, and only this catches it.

3. **Checking the kernel drivers.** Firmware alone does nothing: a Wi-Fi chip
   needs Linux's driver *and* the manufacturer's firmware, and missing either
   one produces the very same "No Wi-Fi Adapter Found". The build looks for
   `mt7925e` (the bench board), `mt7921e`, `iwlwifi`, `ath11k_pci`, `rtw89_pci`,
   `brcmfmac`, `btusb`, `amdgpu` and `i915`, and prints which kernel's modules
   they are. This one *has* to run on the finished image rather than during the
   build, because `58-kernel-pin.sh` can replace the whole kernel — and every
   module with it — long after the firmware is installed.

The first thing check 2 looks at is Royce's own chip:

```
/usr/lib/firmware/mediatek/mt7925/   — must contain 3 files
    WIFI_RAM_CODE_MT7925_1_1.bin.xz          the Wi-Fi program
    WIFI_MT7925_PATCH_MCU_1_1_hdr.bin.xz     the Wi-Fi patch
    BT_RAM_CODE_MT7925_1_1_hdr.bin.xz        the Bluetooth program
```

Note the third one. **The MT7925's Bluetooth firmware is in the same package as
its Wi-Fi firmware** — there is no separate MediaTek Bluetooth package to go
looking for. So the same fix that brings Wi-Fi back also keeps Bluetooth
pairing working, and the build now checks for that file by name so it can never
drift apart from the Wi-Fi half.

The check also counts AMD graphics (must be over 100 files), Intel graphics,
NVIDIA's `ad102` folder (that is the RTX 4090's chip), Realtek, Atheros,
Broadcom, Intel Wi-Fi, the Cirrus speaker amplifiers and the AMD microcode.

If any of it is short, the build stops with a red message and nothing is
published.

The files are all named `.bin.xz` rather than `.bin` — Fedora ships firmware
compressed and the kernel unpacks it on the way in. That is normal. It is also
why the checks count files of any name instead of looking for `.bin`, which
would report an empty shelf on a full one.

---

## Checking it on a real machine

After the bench PC updates to an image with this fix, three commands say
whether it worked. Open **Terminal** and type them one at a time.

**1. Does the system see a Wi-Fi device at all?**

```
nmcli device
```

You want a line whose TYPE is `wifi` and whose STATE is `connected` or
`disconnected` — either is fine, both mean the hardware is alive:

```
DEVICE  TYPE      STATE         CONNECTION
wlp5s0  wifi      disconnected  --
enp4s0  ethernet  connected     Wired connection 1
```

If there is **no `wifi` line at all**, the firmware is still missing.

**2. What did the chip say while booting?**

```
sudo dmesg | grep mt79
```

Working looks like this — it found its firmware and reported a version:

```
mt7925e 0000:05:00.0: HW/SW Version: 0x8a108a10, Build Time: ...
mt7925e 0000:05:00.0: WM Firmware Version: ____000000, ...
```

Broken looks like this:

```
mt7925e 0000:05:00.0: Direct firmware load for mediatek/mt7925/WIFI_RAM_CODE_MT7925_1_1.bin failed with error -2
```

`error -2` means "no such file" — that is the missing-firmware fault exactly.

**3. Is the file actually there?**

```
ls /usr/lib/firmware/mediatek/mt7925/
```

Three files should be listed. An empty result, or "No such file or directory",
means the image does not have the fix in it yet.

**And for Bluetooth**, which shares the same chip:

```
bluetoothctl show
```

A block of text with a `Powered: yes` line means the Bluetooth half loaded its
firmware too.

### Two more, because the firmware turned out not to be the problem

Since the MT7925's firmware was already in the image, these two are the ones
most likely to actually find the fault.

**4. Did the driver load?**

```
lsmod | grep mt79
```

You want to see `mt7925e` and `mt792x_lib` listed. **Nothing at all** means the
driver never loaded — and the cause is then either that the module is not in
this image, or that the kernel never saw the card:

```
lspci -nn | grep -i network
```

If `lspci` shows no MediaTek device, Linux is not the problem. The card is
either disabled in the BIOS, not seated, or the board's Wi-Fi module is
genuinely absent (some X870 boards ship both ways).

**5. Is the radio switched off?**

```
rfkill list
```

`Soft blocked: yes` means software turned the radio off — `rfkill unblock all`
fixes it. `Hard blocked: yes` means a physical switch or a BIOS setting did,
and no amount of software will help until that is changed.

### If it is still broken

Roll back to the previous image and tell Fable which of the three commands
failed:

```
sudo bootc rollback
sudo systemctl reboot
```

That returns the machine to the deployment it was on before the update. Nothing
is lost.

---

## For whoever changes this next

- The list lives in **`build_files/20-hardware-media.sh`**, under the heading
  *"Firmware — Wi-Fi, Bluetooth, graphics, audio, CPU microcode"*. Every package
  has a one-line comment saying whose hardware it is and roughly how big it is,
  and the skipped ones are listed underneath with reasons.
- Adding a vendor is **two** edits: the install list, and the `aq_installed`
  list right below it. If you add a package without adding the check, the next
  person gets no warning when it silently stops arriving. That is how this bug
  happened.
- The same package names are repeated in the CI step
  *"Check the Wi-Fi, Bluetooth and graphics firmware is really in there"* in
  `.github/workflows/build.yml`. Keep the three lists in step.
- Do not go back to relying on `linux-firmware` pulling the vendor packages in
  by suggestion. It does not happen in a container build, and when it fails it
  fails silently.
