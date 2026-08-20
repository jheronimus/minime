# Minime is a minimal Linux firmware for Anbernic handhelds

*Disclaimer*: this is an experimental personal project, and it's not really meant for daily usage (at least yet). AI has been used for maintaining the repo and automation. Use at your own risk, no support is offered.

The goal of Minime is to provide a simple foundation to play around with different UIs and ideas on Anbernic handhelds. The basic idea is this: a lot of cool UIs kind of piggy-back onto the stock firmware of the handheld. Minime replaces the stock firmware in the equation, provides a clean foundation with an up to date kernel and system tools and mostly gets out of the way.


## Unified build system

Under the hood Minime actually builds on two foundations:

- Alpine offers panfrost-enabled images, but uses the musl LibC library, so can't really run a lot of closed source software.
- Buildroot offers glibc, but it builds everything from scratch, so building Panfrost, LLVM, etc would take several hours easily. So it uses libmali driver blobs, but those do not work with H700 on mainline kernel (at least I haven't figured out how).

Both targets are used to basically produce three main files:
- the kernel
- the initramfs
- the read-only erofs image with rootfs

Minime then picks up files from both and produces the final images.

Additionally whenever possible the config files are layered. For example, the kernel config looks like this:

- tiny-base.config — the base modules needed by any target in Minime
- tiny-<platform, e.g. H700>.config — device-specific drivers and options
- tiny-panfrost.config and tiny-libmali.config — different GPU drivers
- tiny-dongles.config (phrasing?) — a lot of RK3326 devices didn't have built-in Wi-Fi, so support for popular dongles is added

This approach will allow simple OTA updates and easy switching between Alpine on Buildroot without reflashing. Also this is great for experimenting as both systems have their own strengths and use cases.

## Standard UI contract

Most firmwares are built for one specific UI - EmulationStation, MinUI, etc. Minime tries to treat UIs the way Linux distros treat GNOME, KDE, etc. It does two things to achieve this:

- maintains a traits system. UIs don't have to support each device Minime supports. They just have to read the traits file that contains specifics like screen aspect ratio, controls, connectivity, lid and all the important system paths.
- provides a standard OpenRC service (`/etc/init.d/ui`). UIs ship a `ui.env` file defining the entry binary, process names, and lifecycle hooks.

Minime doesn't override user directories that UIs provide (like roms or bios or savestates) and doesn't override built-in dependencies. If a UI comes with its own emulation cores, Minime will not try to make it use something else.

## Simple partition structure

A lot of firmwares split boot files, rootfs and userdata into several partitions.

In Minime it's all a single FAT32 partition with a hidden `.minime` folder that contains the bootloader files, the read-only rootfs image and the initramfs.

When flashed, the image contains a minimal 1040MB FAT32 partition. On first boot, the initramfs stages the seed files into RAM, expands the partition to 100% of the actual SD card size via `parted`, formats FAT32, and restores the files.

## Device support

Currently, only two devices are actively supported and tested:

- RG Arc D (RK3566)
- RG35xxSP v1 (H700)

# Credits
[Rocknix](https://github.com/ROCKNIX/distribution) for platform-specific patches and the libmali workaround for mainline.
[MinUI](https://github.com/shauninman/MinUI), [Allium](https://github.com/goweiwen/Allium), and [muOS](https://muos.dev/) as launcher options.
