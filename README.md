# Plug-ins by Segan

Downloads and updates for Sam's plug-ins (Audio Unit and VST3, for Mac):
Breakerizer, Chopperizer, OTTizer, Overtonizer, Reverserizer, Tremorizer,
Erodizer and REF. The page links to his apps too: REF, Combiner and
Preseterizer.

**Get them: <https://segan.world/plugins>** (the old page,
<https://samsegan.github.io/plugins>, sends you there)

This repository only holds the releases and that page. It's published from
the (private) source repository by `scripts/release-plugins.sh`: please don't
edit it by hand, the next release overwrites it.

- `MusicPlugins.zip` and `update-plugins.sh` in each [release](https://github.com/samsegan/plugins/releases)
- `latest.json`: the newest release, for the page
- `install.sh`: `curl -fsSL https://samsegan.github.io/plugins/install.sh | bash`
  installs the plug-ins, every app, and the agent that installs each new
  plug-ins release (`| bash -s -- --plugins` for the plug-ins only)
