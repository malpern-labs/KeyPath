---
layout: default
title: "Move from KeyPath 1.0.1 to the new runtime"
description: "Keep a copy of your rules and remove the old KeyPath keyboard service before installing the new build."
permalink: /guides/upgrading-from-1-0-1/
---

# Move from KeyPath 1.0.1 to the new runtime

Use this guide if you previously set up **KeyPath 1.0.1** and are switching to
a session-runtime build. The new build requires **macOS 27 or later on Apple
Silicon**. It runs in your user session. It does not remove the keyboard
service or privileged helper that 1.0.1 installed.

## 1. Back up your rules and quit KeyPath

Copy `~/.config/keypath` to a backup folder. If you use a custom Kanata
config, back it up separately. Quit KeyPath and turn off any old KeyPath
background items in **System Settings → General → Login Items**. Look for
KeyPath and its helper under the apps allowed to run in the background.
If more than one person used 1.0.1 on this Mac, sign out those other
accounts before continuing.

## 2. Stop the old KeyPath services

In Terminal, run the following from the same macOS account you used for
KeyPath 1.0.1. macOS asks for an administrator password.

```bash
for label in com.keypath.kanata com.keypath.helper \
  com.keypath.karabiner-vhiddaemon com.keypath.karabiner-vhidmanager com.keypath.logrotate
do
  sudo launchctl bootout "system/$label"
  sudo launchctl bootout "gui/$(id -u)/$label"
done
```

Some stop commands can report **No such process** if that service was
already absent. Check that every service stopped before removing files:

```bash
for label in com.keypath.kanata com.keypath.helper \
  com.keypath.karabiner-vhiddaemon com.keypath.karabiner-vhidmanager com.keypath.logrotate
do
  sudo launchctl print "system/$label"
  sudo launchctl print "gui/$(id -u)/$label"
done
```

Each check should report **Could not find service**. If any check still shows
a service or reports a permissions problem, stop here before deleting its files.

## 3. Remove the old service files

Remove only the listed KeyPath files. This leaves your rules and preferences
in place.

```bash
sudo rm -f \
  /Library/LaunchDaemons/com.keypath.kanata.plist \
  /Library/LaunchDaemons/com.keypath.helper.plist \
  /Library/LaunchDaemons/com.keypath.karabiner-vhiddaemon.plist \
  /Library/LaunchDaemons/com.keypath.karabiner-vhidmanager.plist \
  /Library/LaunchDaemons/com.keypath.logrotate.plist \
  /Library/PrivilegedHelperTools/com.keypath.helper \
  /Library/KeyPath/bin/kanata \
  /etc/newsyslog.d/com.keypath.conf \
  /usr/local/bin/keypath-logrotate.sh
```

You can also remove the old engine logs and empty engine folders:

```bash
sudo rm -f /var/log/com.keypath.kanata.stdout.log /var/log/com.keypath.kanata.stderr.log
sudo rmdir /Library/KeyPath/bin /Library/KeyPath
```

An absent folder needs no action. If a folder contains other files, leave it
in place.

Keep the Karabiner VirtualHID driver if you use Karabiner-Elements or another
tool that depends on it. The new KeyPath build does not need the driver.
For optional removal, use the
[driver project's uninstall instructions](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice).

## 4. Install and check the new build

Replace KeyPath in **Applications** and remove extra copies of the old app
from places such as **Downloads**. Restart your Mac so any remaining
processes from the old build exit. Before opening KeyPath, repeat the
service checks from step 2 to verify the old services stayed off. A stale
KeyPath entry can remain in Login Items even after the services are gone.
Then follow [Setting Up KeyPath]({{ '/getting-started/installation/' | relative_url }})
and try one remap from your rules. You can remove the old KeyPath Full Disk
Access and Input Monitoring grants in System Settings.
