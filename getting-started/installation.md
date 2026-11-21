---
layout: default
title: "Setting Up KeyPath"
description: "In two minutes your keyboard will launch apps, tile windows, and remap any key — all from the home row"
theme: parchment
header_image: header-installation.jpg
permalink: /getting-started/installation/
---


# Setting Up KeyPath

In two minutes, your keyboard will be able to launch apps, tile windows, fire shortcuts without reaching, and remap any key — all from the home row. This guide walks you through setup and explains what's happening at each step.

Setup asks for **one permission** and installs nothing outside the app: no keyboard driver, no background system service, and no admin-level helper.

> This guide is for **session-runtime builds on macOS 27 or later**. If your download is **KeyPath 1.0.1**, use the [1.0.1 setup guide](https://github.com/malpern-labs/KeyPath/blob/v1.0.1/getting-started/installation.md). If you already installed 1.0.1 and are switching to a session-runtime build, [remove the old keyboard service first]({{ '/guides/upgrading-from-1-0-1/' | relative_url }}).

---

## What You'll Get

Once setup is complete, KeyPath gives you:

- **System-wide remapping** — Caps Lock becomes Escape, or a Hyper key, or anything you want
- **App launching** — Hold one key + press a letter to open any app instantly
- **Window tiling** — Snap windows to halves, thirds, or corners with a key combo
- **Home row shortcuts** — Your modifier keys live under your fingertips, not in the corner

![Screenshot — The KeyPath overlay with rules panel](full-window-rules-tab.png)

Want to see what's possible before you start? Check out [What You Can Build]({{ '/guides/use-cases/' | relative_url }}).

---

## Before You Start

- **macOS 27 or later** is required
- **An Apple Silicon (M-series) Mac** is required; Intel Macs are not supported
- If you run **Karabiner-Elements** or another keyboard remapper, quit it first

> ⚠️ **Watch out:** Two remappers working on the same keys interfere with each other. Quit the other one before continuing. You can always switch back later — see [From Karabiner-Elements]({{ '/migration/karabiner-users/' | relative_url }}).

---

## Step 1: Put KeyPath in Applications

1. Open the downloaded disk image and drag **KeyPath** to **Applications**.
2. Open KeyPath from Applications and choose **Get Started**.

> ⚠️ **Watch out:** If you opened KeyPath from Downloads or straight from the disk image, move it to Applications and reopen it **before** granting access. macOS ties the permission to the app's location.

---

## Step 2: Allow Accessibility

**Why:** This permission lets KeyPath read the keys you press and send the remapped ones to your apps. On macOS 27 it appears in System Settings as **Device Control and Data Access**; earlier versions called it **Accessibility**.

The setup wizard opens the right pane in System Settings. Turn **KeyPath** on. macOS may ask for your password or Touch ID — that is macOS confirming the change, not KeyPath installing anything.


![KeyPath enabled in macOS 27 Device Control and Data Access]({{ '/images/help/screenshot-accessibility-settings.png' | relative_url }})
Screenshot from a macOS 27 test Mac: **KeyPath** is on. The other apps shown are lab tools; you do not need to add or enable them.

System Settings > Privacy & Security > Device Control and Data Access (Accessibility before macOS 27):
```
  ┌──────────────────────────────────────────────┐
  │  Privacy & Security > Device Control …       │
  │                                              │
  │  Allow the apps below to control             │
  │  your computer.                              │
  │                                              │
  │  ┌──────────────────────────────────┐        │
  │  │ 🔑 KeyPath.app          [  ●  ] │ ← ON   │
  │  └──────────────────────────────────┘        │
  └──────────────────────────────────────────────┘
```

Only **KeyPath** needs to be in this list. You do not add any other program.

KeyPath does not ask for Input Monitoring or Full Disk Access. Later, if you add an action that controls another app (for example an AppleScript action), macOS may ask once for Automation permission for that app.

---

## Step 3: Return to KeyPath

Switch back to KeyPath. It checks that it can actually read and send keys, then starts remapping on its own. There is no separate "start" step.

The keyboard tour then walks you through your first mapping. It can set up Caps Lock to act as Escape on a quick tap and as a Hyper key when held — see [Caps Lock and F18]({{ '/guides/driverless-caps-lock/' | relative_url }}) for details.

---

## Verify It's Working

Look at the overlay in the bottom-center of your screen:


![Screenshot]({{ '/images/help/install-overlay-health-green.png' | relative_url }})
Screenshot — Overlay header with green health indicator:
```
  ┌──────────────────────────────────────────────┐
  │  ● KeyPath                    Base Layer      │
  └──────────────────────────────────────────────┘
       ▲
       Green dot = remapping is running
```

**Quick test:** Press a key you mapped in the tour and confirm it does what you chose.

---

## Keep It Running After Login (Optional)

Turn on **Launch at login** in **Settings → General → Startup**. If macOS needs approval, KeyPath offers **Open Login Items**.

This starts KeyPath after you sign in. It does not remap the login screen.

---

## Where Remapping Doesn't Apply

KeyPath does not remap keys in password fields and other Secure Input contexts, or at the login screen. Don't rely on a remapped key to type a password.

---

## If Something Went Wrong

| Problem | Fix |
|---------|-----|
| The toggle is on but setup still shows a warning | Quit KeyPath completely (Cmd+Q) and reopen it. macOS sometimes needs a fresh launch to apply a new permission. |
| KeyPath doesn't appear in the Accessibility list | Make sure KeyPath is in Applications and was opened from there, then run setup again. |
| Remapping doesn't start | Choose **File → Set Up KeyPath…**. Setup shows what is missing and offers recovery steps. |
| Keys behave strangely with another remapper installed | Quit Karabiner-Elements or the other remapper, then run setup again. |
| Permission granted but a key isn't remapped | Check that the rule is turned on, and that you aren't in a password field. |

> 💡 **Tip:** You can re-run setup any time from **File → Set Up KeyPath…** or from KeyPath's menu-bar menu. It only shows what still needs attention.

---

## Updating and Removing

- **Update:** KeyPath checks for updates once a day and installs them when you quit. Choose **Check for Updates…** in the KeyPath menu to check now, or change this in **Settings → General → Updates**. Your rules are stored separately and are kept.
- **Remove:** see [Uninstall KeyPath]({{ '/guides/uninstall/' | relative_url }}) to back up your rules and remove the session-runtime build.

---

## What's Next

You're set up! Here are the best places to go from here:

- [Keyboard Concepts]({{ '/guides/concepts/' | relative_url }}) — Layers, tap-hold, and the ideas behind modern keyboard customization
- [What You Can Build]({{ '/guides/use-cases/' | relative_url }}) — Real examples: app launching, window tiling, Vim-style navigation
- [Shortcuts Without Reaching]({{ '/guides/home-row-mods/' | relative_url }}) — Turn your home row into modifier keys so you never leave home position
- [Privacy & Permissions]({{ '/guides/privacy/' | relative_url }}) — Exactly what KeyPath accesses and why

---

## Resources

- [Apple: Allow Accessibility apps to access your Mac](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac) ↗
- **[Back to Docs](https://malpern.github.io/KeyPath/docs)**
