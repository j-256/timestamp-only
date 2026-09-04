.PHONY: all app check check-app check-dmg clean dmg lint prepare-release publish-release test test-cli verify-app verify-dmg version

all: check check-app

check: lint test

lint:
	swift format lint --strict --recursive Sources Tests Package.swift
	shellcheck scripts/build-app scripts/create-dmg scripts/notarize-dmg scripts/release scripts/version scripts/verify-app scripts/verify-dmg Tests/Scripts/CommandLineTests.sh Tests/Scripts/ReleaseCommandLineTests.sh

test:
	swift test
	$(MAKE) test-cli

test-cli:
	bash Tests/Scripts/CommandLineTests.sh
	bash Tests/Scripts/ReleaseCommandLineTests.sh

app:
	scripts/build-app

verify-app:
	scripts/verify-app

check-app: app
	scripts/verify-app

dmg: check-app
	scripts/create-dmg --force

verify-dmg:
	scripts/verify-dmg

check-dmg: dmg
	scripts/verify-dmg

prepare-release:
	scripts/release prepare

publish-release:
	scripts/release publish

version:
	@if [ -z "$(V)" ]; then echo "usage: make version V=<X.Y.Z> [BUILD=<integer>]"; exit 2; fi
	@if [ -n "$(BUILD)" ]; then \
		scripts/version --build-number "$(BUILD)" "$(V)"; \
	else \
		scripts/version "$(V)"; \
	fi

clean:
	rm -rf build .build
