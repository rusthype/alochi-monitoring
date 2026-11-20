# Alochi Monitoring — Installing on macOS

## Description

Alochi Monitoring is the macOS app of the student testing system used in schools across Uzbekistan. It helps teachers and administrators follow the testing process in real time.

---

## Installation

1. **Download the DMG file:**
   - Go to https://github.com/rusthype/alochi-monitoring/releases/tag/latest
   - Download `alochi-monitoring.dmg`

2. **Start the installation:**
   - Double-click the downloaded `.dmg` file — a disk image opens
   - In the window that opens, drag **Alochi Monitoring** onto the **Applications** folder icon (drag & drop)

3. **Launch the app:**
   - Open the Applications folder and find **Alochi Monitoring**

---

## If a "Damaged file" / Gatekeeper error appears

The app is **ad-hoc signed** (not with an Apple Developer certificate), so a plain double-click may show the error "Alochi Monitoring" is damaged and can't be opened" on macOS 15+. This is not a real error — a file downloaded correctly from GitHub is safe.

**On first launch:**
1. In the Applications folder, **right-click** **Alochi Monitoring** (or hold Control and click)
2. Choose **Open** from the menu
3. Click **Open** again in the confirmation dialog

After that the app opens with a normal double-click as well.

---

## Uninstalling

1. Open the Applications folder
2. Drag the **Alochi Monitoring** app to the Trash
3. Empty the Trash

---

## Updating

Alochi Monitoring does not update itself automatically (like the Windows version, the app shows a notification on launch when a new version is available, but downloading and installing is done manually). When a new version is released:

1. Move the old `.app` from the Applications folder to the Trash (as described above)
2. Download the new `.dmg` and start the installation again

---

## Troubleshooting

### The app does not open and no error is shown
- Open **System Settings → Privacy & Security**; if a message at the bottom says "Alochi Monitoring" was blocked, click **Open Anyway**

### Other questions
- Ask on the GitHub issues page: https://github.com/rusthype/alochi-monitoring/issues

---

*Last updated: July 2026*
