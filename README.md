# Talos 1.14 for Mixtile Blade 3

[English](README.md) · [Русский](README.ru.md)

This repository builds a Talos Linux `v1.14.2` ARM64 SBC overlay and bootable
images for the Mixtile Blade 3 (RK3588), including blades installed in a
Mixtile Cluster Box.

Image build and eMMC flashing stay here. Cozystack bootstrap, storage classes,
and UI access scripts belong in the separate `cozystack-box-mixtile` project.

## OpenMIOP Stack v0.1.0-rc.2

This repository's release **v0.1.0-rc.2** is the Blade OS of the OpenMIOP
stack: Talos with **openmiop**, Ethernet (`omi0`) between the blades of a
Mixtile Cluster Box over its PCIe switch, built into the installer image.

```
        Cluster Box BMC (MT7620A, OpenWrt)  — openmiop-rc helper, omi0 10.20.0.1
                       |
                    ASM2824 PCIe switch
                       |
                  PCIe fabric (Gen3 x2 per blade)
              /      /        \       \
           B1      B2          B3      B4     Mixtile Blade 3 (RK3588)
                                              Talos + openmiop, omi0 10.20.0.x
```

| OpenMIOP Stack v0.1.0-rc.2 | |
| --- | --- |
| Protocol | OpenMIOP v4 |
| Blade driver | [pcie-ep-net v0.1.0-rc.2](https://github.com/roysbike/pcie-ep-net/releases/tag/v0.1.0-rc.2) |
| Blade OS | [mixtile-talos v0.1.0-rc.2](https://github.com/roysbike/mixtile-talos/releases/tag/v0.1.0-rc.2) (this repository) |
| ClusterBox BMC | [mixtile-clusterbox-mt7620a-openwrt v0.1.0-rc.1](https://github.com/roysbike/mixtile-clusterbox-mt7620a-openwrt/releases/tag/v0.1.0-rc.1) (unchanged) |

The [release page](https://github.com/roysbike/mixtile-talos/releases/tag/v0.1.0-rc.2)
lists the installer image digest, the disk image, DTB, U-Boot, module and
checksums. What changed: [CHANGELOG.md](CHANGELOG.md). Details of the
openmiop integration: [docs/openmiop.md](docs/openmiop.md).

### Install or upgrade a Blade 3 node

Installer for v0.1.0-rc.2: use the immutable digest from the
[release page](https://github.com/roysbike/mixtile-talos/releases/tag/v0.1.0-rc.2);
the tag `ghcr.io/roysbike/mixtile-talos-installer:v0.1.0-rc.2` resolves to it.

1. Add the openmiop documents to the machine configuration (one address
   per blade; 10.20.0.1 is the BMC) and apply them without reboot:

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
     - address: 10.20.0.<last octet of the management address>/24
   ```

   ```sh
   talosctl -n <node> patch mc --mode no-reboot -p @omi.yaml
   ```

2. Upgrade (one node at a time; mind etcd quorum):

   ```sh
   talosctl -n <node> upgrade --image ghcr.io/roysbike/mixtile-talos-installer@sha256:<digest of v0.1.0-rc.2>
   ```

   New nodes: write `metal-arm64.raw.xz` **from this release** (see
   [Install from macOS](#install-from-macos)); check that the console
   shows `enabling system extension openmiop`. Then apply the machine
   configuration with `machine.install.image` set to the same reference
   and `machine.install.disk: /dev/mmcblk0`. Applying a configuration to a
   node that booted an older raw image does **not** reinstall it
   (`install sequence: 0 phase(s)`): run `talosctl upgrade --image ...` on
   it afterwards.

   A new control-plane node cannot join etcd while the cluster still lists
   a dead member (`error adding member: etcdserver: unhealthy cluster`):
   remove that member first (`talosctl etcd remove-member <id>`, after an
   `etcd snapshot`).

3. Verify:

   ```sh
   talosctl -n <node> read /proc/cmdline       # no module.sig_enforce
   talosctl -n <node> get extensions           # openmiop 0.1.0-rc.2-v1.14.2
   talosctl -n <node> dmesg | grep openmiop    # link up, node N, peer M up
   talosctl -n <node> get links | grep omi0    # alias omi0 on enx<mac>, up
   ping -c3 -M do -s 8972 10.20.0.<node>       # from another fabric member
   ```

Rollback: `talosctl -n <node> rollback`.

Known limitations: openmiop RX is polled (no interrupt-driven RX), no
multiqueue, Talos receives ~20 % slower than Debian, BMC re-enumeration
pauses the fabric ~1-2 s when a blade appears; see [CHANGELOG.md](CHANGELOG.md).

## Source baseline

- Talos and imager: `v1.14.2`
- Talos packages: `v1.14.0-37-g6c312e4`
- Linux: `6.18.54-talos`, the Talos ARM64 kernel configuration (rebuilt at the
  same PKGS commit so the openmiop module matches its ABI)
- U-Boot: `v2026.07`
- Board DTS and U-Boot configuration: Armbian mainline Blade 3 port
- TF-A: `lts-v2.14.6`
- Rockchip DDR training binary: rkbin commit `74213af1`

The overlay follows the same package and installer API as the official
[`siderolabs/sbc-rockchip`](https://github.com/siderolabs/sbc-rockchip)
Turing RK1 support. It adds the Blade 3-specific DTB, U-Boot and install
offset; it does not treat the Turing RK1 DTB as interchangeable with Blade 3.

## What is built

`sbc-mixtile-blade3` contains:

- `u-boot-rockchip.bin`, written at sector 64;
- `rk3588-mixtile-blade3.dtb`;
- the Talos 1.14 overlay installer;
- the raw-image profile.

The final images use the Talos v1.14.2 kernel (6.18.54-talos) and include:

- `ghcr.io/siderolabs/drbd:9.3.4-v1.14.2`
- `ghcr.io/siderolabs/zfs:2.4.4-v1.14.2`
- `ghcr.io/siderolabs/iscsi-tools:v0.2.0`
- `ghcr.io/siderolabs/panfrost:20260916-v1.14.2`
- `ghcr.io/siderolabs/rockchip-rknn:v1.14.2`
- openmiop `0.1.0-rc.2-v1.14.2` (built by this repository)

DRBD and ZFS therefore match the running official Talos kernel release,
module ABI and signing key.

## Build

Requirements:

- Docker with Buildx;
- access to an OCI registry visible to the build host and Talos imager;
- authenticated push access to the selected namespace.

```bash
docker login ghcr.io
USERNAME=<github-user-or-org> ./build.sh all
```

Useful individual steps:

```bash
USERNAME=<namespace> ./build.sh overlay
USERNAME=<namespace> ./build.sh image
```

Artifacts are written to `_out/`. Set `OUTPUT_DIR`, `REGISTRY`, `IMAGE_TAG`
or `TALOS_VERSION` to override their defaults.

### macOS

Docker Desktop must be running and ARM64 emulation enabled. The checked-in
Makefile is compatible with the GNU Make 3.81 shipped by macOS and does not
require GNU sed.

Cross-building and running the privileged ARM64 imager through Docker Desktop
is significantly slower than Linux. For repeatable builds, use the included
GitHub Actions workflow.

### GitHub Actions

Pushes to `claude/**` branches and `v*` tags run the workflow on a native
arm64 runner. It:

1. builds the overlay and the openmiop extension and pushes them to the
   repository owner's GHCR namespace;
2. builds installer and raw metal images and pushes the installer;
3. inspects the installer (`scripts/verify-installer.sh`) and checks
   `BUILD-INFO.txt` (commit, clean tree) and `SHA256SUMS`;
4. uploads `_out/` as a workflow artifact for 14 days;
5. on a `v*` tag, publishes the GitHub release
   (`scripts/publish-release.sh`, notes from `docs/release-notes/<tag>.md`).

No personal registry token is needed: the workflow uses `GITHUB_TOKEN` with
`packages: write`.

## Kernel configuration audit

Run:

```bash
./scripts/verify-kernel-config.sh
```

The audit checks the exact `config-arm64` from the Talos 1.14.2 package
commit and verifies that modular storage, NVMe, VFIO and Realtek drivers are
listed in the Talos ARM64 initramfs manifest.

Talos builds several drivers as modules (`m`) instead of built-ins (`y`):
NBD, NVMe, VFIO, DM thin/multipath and R8169. This is intentional and
functionally equivalent after Talos loads the modules from initramfs.

Linux 6.18/Talos uses iptables over nftables. The legacy-only
`CONFIG_IP_NF_FILTER` and `CONFIG_IP_NF_NAT` are disabled, while
`NF_TABLES`, `NFT_NAT`, `NF_NAT`, `NETFILTER_XT_NAT` and
`NETFILTER_XT_TARGET_MASQUERADE` are enabled. Enabling the legacy tables is
not required by current Kube-OVN and would require maintaining a custom
kernel plus matching DRBD/ZFS builds.

## Install from macOS

The build produces `_out/metal-arm64.raw.xz`, matching the filename used by
the [Mixtile installation guide](https://www.mixtile.com/docs/installing-talos-on-mixtile-blade-3/).
Verify and decompress the artifact before writing it:

```bash
brew install xz
xz --test _out/metal-arm64.raw.xz
xz --decompress --keep _out/metal-arm64.raw.xz
shasum -a 256 _out/metal-arm64.raw.xz
```

### microSD

Identify the target carefully. The following operation destroys all data on
the selected disk:

```bash
diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=_out/metal-arm64.raw of=/dev/rdiskN bs=4m
sync
diskutil eject /dev/diskN
```

Replace `diskN` with the whole microSD device, not a partition such as
`diskN1`. On macOS, press `Ctrl-T` while `dd` is running to print progress.

### eMMC over USB

Install `rkdeveloptool` from a third-party Homebrew tap:

```bash
brew tap IgorKha/rkdeveloptool
brew trust --formula IgorKha/rkdeveloptool/rkdeveloptool
brew install rkdeveloptool
```

Alternatively, build the
[official Rockchip source](https://github.com/rockchip-linux/rkdeveloptool):

```bash
brew install automake autoconf libusb pkg-config
git clone https://github.com/rockchip-linux/rkdeveloptool.git
cd rkdeveloptool
autoreconf -i
./configure
make
sudo install -m 0755 rkdeveloptool /usr/local/bin/rkdeveloptool
```

Put the Blade 3 into Rockchip Loader/Maskrom mode and confirm that it is
visible:

```bash
rkdeveloptool ld
```

The temporary `rk3588_spl_loader_*.bin` used by `rkdeveloptool db` is not
generated by this repository. Obtain the Blade 3-compatible loader described
in the Mixtile guide; do not substitute an arbitrary RK3588 loader. Save it
as `rk3588_spl_loader_v1.08.111.bin` in the repository root, set DIP switch 4
to ON, power-cycle the board, and run:

```bash
./scripts/flash-blade3-macos.sh
```

The script validates the compressed image and its RKNS U-Boot signature,
waits for exactly one Blade 3 in MaskROM mode, asks for
destructive-operation confirmation, loads the temporary SPL, and writes the
full image to eMMC. Run it with `--help` to override the image or loader
paths.

The raw image already contains the project-built U-Boot at sector 64. The SPL
loader above is only used temporarily for USB access to eMMC.

Each Blade 3 in a Cluster Box is flashed separately.

## First boot

U-Boot tries microSD, NVMe and then eMMC. Serial console is UART2 at
1,500,000 baud.

Before replacing a working installation:

1. Keep a copy of the currently bootable image.
2. Test the new image from removable media.
3. Capture the full UART log.
4. In Talos maintenance mode verify eMMC, NVMe and both Ethernet ports.
5. Only then install to eMMC/NVMe.

After boot:

```bash
talosctl -n <node> version
talosctl -n <node> read /proc/config.gz | gzip -dc
talosctl -n <node> get extensions
talosctl -n <node> get kernelmodulestatus
```

Hardware runtime verification—KVM guests, Geneve traffic, DRBD replication
and ZFS import—requires a physical Blade 3 and is not replaced by a
successful cross-build.

## Known risk

The Blade 3 mainline support is newer and less mature than the vendor 6.1
tree. U-Boot 2026.07 includes the Armbian FUSB302/USB-C PD description so PD
negotiation happens before Linux starts. For the first boot, use UART and a
known-good power source, and do not overwrite the working boot medium until
PCIe, NVMe and Ethernet have been observed.

Cluster Box endpoint support comes from the open `openmiop` driver
(<https://github.com/roysbike/pcie-ep-net>), packaged here as a system
extension together with the device tree changes it needs. See
[docs/openmiop.md](docs/openmiop.md) for what changes, the build, the
canary procedure and rollback.
