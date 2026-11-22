---
layout: default
title: Getting Started
description: Install KeyPath and create your first keyboard remapping
---

# Getting Started

KeyPath needs **macOS 27 or later** on an **Apple Silicon (M-series) Mac**. Setup asks for one permission and installs nothing outside the app: no keyboard driver, no background system service and no admin-level helper.

> Using **KeyPath 1.0.1**? It has its own [1.0.1 setup guide](https://github.com/malpern-labs/KeyPath/blob/v1.0.1/getting-started/installation.md). To move from 1.0.1 to the current version, [remove the old keyboard service first]({{ '/guides/upgrading-from-1-0-1/' | relative_url }}).

## Install

1. Download KeyPath from the [Releases page]({{ site.github_url }}/releases).
2. Open the disk image and drag **KeyPath** to **Applications**.
3. Open KeyPath from Applications and follow setup.

The [setup guide]({{ '/getting-started/installation/' | relative_url }}) explains each step, including the one permission KeyPath asks for.

### Build from source

```bash
git clone {{ site.github_url }}.git
cd KeyPath
./build.sh
```

Building needs a full Xcode installation, not only the Command Line Tools.

## Create your first mapping

[Your First Mapping]({{ '/getting-started/first-mapping' | relative_url }}) walks you through remapping a key, step by step. Changes take effect as soon as you save them.

## Already using Kanata?

KeyPath can run your existing Kanata configuration. See the [Kanata migration guide]({{ '/migration/kanata-users' | relative_url }}).

## Next steps

- **[Tap-Hold & Tap-Dance]({{ '/guides/tap-hold' | relative_url }})**: keys that do one thing when tapped and another when held
- **[Action URI System]({{ '/guides/action-uri' | relative_url }})**: trigger actions through a URL
- **[Window Management]({{ '/guides/window-management' | relative_url }})**: snap and move windows from the keyboard

## Troubleshooting

If keys are not remapping, open KeyPath and check its status. If setup asks for the permission again, follow the [setup guide]({{ '/getting-started/installation/' | relative_url }}). KeyPath writes its log to `~/Library/Logs/KeyPath/keypath-debug.log`.

For more help, browse [all guides]({{ '/docs' | relative_url }}).
