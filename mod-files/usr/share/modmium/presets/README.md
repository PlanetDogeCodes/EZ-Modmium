# EZ-Modmium Policy Presets

This directory contains named JSON presets that can be applied in one action
from the device policy editor (MOSH → Edit Device Policies → Load Preset).

## How presets work

Each preset is a JSON object where:
- `_preset_name` and `_preset_description` are metadata (shown in the menu)
- Every other key is a device policy name (as listed in the Google policy docs)
- Values are the desired setting (boolean, string, number, or array)

When you load a preset, the policy editor merges its values into the current
`dump.json`, overwriting only the keys present in the preset. Keys not in the
preset are left untouched. You can then review the changes and press
**Apply Policies** to write them.

## Available presets

| Preset | Description |
|--------|-------------|
| `unlock-developer.json` | The "make my Chromebook free" preset. Enables Crostini, Borealis, Play Store, VPN, new users, and the `*@gmail.com` allowlist. |
| `max-privacy.json` | Disables all device reporting/telemetry/upload frequencies. The device appears offline but isn't flagged for missing telemetry. |
| `gac-friendly.json` | Minimal changes that keep the device reporting normally. Only enables new users + Crostini. |
| `gaming-steam.json` | Enables Steam (Borealis) + the VMs it requires + Crostini. Also toggle the Borealis flag in `chrome://flags`. |

## Creating your own preset

1. Copy any existing preset to a new file, e.g. `my-fleet.json`.
2. Edit the `_preset_name` and `_preset_description` fields.
3. Add/remove policy keys as needed (search https://chromeenterprise.google/policies for names).
4. Place the file in this directory (`/usr/share/modmium/presets/` on-device).
5. It will appear automatically in the **Load Preset** menu.

## Notes

- Presets are **merged**, not replaced — only the keys you list are changed.
- After loading a preset, you still need to press **Apply Policies** for the
  changes to take effect.
- Modifying *any* device policy stops new reports to the GAC. Use **Reset All
  Changes** to resume reporting. The `gac-friendly` preset avoids this by not
  touching reporting policies.
