# Alochi Monitoring on Linux

Intended for teachers and practice sessions on Ubuntu 22.04+ / Debian 12+ (x86_64).
It is **not** a locked-down exam kiosk.

## Install

```bash
sudo apt install ./alochi-monitoring_<version>_amd64.deb   # adds the launcher and icon
# or: tar -xzf alochi-monitoring-linux-x64.tar.gz && ./alochi-monitoring-linux-x64/alochi_monitoring
```

`apt` installs the recommended helpers (`gnome-keyring`, `zenity`, `xdg-utils`,
`gnome-screenshot`, `scrot`). The app also runs without them (see below).

## Behaviour

- Starts maximized with a normal title bar. F11 toggles fullscreen. There is no hard lockdown
  (same as the Windows build, which only maximizes).
- A second launch brings the running window to the front (needs a D-Bus session; without one,
  verified on Debian, two copies run side by side).
- During a test the screen and the system are kept awake (sleep inhibit).
- Updates: the update button opens the release page; nothing installs itself (a `.deb` needs
  root). A remote "force update" command is answered `failed` on Linux.
- Seat id sent to the backend is `sha256("alochi-linux|<machine-id>|<primary NIC MAC>")[:32]`,
  so PCs cloned from one image (same `/etc/machine-id`) are still different seats.

## Known limits

- **Proctoring** needs a screenshot tool: `gnome-screenshot`, `grim`, `scrot` or ImageMagick
  `import`. Without one the teacher panel simply gets no frames (the backend has no
  "capture unavailable" flag). Keyframes only: no cursor, one monitor.
  - On X11 `scrot`/`import` are silent. On **GNOME Wayland** only `gnome-screenshot` works and it
    always asks the shell for its screen flash, so every captured frame flashes the screen.
    Use an X11 session for proctored labs.
- **USB export** lists mounts under `/media`, `/run/media` and `/mnt` whose device is on the USB
  bus or reports `removable=1`. Encrypted (LUKS) sticks are not listed.
- **File dialogs** (open a pack) need `zenity`, `qarma` or `kdialog`; the app says so when none
  is installed.
- **No keyring** (no `gnome-keyring`, or no D-Bus): the offline login cache and the clock
  high-water mark are not persisted; the queue encryption key falls back to a file in the app
  data directory. Nothing crashes.
- Without NetworkManager the OS "network changed" trigger is disabled; connectivity still comes
  from the HTTP probe.
