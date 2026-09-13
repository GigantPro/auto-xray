SHELL := /usr/bin/env bash
VERSION ?= dev

.PHONY: build check test clean

build:
	@bash scripts/build.sh "$(VERSION)"

check: build
	@bash -n dist/auto-xray
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck -x src/auto-xray.sh src/lib/*.sh scripts/build.sh; else echo "shellcheck not installed; skipped"; fi

test: check
	@if command -v bats >/dev/null 2>&1; then bats tests; else bash tests/smoke.sh; fi

clean:
	@rm -rf dist
