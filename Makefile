SHELL := /bin/bash

ARTIFACTS ?= _out
PLATFORM ?= linux/arm64
PROGRESS ?= auto
PKGS_PREFIX ?= ghcr.io/siderolabs
PKGS ?= v1.14.0-37-g6c312e4
TOOLS_PREFIX ?= ghcr.io/siderolabs
TOOLS ?= v1.14.0-8-g9776960
SOURCE_DATE_EPOCH ?= $(shell git log -1 --pretty=%ct)

BUILD_ARGS = --file=Pkgfile
BUILD_ARGS += --provenance=false
BUILD_ARGS += --sbom=false
BUILD_ARGS += --progress=$(PROGRESS)
BUILD_ARGS += --platform=$(PLATFORM)
BUILD_ARGS += --build-arg=SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH)
BUILD_ARGS += --build-arg=PKGS_PREFIX=$(PKGS_PREFIX)
BUILD_ARGS += --build-arg=PKGS=$(PKGS)
BUILD_ARGS += --build-arg=TOOLS_PREFIX=$(TOOLS_PREFIX)
BUILD_ARGS += --build-arg=TOOLS=$(TOOLS)
# Optional, e.g. registry cache flags from build.sh (BUILD_CACHE).
BUILD_ARGS += $(CACHE_ARGS)

.DEFAULT_GOAL := sbc-mixtile-blade3

.PHONY: sbc-mixtile-blade3
sbc-mixtile-blade3:
	$(MAKE) target-sbc-mixtile-blade3 TARGET_ARGS="$(TARGET_ARGS)"

.PHONY: target-%
target-%:
	docker buildx build --target=$* $(BUILD_ARGS) $(TARGET_ARGS) .

.PHONY: clean
clean:
	rm -rf "$(ARTIFACTS)"

.PHONY: help
help:
	@echo "Targets:"
	@echo "  sbc-mixtile-blade3  Build the Blade 3 overlay"
	@echo "  target-<stage>       Build any bldr stage"
	@echo "  clean                Remove local output"
