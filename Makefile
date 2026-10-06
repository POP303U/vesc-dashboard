VESC_TOOL ?= vesc_tool
VERSION := $(shell git describe --tags --always --dirty)

all: build/dashboard.vescpkg

build/dashboard.vescpkg: ui.qml pkgdesc.qml README.md
	mkdir -p build
	sed 's/@VERSION@/$(VERSION)/' ui.qml > build/ui.qml
	cp pkgdesc.qml README.md build/
	cd build && $(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml