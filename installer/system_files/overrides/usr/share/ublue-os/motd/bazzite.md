# Welcome to the AquariusOS Live Installer 󰊴

󰋼 This is a temporary session that runs entirely from your USB stick. Nothing you
do here is saved, and nothing on your computer has been changed yet.
`rpm-ostree` commands do not work here. Once AquariusOS is installed,
*restart your computer* and remove the stick.

|  Command | Description |
| ------- | ----------- |
| `fastfetch` | View system information |
| `liveinst` | Launch the AquariusOS installer |

<!--
  Yes, the filename really is bazzite.md.

  The greeting script that prints this file lives in the Bazzite base image and
  looks for this exact path, so replacing the file is the safe way to change the
  text without touching the script. Rename it only if you also override
  /usr/libexec/ublue-motd.

  Adapted from ublue-os/bazzite installer/system_files/overrides/usr/share/
  ublue-os/motd/bazzite.md (Apache-2.0), read at commit
  0fb3abacb1135fbb50cbb575a18f53fea683ab0f (2026-08-23). The %IMAGE_NAME%
  placeholder was removed because the script fills it by searching for images
  named "bazzite*", which finds nothing in an AquariusOS live session.
-->
