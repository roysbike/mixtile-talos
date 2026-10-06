# Talos 1.14 for Mixtile Blade 3

[English](README.md) · [Русский](README.ru.md)

This repository builds a Talos Linux `v1.14.2` ARM64 SBC overlay and bootable
images for the Mixtile Blade 3 (RK3588), including blades installed in a
Mixtile Cluster Box.

Image build and eMMC flashing stay here. Cozystack bootstrap, storage classes,
and UI access scripts belong in the separate `cozystack-box-mixtile` project.

## Source baseline

- Talos and imager: `v1.14.2`
- Talos packages: `v1.14.0-37-g6c312e4`
- Linux: `6.18.54`, the unmodified Talos ARM64 kernel
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

The final images use the official Talos 1.14.1 kernel and include:

- `ghcr.io/siderolabs/drbd:9.3.4-v1.14.2`
- `ghcr.io/siderolabs/zfs:2.4.4-v1.14.2`
- `ghcr.io/siderolabs/iscsi-tools:v0.2.0`

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

Push this branch to GitHub, open **Actions → Build Talos for Mixtile Blade 3
→ Run workflow**. The workflow:

1. enables ARM64 emulation and Buildx;
2. publishes the temporary overlay to the repository owner's GHCR namespace;
3. builds installer and raw metal images;
4. uploads `_out/` as a workflow artifact for 14 days.

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
