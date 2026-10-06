# Changelog

## v0.1.0-rc.1 — 2026-10-06

First release candidate of Talos for the Mixtile Blade 3 with Cluster Box
PCIe fabric networking (openmiop). The installer image contains everything;
nothing has to be built to install it.

### Versions

| Component | Version |
| --- | --- |
| Talos | v1.14.2 (installer-base v1.14.2, imager v1.14.2) |
| Linux kernel | 6.18.54-talos (official Talos kernel, PKGS v1.14.0-37-g6c312e4, clang 22.1.8) |
| Kubernetes | tested with v1.34.3 (the cluster's configured version); the image does not pin Kubernetes — Talos v1.14.2's default is 1.37.1 |
| openmiop | 0.1.0-rc.1-v1.14.2, roysbike/pcie-ep-net `2aacb2b` (driver source identical to the hardware-tested `a7a8177`) |
| U-Boot | 2026.07 (Blade 3 board support from this repository) |
| TF-A | lts-v2.14.6 |
| rkbin (DDR init) | 74213af1 |
| System extensions | drbd 9.3.4-v1.14.2, zfs 2.4.4-v1.14.2, iscsi-tools v0.2.0, panfrost 20260916-v1.14.2, rockchip-rknn v1.14.2, openmiop 0.1.0-rc.1-v1.14.2 |

### Mixtile Blade 3 / RK3588 support

* Talos SBC overlay `mixtile-blade3`: U-Boot at sector 64, Blade 3 DTB,
  installer.
* eMMC boot (tested), management Ethernet (`end0`, stable RTL8125 MACs).
* NPU: three RKNN cores, their IOMMUs and the NPU power-domain supply are
  enabled as in installer v0.3.2; `rocket` loads (not functionally tested).
* GPU: `panthor` loads (not functionally tested).

### Device tree changes for the Cluster Box (vs installer v0.3.2)

Only PCIe changes; every other node is unchanged (compared by decompiling
both DTBs):

* `pcie30phy`: `data-lanes = <1 1 2 2>` — two x2 halves, PHY lanes 0-1 to
  the Cluster Box connector (`pcie3x4`, fe150000), lanes 2-3 to the M.2 slot
  (`pcie3x2`, fe160000). Previously the PHY was aggregated and the NVMe
  trained at 2.5 GT/s.
* `pcie30phy`: `rockchip,rx-common-refclk-mode = <0 0 0 0>` — the blade and
  the Cluster Box have separate reference clocks.
* `pcie3x4` (host) disabled; `pcie3x4_ep` enabled as
  `openmiop,rk3588-pcie-ep`, x2, no reset GPIO.
* `pcie3x2` enabled for the NVMe with PERST (GPIO4_B6) and its pinctrl.
* `mmu600_pcie` (PCIe SMMU) disabled — required for the endpoint: inbound
  BAR traffic from other blades and the eDMA carry stream IDs no Linux
  device owns. PCIe devices (NVMe, RTL8125) DMA without IOMMU
  translation; no device may rely on vfio-pci for PCIe passthrough.

### Cluster Box fabric (openmiop)

* PCIe endpoint mode on the Cluster Box fabric: each blade's fe150000
  becomes a PCIe endpoint (`1d87:4f4d`) behind the ASM2824 switch.
* Link: PCIe Gen3 x2 (8 GT/s) to the switch; local NVMe retained on its own
  Gen3 x2 link.
* `openmiop-ep.ko` ships as a system extension (`/usr/lib/modules/6.18.54-talos/extras`),
  is listed in the generated `modules.dep` with its DT aliases and is loaded
  at boot (`machine.kernel.modules`; it also autoloads by modalias).
* Kernel argument `module.sig_enforce=1` is removed: Talos signs its own
  modules with a key discarded after each kernel build, so no other module
  can be signed for it. The kernel is tainted (unsigned module); nothing
  else changes.
* `omi0` network: udev names the link `enx<mac>`; a `LinkAliasConfig`
  (`link.driver == "openmiop-ep"`) names it `omi0`, a `LinkConfig` sets the
  address and MTU (see the release notes).
* Multi-peer L2: full mesh between all blades, broadcast/multicast, ARP,
  IPv4, IPv6 ND, unknown-unicast flooding, MAC learning.
* Jumbo frames: MTU 9000 between blades and to the BMC.
* BMC / ASM2824 support: the Cluster Box runs `openmiop-rc` (from
  pcie-ep-net v0.1.0-rc.1). It restores BARs and MPS, publishes the peer
  table and re-enumerates from the PCIe root port when a blade appears
  without a BAR address (bridge windows are sized at first assignment);
  P2P traffic pauses ~1-2 s then.

### Tested on hardware (2026-10-06)

Cluster Box, four Blade 3: two Debian 12 (vendor 6.1.99) and two Talos
(.201, .204) running this image's content (CI build ci-6, same kernel,
DTB, extensions and driver source as this release).

| Test | Result |
| --- | --- |
| Boot, etcd rejoin, extensions, cmdline | OK on both Talos nodes |
| NVMe | 8 GT/s x2 (was 2.5 GT/s); ZFS pool back ONLINE on both nodes |
| Endpoint | link 8 GT/s x2, activated by the BMC, peers up |
| Five-member matrix | ping + jumbo between all members, TCP to apid over the fabric, IPv6 `ff02::1` |
| Debian ↔ Debian TCP | 8.0-8.3 Gbit/s each way, ~15.8 bidirectional |
| Debian ↔ Talos TCP | 6.4-6.6 (to Talos) / 7.4-7.5 (from Talos) Gbit/s |
| Talos ↔ Talos TCP | 6.48 / 6.73 Gbit/s, bidirectional 4.45 + 4.51 |
| SHA-256 integrity | 1 GiB Debian→Talos, 512 MiB Talos→Debian, 512 MiB Talos→Talos, all identical |

### Known limitations

* RX is polled by a kernel thread; interrupt-driven RX is not implemented
  or tested.
* No multiqueue.
* Talos receive throughput is ~20 % lower than Debian's in these tests
  (6.4 vs 8.0 Gbit/s); not investigated.
* BMC root-port re-enumeration pauses all fabric traffic for ~1-2 s when a
  blade appears without a BAR address, and still needs care: an endpoint
  that disappears without the leave handshake (crash, power loss) can race
  a BMC read, which once took the fabric down until the BMC was rebooted.
* Upgrading a node whose pods hold volumes on failed storage: the drain
  can fail and the reboot can hang unmounting; `--drain=false` and a BMC
  hardware reset (`nodectl reset`) were needed.
* Not hardware-tested: installing from the raw disk image of this exact
  build (the canaries were upgrades), the v0.1.0-rc.1 build itself on a
  node (its content equals the tested ci-6 build except version labels),
  NPU/GPU workloads, VFIO, more than four blades, mixed Debian/Talos
  orders other than slots 1-4 here.
