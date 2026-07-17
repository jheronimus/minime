# Minime is a minimal Linux firmware for Anbernic handhelds

The goal of Minime is to provide a simple foundation to play around with different UIs and ideas on Anbernic handhelds without having to rely on the stock firmware.

It aspires (strong emphasis for the moment) to cover three lines of devices:

- RK3326 (testing on RG351MP and RG351V);
- H700 (testing on RG35xxSP);
- RK3566 (testing on RG Arc D).

It comes in two flavors:

1) **Alpine**

Very fast to build (basically only needs to build the kernel and bootloaders), simple, uses busybox and has other traits of a nice embedded OS.

But Alpine is limited by musl, so has issues with proprietary parts like libmali, drastic, etc. Also optimized for size, not performance — think Os optimization, no jemmaloc, etc. However, Github builds Alpine images of Minime in roughly 10 minutes for all platforms, so it's the main platform for the project.

2) **Buildroot**

Builds almost everything from source. Panfrost pulls LLVM stack that takes hours to build, so Buildroot images use libmali. I haven't figured out libmali for H700 devices on mainline kernel, so only RK3326 and RK3566 are being built for now.

So in theory once I'm glad with the features and the hardware support and get to a point where rebuilds are not that frequent, Buildroot becomes the new main.

# Why two build targets?

In the past I would keep switching between the Alpine and Buildroot when I wanted to try different things, and the migration would take a lot of effort, hence the dual-target design now. Any configs the two can reuse, should be reused.

Minime uses cascaded config fragments whenever it can. For example, the kernel has:

- tinyconfig.base — the base modules needed by any target in Minime
- tinyconfig.<platform, e.g. H700> — device-specific drivers and options
- tinyconfig.panfrost and tinyconfig.libmali - different GPU drivers

A Github build job just pulls whatever fragments it needs for each platform. This means minimal config drift and simpler maintanence for a dual-target architecture.

# Credits
[Rocknix](https://github.com/ROCKNIX/distribution) for platform-specific patches and the libmali workaround for mainline.
[MinUI](https://github.com/ROCKNIX/distribution) and [Allium](https://github.com/ROCKNIX/distribution) as the main launcher options.
