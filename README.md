# Talos Linux for Mixtile Blade 3 in the Cluster Box

[English](README.md) · [Русский](README.ru.md)

**Talos Linux (Kubernetes) images for the Mixtile Blade 3 (RK3588) in a
Mixtile Cluster Box, with the PCIe fabric network `omi0` built in.** The
repository builds a Talos ARM64 board overlay (U-Boot, device tree,
installer), the `openmiop` system extension and ready-to-flash disk and
installer images. Nothing has to be compiled on the blades.

**Current release: [v0.7.0](https://github.com/roysbike/mixtile-talos/releases/tag/v0.7.0)**
(2026-10-24): Talos v1.14.4, Linux 6.18.57-talos, part of OpenMIOP Stack
v0.7.0. Release notes: [v0.7.0](docs/release-notes/v0.7.0.md) · [v0.6.2](docs/release-notes/v0.6.2.md) ·
[CHANGELOG.md](CHANGELOG.md).

```
ghcr.io/roysbike/mixtile-talos-installer:v0.7.0
```

## Contents

* [The OpenMIOP Stack](#the-openmiop-stack)
* [Features](#features)
* [Hardware and requirements](#hardware-and-requirements)
* [What is in the image](#what-is-in-the-image)
* [Install a new node](#install-a-new-node)
* [Machine configuration for omi0](#machine-configuration-for-omi0)
* [Upgrade a node](#upgrade-a-node)
* [Verify](#verify)
* [Technical details](#technical-details)
* [Known limitations](#known-limitations)
* [Build](#build)
* [Repository layout](#repository-layout)

## The OpenMIOP Stack

Mixtile ships the Cluster Box with its own BMC firmware and its own blade
network driver (MIOP). The **OpenMIOP Stack** is an independent, open
replacement made of three repositories that are released together:

| Repository | What it gives you | Stack v0.7.0 |
| --- | --- | --- |
| [pcie-ep-net](https://github.com/roysbike/pcie-ep-net) | the blade driver `openmiop-ep` (`omi0`), the BMC module `omi-rc`, the Blade 3 board modules | [v0.7.0](https://github.com/roysbike/pcie-ep-net/releases/tag/v0.7.0) |
| **mixtile-talos** (this one) | Talos Linux (Kubernetes) for Blade 3 with openmiop built in | [v0.7.0](https://github.com/roysbike/mixtile-talos/releases/tag/v0.7.0) (Talos v1.14.4) |
| [mixtile-clusterbox-mt7620a-openwrt](https://github.com/roysbike/mixtile-clusterbox-mt7620a-openwrt) | OpenWrt for the BMC: blade power and consoles, the BMC side of openmiop, the cluster's network edge, web UI, updates | [v0.4.1](https://github.com/roysbike/mixtile-clusterbox-mt7620a-openwrt/releases/tag/v0.4.1) (OpenWrt 25.12.6) |

```
        Cluster Box BMC (MT7620A, OpenWrt)  omi-rc, omi0 10.20.0.1, gateway to the LAN
                       |  PCIe Gen1 x1
                 ASM2824 PCIe switch        blade-to-blade traffic stays here
              /      /        \       \     Gen3 x2 each
         slot 1   slot 2   slot 3   slot 4  Mixtile Blade 3: Talos + openmiop, omi0 10.20.0.x
```

## Features

* **Official Talos, official kernel.** Talos v1.14.4 with the Siderolabs
  kernel 6.18.57-talos and the official extensions built for it (DRBD,
  ZFS, iSCSI, Panfrost GPU, Rockchip NPU).
* **Blade 3 board support.** Device tree and U-Boot 2026.07 for the
  Blade 3 (from the Armbian mainline port), TF-A and the Rockchip DDR
  blob, U-Boot at sector 64, serial console on UART2.
* **PCIe fabric network.** The `openmiop` extension brings `omi0`:
  ~8.5 Gbit/s per flow between blades, the BMC as gateway to the LAN.
* **NVMe at full speed in the box.** The M.2 NVMe trains Gen3 x2, and
  `blade3-nvme-recover` brings it back after a Cluster Box PCIe reset
  (BMC reboot).
* **Port LEDs.** `blade3-leds` drives the 2.5G Ethernet port LEDs.
* **Reproducible releases.** GitHub Actions builds every release on
  native arm64, pins the extensions by digest, checks the installer
  (`scripts/verify-installer.sh`) and publishes the image, boot files and
  checksums.

## Hardware and requirements

| | |
| --- | --- |
| Board | Mixtile Blade 3 (RK3588, 4× Cortex-A76 + 4× Cortex-A55), installed on eMMC |
| Chassis | Mixtile Cluster Box (ASM2824 PCIe switch, MT7620A BMC), up to 4 blades |
| BMC firmware | [ClusterBox firmware v0.4.1](https://github.com/roysbike/mixtile-clusterbox-mt7620a-openwrt/releases/tag/v0.4.1) (v0.4.0 and v0.3.0 work too) for `omi0`. With Mixtile's stock BMC firmware the blades boot and work, without `omi0` |
| Kubernetes | not pinned by the image; tested with v1.34.3 (Cozystack) |
| Tested on | a Cluster Box with four Blade 3: 3 control plane + 1 worker, DRBD/LINSTOR, ZFS, CloudNativePG |

The image is built for blades in a Cluster Box: the device tree sets up
the PCIe controller as an endpoint towards the box. A standalone Blade 3
is not a tested configuration.

## What is in the image

| Component | Version / source |
| --- | --- |
| Talos, imager | v1.14.4 |
| Kernel | 6.18.57-talos (the official Talos kernel; Talos packages `v1.14.0-44-g2ec10eb`) |
| U-Boot | v2026.07, Blade 3 configuration from the Armbian mainline port |
| TF-A | `lts-v2.14.6` |
| DDR training blob | rkbin `74213af1` |
| Device tree | `rk3588-mixtile-blade3.dtb` (Armbian port + Cluster Box PCIe changes, see [Technical details](#technical-details)) |
| openmiop extension | `0.7.0-v1.14.4`: `openmiop-ep`, `blade3-nvme-recover`, `blade3-leds` from [pcie-ep-net v0.7.0](https://github.com/roysbike/pcie-ep-net/releases/tag/v0.7.0) |
| Official extensions | `drbd 9.3.4`, `zfs 2.4.4`, `iscsi-tools v0.2.0`, `panfrost`, `rockchip-rknn` (the v1.14.4 builds, pinned by digest) |
| Kernel arguments | `console=tty0 console=ttyS2,1500000n8 cma=128MB … -module.sig_enforce sysctl.net.core.default_qdisc=fq` |

Release assets:

| File | Use |
| --- | --- |
| installer `ghcr.io/roysbike/mixtile-talos-installer@sha256:…` | `talosctl upgrade` and `machine.install.image` |
| `openmiop-0.7.0-blade3-talos-1.14.4-arm64.raw.xz` | disk image for a new node (eMMC) |
| `openmiop-0.7.0-blade3-talos-1.14.4-arm64-boot-files.tar.gz` | DTB, `u-boot-rockchip.bin`, `openmiop-ep.ko`, extension manifest |
| `SHA256SUMS`, `BUILD-INFO.txt` | checksums, build record (commit, versions, digests) |

## Install a new node

Each blade is flashed on its own, over USB in MaskROM mode.

1. Download the disk image and `SHA256SUMS` from the release and check
   them: `sha256sum -c --ignore-missing SHA256SUMS` (macOS:
   `shasum -a 256 -c`).
2. Get `rkdeveloptool` (Linux: the distribution package or
   [rockchip-linux/rkdeveloptool](https://github.com/rockchip-linux/rkdeveloptool);
   macOS: `brew tap IgorKha/rkdeveloptool && brew install rkdeveloptool`)
   and the Blade 3 SPL loader `rk3588_spl_loader_v1.08.111.bin` from the
   [Mixtile guide](https://www.mixtile.com/docs/installing-talos-on-mixtile-blade-3/).
   Do not use another RK3588 loader; it is only used for USB access to
   the eMMC.
3. Set DIP switch 4 of the blade to ON, power-cycle it and check that it
   shows up: `rkdeveloptool ld`.
4. Write the image:

   ```sh
   ./scripts/flash-blade3-macos.sh --image openmiop-0.7.0-blade3-talos-1.14.4-arm64.raw.xz \
       --loader rk3588_spl_loader_v1.08.111.bin
   ```

   The script (written for macOS; it only needs `rkdeveloptool` and `xz`) checks the image and its U-Boot signature,
   waits for exactly one Blade 3 in MaskROM, asks for confirmation and
   writes the eMMC. By hand: `rkdeveloptool db <loader>`, then
   `rkdeveloptool wl 0 <image.raw>`, `rkdeveloptool rd`.
5. Set DIP switch 4 back and boot. The serial console (UART2,
   1 500 000 baud; in the Cluster Box: CONSOLE in the BMC web UI) must
   show `enabling system extension openmiop 0.7.0-v1.14.4`.
6. Apply the machine configuration with `machine.install.disk:
   /dev/mmcblk0`, `machine.install.image` set to the installer above and
   the [omi0 documents](#machine-configuration-for-omi0).

Applying a configuration to a node that booted an older raw image does
not reinstall it (`install sequence: 0 phase(s)`): run `talosctl upgrade
--image …` on it afterwards. A new control-plane node cannot join etcd
while the cluster still lists a dead member: remove that member first
(`talosctl etcd remove-member <id>`, after an `etcd snapshot`).

## Machine configuration for omi0

One address per blade (10.20.0.1 is the BMC). Apply without a reboot:
`talosctl -n <node> patch mc --mode no-reboot -p @omi.yaml`.

```yaml
# omi.yaml
machine:
  kernel:
    modules:
      - name: openmiop_ep
---
apiVersion: v1alpha1
kind: LinkAliasConfig
name: omi0
selector:
  match: link.driver == "openmiop-ep"
---
apiVersion: v1alpha1
kind: LinkConfig
name: omi0
up: true
mtu: 9000
addresses:
  - address: 10.20.0.<N>/24
```

Without the `LinkAliasConfig` Talos names the link `enx<mac>`. Driver
parameters (queues, CPUs, offloads) go into
`machine.kernel.modules[].parameters`; see the
[pcie-ep-net README](https://github.com/roysbike/pcie-ep-net#configuration).

## Upgrade a node

```sh
talosctl -n <node> upgrade --image ghcr.io/roysbike/mixtile-talos-installer:v0.7.0
talosctl -n <node> patch mc --mode no-reboot \
  -p '{"machine":{"install":{"image":"ghcr.io/roysbike/mixtile-talos-installer:v0.7.0"}}}'
```

* **One node at a time.** Before the next node: etcd has all members,
  storage replicas (DRBD) are in sync, databases are healthy.
* **Keep the default drain** (no `--drain=false`). A roll without drain
  left DRBD replicas of a running database in different states and
  corrupted its ext4.
* **Cordon a node that holds a database primary first** (CloudNativePG)
  and wait for the switchover.
* **Always pass `--image` and keep `machine.install.image` equal to
  it.** `talosctl upgrade` without `--image` installs whatever that field
  names. Do not set `machine.install.grubUseUKICmdline: false`: with an
  old image in `machine.install.image` it booted a kernel that rejected
  the openmiop module.
* Rollback: `talosctl -n <node> rollback`.

## Verify

```sh
talosctl -n <node> version                        # Tag: v1.14.4
talosctl -n <node> get extensions                 # openmiop 0.7.0-v1.14.4, drbd, zfs, ...
talosctl -n <node> dmesg | grep openmiop          # "peer N up, 4 queues, doorbell, checksum offload"
talosctl -n <node> get links | grep omi0          # alias omi0, up
talosctl -n <node> get kernelmodulestatus | grep blade3   # blade3_leds, blade3_nvme_recover
ping -c3 -M do -s 8972 10.20.0.<N>                # jumbo frame from another fabric member
```

`scripts/openmiop-verify.sh <node-ip>` runs these checks in one go.
The kernel log shows `module verification failed: signature and/or
required key missing - tainting kernel` once; see below.

## Technical details

**Device tree changes for the Cluster Box** (on top of the Armbian
Blade 3 device tree; each change is commented in
`artifacts/dtb/blade3/rk3588-mixtile-blade3.dts`):

| Change | Why |
| --- | --- |
| PCIe3 x4 controller `fe150000` as endpoint `pcie3x4_ep` (2 lanes, compatible `openmiop,rk3588-pcie-ep`), host `pcie3x4` off | lanes 0-1 go to the Cluster Box switch; openmiop drives the controller itself (DBI, iATU, eDMA), so not the mainline `rockchip,rk3588-pcie-ep` |
| PHY split `data-lanes = <1 1 2 2>`, no common refclk | lanes 0-1 to the switch, 2-3 to the M.2 NVMe; the box and the blade have separate reference clocks |
| NVMe on `pcie3x2` without `reset-gpios` | the NVMe PERST# is the blade's U.2 PERST#, driven by the Cluster Box; `blade3-nvme-recover` restores the NVMe after a box reset. The NVMe trains Gen3 x2 and moves to PCI domain 0001 |
| PCIe SMMU (`mmu600_pcie`) off | endpoint traffic and eDMA reads carry stream IDs no Linux device owns |

**Module signing.** Talos signs its kernel modules with a key that only
exists during the official kernel build and is thrown away afterwards.
The openmiop modules are built here against the same kernel tree
(`artifacts/talos-kernel`, the way siderolabs/pkgs builds out-of-tree
modules: `modules_install` into `extras`, stripped) and signed with this
build's own key, which the kernel does not trust. The image therefore
boots with `-module.sig_enforce`. Everything else (DRBD, ZFS, …) is the
official signed build.

**Queueing on omi0.** The image sets `sysctl.net.core.default_qdisc=fq`
on the kernel command line, so omi0 gets `mq` with `fq` on each of its
four queues. Under load this keeps the latency on omi0 at ~0.4-0.9 ms
instead of ~3.5 ms with `pfifo_fast` (lab measurement, ping during four
TCP streams between two blades). The same setting in
`machine.sysctls` comes too late: the openmiop module creates omi0 in
the initramfs, before Talos applies the machine configuration.

**Kernel configuration.** The kernel is the unmodified Talos ARM64
kernel. `scripts/verify-kernel-config.sh` checks the configuration of
the pinned Talos packages commit (storage, NVMe, VFIO, Realtek, netfilter
for Kubernetes). Several of these drivers are modules loaded from the
initramfs, as on every Talos ARM64 image.

**Integration of openmiop:** [docs/openmiop.md](docs/openmiop.md).
**How the overlay maps onto the official Siderolabs layout**
(siderolabs/sbc-rockchip, pkgs, extensions): [docs/upstream.md](docs/upstream.md).

## Known limitations

* `module.sig_enforce` is off (see above).
* A BMC reboot resets every blade link (~150 s until `omi-rc` is back)
  and the M.2 NVMe; the blades and the NVMe recover by themselves. With
  DRBD 9.3.4 check that `out-of-sync` is 0 before a planned BMC reboot
  ([LINBIT/drbd#153](https://github.com/LINBIT/drbd/issues/153)), and
  pause CloudNativePG's primary isolation check for it.
* The BMC is the blades' gateway to the LAN: ~220-280 Mbit/s (BMC CPU).
  Blade-to-blade traffic is not affected.
* ghcr.io refuses an image pull now and then during `talosctl upgrade`;
  retrying once works.
* Not tested: a standalone Blade 3.

Network limits of openmiop:
[pcie-ep-net](https://github.com/roysbike/pcie-ep-net#known-limitations).

## Build

GitHub Actions (`.github/workflows/build-talos.yaml`) builds on a native
arm64 runner for every push to `claude/**` and `feat/**` (except
documentation-only changes) and for `v*` tags:

1. overlay and openmiop extension, pushed to the repository owner's GHCR;
2. installer and raw disk image;
3. checks: U-Boot at sector 64 of the disk image, `scripts/verify-installer.sh`
   (kernel, extensions, the openmiop modules and their `vermagic`, DTB
   content, kernel arguments), `BUILD-INFO.txt`, `SHA256SUMS`;
4. `_out/` as a workflow artifact (14 days);
5. for a tag: the GitHub release (`scripts/publish-release.sh`, notes from
   `docs/release-notes/<tag>.md`).

Locally (Docker with Buildx and arm64 emulation; much slower than CI):

```sh
docker login ghcr.io
USERNAME=<github-user-or-org> ./build.sh all        # or: overlay, image
```

Artifacts go to `_out/`. Overrides: `OUTPUT_DIR`, `REGISTRY`,
`IMAGE_TAG`, `TALOS_VERSION`; `OPENMIOP=0` builds without openmiop and
keeps `module.sig_enforce`; `PIN_EXTENSIONS=0` uses extension tags
instead of digests. The Makefile works with the GNU Make 3.81 of macOS.

## Repository layout

| Path | Content |
| --- | --- |
| `artifacts/blade3/u-boot/` | U-Boot 2026.07 for Blade 3 (defconfig, DTS) |
| `artifacts/dtb/blade3/` | the Blade 3 device tree with the Cluster Box PCIe changes |
| `artifacts/arm-trusted-firmware/rk3588/`, `artifacts/rkbin/rk3588/` | TF-A and the DDR training blob |
| `artifacts/talos-kernel/` | the Talos kernel tree (config, patches) for building modules |
| `artifacts/openmiop/` | the openmiop extension (module build, manifest) |
| `installers/blade3/` | the overlay installer (U-Boot placement, kernel arguments) |
| `profiles/blade3/` | the raw image profile |
| `build.sh`, `Makefile`, `Pkgfile` | build entry point, kres/bldr build, versions |
| `scripts/` | `verify-installer.sh`, `verify-kernel-config.sh`, `openmiop-verify.sh`, `flash-blade3-macos.sh`, `publish-release.sh` |
| `docs/` | [openmiop integration](docs/openmiop.md), [official image layout](docs/upstream.md), [release notes](docs/release-notes/) |

License: [Mozilla Public License 2.0](LICENSE) (as the Siderolabs
overlays); the openmiop modules are GPL-2.0 (pcie-ep-net).
