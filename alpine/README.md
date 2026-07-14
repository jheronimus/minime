# Minime Alpine

Minime Alpine is an immutable Alpine-based firmware branch for RK3566 Anbernic handhelds.

## Supported boards

- `rk3566`

## Build

```sh
make prepare
make image BOARD=rk3566
```

The compressed image is written to:

```text
out/rk3566/minime-alpine-rk3566.img.gz
```

## First boot

Before first boot, add Wi-Fi credentials to `.minime/config/wifi.cfg` on the FAT32 partition. The device starts passwordless telnet and FTP for local development.

On first boot, Minime expands the FAT32 partition to fill the SD card.
