# Bluetooth KOReader Plugin

KOReader plugin for Kindle Bluetooth audio management and audio volume control.

The plugin registers two menu entries:

- `Bluetooth` under the network menu area.
- `Audio volume` under the screen menu area.

It uses Kindle/Lab126 LIPC services:

- `com.lab126.btfd` for Bluetooth audio state, scan, connect, and disconnect.
- `com.lab126.audiomgrd` for speaker volume.

Install by placing this repository directory as `bluetooth.koplugin` under KOReader's `plugins` directory, then restart KOReader.
