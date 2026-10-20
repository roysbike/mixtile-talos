// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

package main

import (
	"context"
	_ "embed"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"

	"github.com/siderolabs/go-copy/copy"
	"github.com/siderolabs/talos/pkg/machinery/overlay"
	"github.com/siderolabs/talos/pkg/machinery/overlay/adapter"
	"golang.org/x/sys/unix"
)

const (
	off int64 = 512 * 64
	dtb       = "rockchip/rk3588-mixtile-blade3.dtb"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	adapter.Execute(ctx, &mixtileBlade3{})
}

type mixtileBlade3 struct{}

type mixtileBlade3ExtraOptions struct {
	SPIBoot bool `yaml:"spi_boot,omitempty"`
}

func (i *mixtileBlade3) GetOptions(_ context.Context, _ mixtileBlade3ExtraOptions) (overlay.Options, error) {
	kernelArgs := []string{
		"cma=128MB",
		"console=tty0",
		"console=ttyS2,1500000n8",
		"sysctl.kernel.kexec_load_disabled=1",
		"talos.dashboard.disabled=1",
	}

	return overlay.Options{
		Name:       "mixtile-blade3",
		KernelArgs: kernelArgs,
		PartitionOptions: overlay.PartitionOptions{
			Offset: 2048 * 10,
		},
	}, nil
}

func (i *mixtileBlade3) Install(_ context.Context, options overlay.InstallOptions[mixtileBlade3ExtraOptions]) error {
	if !options.ExtraOptions.SPIBoot {
		uBootBin := filepath.Join(options.ArtifactsPath, "arm64/u-boot/mixtile-blade3/u-boot-rockchip.bin")

		if err := uBootLoaderInstall(uBootBin, options.InstallDisk); err != nil {
			return err
		}
	}

	src := filepath.Join(options.ArtifactsPath, "arm64/dtb", dtb)
	dst := filepath.Join(options.MountPrefix, "boot/EFI/dtb", dtb)

	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}

	return copy.File(src, dst)
}

func uBootLoaderInstall(uBootBin, installDisk string) error {
	f, err := os.OpenFile(installDisk, os.O_RDWR|unix.O_CLOEXEC, 0o666)
	if err != nil {
		return fmt.Errorf("failed to open %s: %w", installDisk, err)
	}

	defer f.Close() //nolint:errcheck

	uBoot, err := os.ReadFile(uBootBin)
	if err != nil {
		return err
	}

	if _, err = f.WriteAt(uBoot, off); err != nil {
		return err
	}

	// NB: In the case that the block device is a loopback device, we sync here
	// to ensure that the file is written before the loopback device is
	// unmounted.
	return f.Sync()
}
