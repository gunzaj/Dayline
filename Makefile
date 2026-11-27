SHELL := /bin/bash

.PHONY: build install test garmin run clean

# Build dist/Dayline.app (ad-hoc signed).
build:
	./scripts/build.sh

# Build, copy to /Applications and launch.
install:
	./scripts/install.sh

# Behavioural checks and a release build.
test:
	./scripts/test.sh

# One-time Garmin helper install (python-garminconnect, pinned).
garmin:
	./scripts/setup-garmin.sh

# Run the built app from dist/ with a year of sample data.
run: build
	DAYLINE_DEMO=1 ./dist/Dayline.app/Contents/MacOS/Dayline

clean:
	swift package clean
	rm -rf dist
