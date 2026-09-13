SHELL := /usr/bin/env bash
VERSION ?= dev

.PHONY: build check test clean

build:
	@bash scripts/build.sh "$(VERSION)"

check: build
	@bash -n dist/auto-xray
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck dist/auto-xray scripts/build.sh tests/smoke.sh; else echo "shellcheck not installed; skipped"; fi

test: check
	@bash tests/smoke.sh
	@if command -v bats >/dev/null 2>&1; then bats tests/unit.bats; else echo "bats not installed; extended tests skipped"; fi

clean:
	@rm -rf dist
