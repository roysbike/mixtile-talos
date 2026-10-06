# Changelog

All notable changes to this project are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0-rc.1] - 2026-10-06

First release candidate of Talos for the Mixtile Blade 3 with Cluster Box
PCIe fabric networking (openmiop). Part of OpenMIOP Stack v0.1.0-rc.1
(protocol v4). The installer image contains everything; nothing has to be
built to install it.

### Versions

| Component | Version |
| --- | --- |
| Talos | v1.14.2 (installer-base v1.14.2, imager v1.14.2) |
| Linux kernel | 6.18.54-talos: the official Talos kernel configuration, rebuilt at PKGS v1.14.0-37-g6c312e4 with the Talos LLVM 22.1.8 toolchain so external modules match its ABI (symbol CRCs checked against the official modules) |
| Kubernetes | not pinned by the image; tested with v1.34.3 (Talos v1.14.2 default: 1.37.1) |
| openmiop | 0.1.0-rc.1-v1.14.2 from roysbike/pcie-ep-net `922389d` (tag v0.1.0-rc.1; driver source identical to the hardware-tested `a7a8177`) |
| U-Boot | 2026.07 (Blade 3 board support from this repository) |
| TF-A | lts-v2.14.6 |
| rkbin (DDR init) | 74213af1 |
| System extensions | drbd 9.3.4-v1.14.2, zfs 2.4.4-v1.14.2, iscsi-tools v0.2.0, panfrost 20260916-v1.14.2, rockchip-rknn v1.14.2, openmiop 0.1.0-rc.1-v1.14.2 |

### Added

- openmiop system extension: `openmiop-ep.ko` built against the exact
  Talos kernel tree, installed to `/usr/lib/modules/6.18.54-talos/extras`,
  listed in the generated `modules.dep`/`modules.alias` (autoloads by DT
  modalias; `machine.kernel.modules` loads it explicitly).
- PCIe endpoint mode on the Cluster Box connector: `pcie3x4_ep`
  (`fe150000`) enabled as `openmiop,rk3588-pcie-ep`, x2, no reset GPIO;
  the host controller on the same port disabled. The blade appears behind
  the ASM2824 as `1d87:4f4d`, link Gen3 x2.
- `omi0` network: OpenMIOP protocol v4 multi-peer L2 (full mesh between
  blades, broadcast/multicast, ARP, IPv4, IPv6 ND), jumbo frames (MTU
  9000). Documented machine configuration: `LinkAliasConfig`
  (`link.driver == "openmiop-ep"` → `omi0`; udev would name it
  `enx<mac>`) and `LinkConfig` (address, MTU).
- Release pipeline: tag builds push the overlay, the openmiop extension
  and the installer to GHCR, inspect the installer image
  (`scripts/verify-installer.sh`: kernel release, command line, extension
  list, module path/hash/vermagic, modules.dep/alias, DTB nodes) and
  publish a GitHub release whose notes carry the image digests from
  `BUILD-INFO.txt`.
- `BUILD-INFO.txt` (commit, clean tree, Talos/PKGS/TOOLS, kernel,
  openmiop version and source commit, image digests, module vermagic) and
  `SHA256SUMS` next to the images.
- `scripts/openmiop-verify.sh`: read-only checks on a node after install.
- Native arm64 GitHub Actions build (the kernel tree build is too slow
  under QEMU).

### Changed

- Device tree for the Cluster Box (compared with installer v0.3.2 by
  decompiling both DTBs; no other node changed):
  - `pcie30phy`: `data-lanes = <1 1 2 2>` — two x2 halves: lanes 0-1 to
    the Cluster Box connector, lanes 2-3 to the M.2 slot;
    `rockchip,rx-common-refclk-mode = <0 0 0 0>` (separate reference
    clocks).
  - `pcie3x2` (`fe160000`) enabled for the NVMe with PERST (GPIO4_B6):
    the local NVMe is kept, now at Gen3 x2 (8 GT/s; previously 2.5 GT/s
    on the aggregated PHY), PCI domain `0001`.
  - PCIe SMMU (`mmu600_pcie`, `iommu@fc900000`) disabled: inbound BAR
    traffic from other blades and the endpoint eDMA carry stream IDs no
    Linux device owns. PCIe devices (NVMe, RTL8125) DMA without IOMMU
    translation; PCIe passthrough with vfio-pci is not available.
  - NPU: the three RKNN cores, their IOMMUs and the NPU power-domain
    supply stay enabled as in installer v0.3.2.
- Kernel command line: `module.sig_enforce=1` removed (imager
  `--extra-kernel-arg -module.sig_enforce`). Talos signs its modules
  with a key discarded after each kernel build, so no other module can
  be signed for it; the kernel is tainted by the unsigned module.
- Image package names are configurable (`OVERLAY_NAME`, `OPENMIOP_NAME`,
  `INSTALLER_IMAGE`); CI publishes `sbc-mixtile-blade3-ci`, `openmiop` and
  `mixtile-talos-installer`.

### Tested

Cluster Box with four Blade 3: two Debian 12 (vendor 6.1.99) and two
Talos v1.14.2 control-plane nodes (canary one node at a time), plus the
BMC. The Talos nodes ran CI build ci-6 of this repository: same kernel,
DTB, extensions and openmiop driver source as this release.

| Test | Result |
| --- | --- |
| Upgrade, boot, etcd rejoin, extensions, command line | OK on both Talos nodes |
| NVMe | 8 GT/s x2 (was 2.5 GT/s); ZFS pool ONLINE on both nodes |
| Endpoint | link 8 GT/s x2, activated by the BMC, peers up; module autoloaded |
| Five-member matrix | ping + jumbo between all members, TCP to apid over the fabric, IPv6 `ff02::1` |
| Debian → Talos / Talos → Debian TCP | 6.4-6.6 / 7.4-7.5 Gbit/s |
| Talos ↔ Talos TCP | 6.48 / 6.73 Gbit/s, bidirectional 4.45 + 4.51 |
| SHA-256 integrity | 1 GiB Debian→Talos, 512 MiB Talos→Debian, 512 MiB Talos→Talos: identical |
| Release image | inspected in CI (`verify-installer.sh`); the same check passes on ci-6 |

### Known limitations

- openmiop RX is polled by a kernel thread; interrupt-driven RX is not
  implemented or tested. No multiqueue.
- Talos receives ~20 % slower than Debian in these tests (6.4 vs 8.0
  Gbit/s); not investigated.
- BMC root-port re-enumeration pauses all fabric traffic ~1-2 s when a
  blade appears without a BAR address; an endpoint that disappears
  without the leave handshake (crash, power loss) can race a BMC read and
  wedge the fabric until the BMC reboots.
- Upgrading a node whose pods hold volumes on failed storage: the drain
  can fail and the reboot can hang unmounting; `--drain=false` and a BMC
  hardware reset (`nodectl reset`) were needed.
- Not hardware-tested: booting this exact release build (its content
  equals the tested ci-6 except version labels and the pcie-ep-net pin
  with identical driver source), installing from the raw disk image of
  this build, NPU/GPU workloads (`rocket` and `panthor` load), VFIO, more
  than four blades.

[0.1.0-rc.1]: https://github.com/roysbike/mixtile-talos/releases/tag/v0.1.0-rc.1
