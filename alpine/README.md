# SP — a minimal custom firmware for Anbernic RG35xxSP

This is an experimental CFW that I vibe-coded mostly for fun.

## Based on Alpine

So that I don't have to build every package by myself and fill my whole HDD doing that.

Also uses mainline kernel with patches adapted from [Rocknix](https://github.com/ROCKNIX/distribution). Built to be as small as possible using tinyconfig.

The current make file is designed for a Mac with OrbStack installed. It deploys a small Alpine VM to build custom packages and the final image.

SP only supports RG35xxSP. I don't own other xx devices.

Also, because it's Alpine-based, it uses musl instead of glibc. As such, it can't run closed source binaries like Drastic or Pico-8.

## Uses [MinUI](https://github.com/ROCKNIX/distribution)

Uses the great frontend by Shaun Inman, but with a few differences:

- it's a full custom firmware (no stock required), MinUI acts as a first class app
- it supports using both SD cards for ROMs. It will autoexpand on first boot and automatically initiate the second SD card
- it supports Wi-Fi and BT (for gamepads and headphones)
- it has power management settings to decide what happens when you close the lid/push the power button
- it supports rewind, even on PlayStation
- it has a simple BIOS checker tool
- it supports bezels from [drkhrse](https://github.com/drkhrse/drkhrse_miyoo_bezels/tree/main/drkhrse_miyoo_bezels)
- it supports multi-version ROMs

Basically you can have additional versions of the same ROM inside your main ROM archive, add an empty .version textfile, and SP will ask you which version you want to run. Useful for when you want to try different romhacks but keep your menu simple.
