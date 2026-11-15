# Font Repository Makefile
SHELL := /bin/bash
.SILENT:

# Variables
XDG_DATA_HOME ?= $(HOME)/.local/share
XDG_CONFIG_HOME ?= $(HOME)/.config
FONTS_DIR = share/fonts
BIN_DIR = bin
INSTALL_FONTS_DIR = $(XDG_DATA_HOME)/fonts
UI = $(BIN_DIR)/ui.sh

define HELP_TEXT
Font Repository Management

Available targets:

  make help               Show this help
  make all                Run normal, usage, previews, and stats
  make smoke              Check organization and target requirements

Font organization:
  make normal             Organize fonts
  make normal-staged      Organize staged fonts
  make normal-unstaged    Organize tracked fonts with unstaged changes
  make normal-untracked   Organize untracked fonts
  make dryrun             Preview font organization
  make dryrun-staged      Preview staged font organization
  make dryrun-unstaged    Preview unstaged tracked font organization
  make dryrun-untracked   Preview untracked font organization
  make clean              Remove duplicate and delete directories

Single-file processing:
  $(BIN_DIR)/rename-fonts.sh --file /path/to/font.ttf:share/fonts

Previews and statistics:
  make previews          Generate font previews and catalog
  make stats             Generate repository statistics
  make usage             Remove font usage restrictions

Installation and Fontconfig:
  make install           Install fonts and configure Fontconfig
  make uninstall         Remove installed fonts from XDG_DATA_HOME
  make fontconfig        Generate Fontconfig configuration files

Release management:
  make release-major     Create and publish a major release
  make release-minor     Create and publish a minor release
  make release-patch     Create and publish a patch release
  make release-amend     Replace the latest release archive

Environment variables:
  XDG_DATA_HOME=$(XDG_DATA_HOME)
  XDG_CONFIG_HOME=$(XDG_CONFIG_HOME)
  INSTALL_FONTS_DIR=$(INSTALL_FONTS_DIR)
endef
export HELP_TEXT

.PHONY: help
help: | _check-gum
	@if [ -t 1 ]; then \
		printf '%s\n' "$$HELP_TEXT" | awk 'BEGIN { print "Group,Target,Action" } \
			/^[^ ]/ { group=$$0; sub(/:$$/, "", group); next } \
			/^  make / { target=$$2; $$1=$$2=""; sub(/^ +/, ""); \
				gsub(/"/, "\"\"", group); gsub(/"/, "\"\"", target); gsub(/"/, "\"\"", $$0); \
				printf "\"%s\",\"%s\",\"%s\"\n", group, target, $$0 }' | $(UI) table || exit 1; \
		$(UI) info "Single font: $(BIN_DIR)/rename-fonts.sh --file /path/to/font.ttf:share/fonts"; \
		$(UI) info "XDG_DATA_HOME=$(XDG_DATA_HOME)"; \
		$(UI) info "XDG_CONFIG_HOME=$(XDG_CONFIG_HOME)"; \
		$(UI) info "INSTALL_FONTS_DIR=$(INSTALL_FONTS_DIR)"; \
	else \
		$(UI) heading "$$HELP_TEXT"; \
	fi

.PHONY: _check-gum
_check-gum:
	@source "$(BIN_DIR)/ui.sh" && ui_require_gum

.PHONY: all
all: normal usage previews stats | _check-gum

.PHONY: previews
previews: | _check-gum
	@$(UI) info "Generate font previews."
	$(BIN_DIR)/gen-previews.sh

.PHONY: stats
stats: | _check-gum
	@$(UI) info "Generate repository statistics."
	$(BIN_DIR)/gen-stats.sh

.PHONY: usage
usage: | _check-gum
	@$(UI) info "Set font usage restrictions."
	$(BIN_DIR)/set-usage.sh

.PHONY: normal
normal: | _check-gum
	@$(UI) info "Organize fonts."
	$(BIN_DIR)/rename-fonts.sh

.PHONY: normal-staged
normal-staged: | _check-gum
	@$(UI) info "Organize staged fonts."
	$(BIN_DIR)/rename-fonts.sh --staged

.PHONY: normal-untracked
normal-untracked: | _check-gum
	@$(UI) info "Organize untracked fonts."
	$(BIN_DIR)/rename-fonts.sh --untracked

.PHONY: normal-unstaged
normal-unstaged: | _check-gum
	@$(UI) info "Organize tracked fonts with unstaged changes."
	$(BIN_DIR)/rename-fonts.sh --unstaged

.PHONY: dryrun
dryrun: | _check-gum
	@$(UI) info "Preview font organization changes."
	$(BIN_DIR)/rename-fonts.sh --dry-run

.PHONY: dryrun-staged
dryrun-staged: | _check-gum
	@$(UI) info "Preview staged font organization."
	$(BIN_DIR)/rename-fonts.sh --staged --dry-run

.PHONY: dryrun-untracked
dryrun-untracked: | _check-gum
	@$(UI) info "Preview untracked font organization."
	$(BIN_DIR)/rename-fonts.sh --untracked --dry-run

.PHONY: dryrun-unstaged
dryrun-unstaged: | _check-gum
	@$(UI) info "Preview tracked fonts with unstaged changes."
	$(BIN_DIR)/rename-fonts.sh --unstaged --dry-run

.PHONY: smoke
smoke: | _check-gum
	@TEMP_LOG=$$(mktemp) && TEMP_ERR=$$(mktemp) && TEMP_COMPARE_LOG=$$(mktemp) && TEMP_COMPARE_ERR=$$(mktemp) && SMOKE_ROWS=$$(mktemp) || { $(UI) error "Could not prepare smoke test output."; exit 1; }; \
	trap 'rm -f "$$TEMP_LOG" "$$TEMP_ERR" "$$TEMP_COMPARE_LOG" "$$TEMP_COMPARE_ERR" "$$SMOKE_ROWS"' EXIT; \
	csv_field() { local value=$${1//\"/\"\"}; printf '"%s"' "$$value"; }; \
	smoke_row() { csv_field "$$1" >> "$$SMOKE_ROWS"; printf ',' >> "$$SMOKE_ROWS"; csv_field "$$2" >> "$$SMOKE_ROWS"; printf ',' >> "$$SMOKE_ROWS"; csv_field "$$3" >> "$$SMOKE_ROWS"; printf '\n' >> "$$SMOKE_ROWS"; }; \
	smoke_summary() { if [ -t 1 ]; then { printf '"Check","Result","Details"\n'; cat "$$SMOKE_ROWS"; } | $(UI) table || exit 1; fi; }; \
	smoke_fail() { smoke_row "$$1" "FAIL" "$$2"; $(UI) error "$$2"; smoke_summary; exit 1; }; \
	smoke_report() { if [ ! -t 1 ]; then $(UI) "$$1" "$$2"; fi; }; \
	$(UI) heading "Smoke test"; \
	smoke_report info "[1/3] Validate font organization."; \
	if $(BIN_DIR)/rename-fonts.sh --dry-run > "$$TEMP_LOG" 2> "$$TEMP_ERR"; then \
		if [ -t 1 ]; then grep -v '^Analyzing fonts:' "$$TEMP_ERR" >&2 || true; else cat "$$TEMP_ERR" >&2; fi; \
		fonts=$$(grep -oP 'Processed \K\d+(?= font files)' "$$TEMP_LOG" | tail -1); \
		families=$$(grep -oP 'across \K\d+(?= families)' "$$TEMP_LOG" | tail -1); \
		smoke_row "Font organization" "PASS" "$${fonts:-0} fonts, $${families:-0} families."; \
		smoke_report success "Font organization passed ($${fonts:-0} fonts, $${families:-0} families)."; \
	else \
		organization_status=$$?; \
		smoke_row "Font organization" "FAIL" "Exit status $$organization_status."; \
		$(UI) error "Font organization failed."; \
		cat "$$TEMP_LOG"; \
		cat "$$TEMP_ERR" >&2; \
		smoke_summary; \
		exit 1; \
	fi; \
	smoke_report info "[2/3] Verify target requirements."; \
	command -v fontimage >/dev/null 2>&1 || smoke_fail "Preview requirements" "fontimage is not installed."; \
	command -v fc-query >/dev/null 2>&1 || smoke_fail "Preview requirements" "fc-query is not installed."; \
	[ -d "$(FONTS_DIR)" ] || smoke_fail "Preview requirements" "Font directory $(FONTS_DIR) does not exist."; \
	[ -n "$$(find "$(FONTS_DIR)" -type f \( -name '*.otf' -o -name '*.ttf' \) -print -quit)" ] || smoke_fail "Preview requirements" "No font files exist in $(FONTS_DIR)."; \
	smoke_row "Preview requirements" "PASS" "fontimage, fc-query, and font files in $(FONTS_DIR)."; \
	smoke_report success "Preview requirements are available."; \
	if command -v fc-cache >/dev/null 2>&1; then \
		smoke_row "Install requirements" "PASS" "fc-cache is installed."; \
	else \
		smoke_row "Install requirements" "WARN" "fc-cache is not installed; cache updates will be skipped."; \
		$(UI) warn "fc-cache is not installed; cache updates will be skipped."; \
	fi; \
	smoke_report success "Install requirements are available."; \
	command -v git >/dev/null 2>&1 || smoke_fail "Release requirements" "git is not installed."; \
	command -v gh >/dev/null 2>&1 || smoke_fail "Release requirements" "gh is not installed."; \
	if git diff-index --quiet HEAD -- 2>/dev/null; then \
		smoke_row "Release requirements" "PASS" "git and gh are available; no uncommitted changes."; \
		smoke_report success "Release requirements are available."; \
	else \
		smoke_row "Release requirements" "WARN" "Release has uncommitted changes."; \
		smoke_report info "Release has uncommitted changes."; \
	fi; \
	command -v fonttools >/dev/null 2>&1 || smoke_fail "Usage requirements" "fonttools is not installed."; \
	smoke_row "Usage requirements" "PASS" "fonttools is installed."; \
	smoke_report success "Usage requirements are available."; \
	smoke_report info "[3/3] Compare repository statistics."; \
	if $(BIN_DIR)/gen-stats.sh --compare > "$$TEMP_COMPARE_LOG" 2> "$$TEMP_COMPARE_ERR"; then \
		compare_status=0; \
	else \
		compare_status=$$?; \
	fi; \
	if [ ! -t 1 ]; then grep -hE '^Analyzing' "$$TEMP_COMPARE_LOG" "$$TEMP_COMPARE_ERR" || true; fi; \
	if grep -Fq 'Statistics differ from README.md' "$$TEMP_COMPARE_LOG" "$$TEMP_COMPARE_ERR"; then \
		smoke_row "Repository statistics" "DIFFER" "Statistics differ from README.md; run make stats."; \
		$(UI) warn "Statistics differ from README.md."; \
		cat "$$TEMP_COMPARE_LOG"; \
		cat "$$TEMP_COMPARE_ERR" >&2; \
		$(UI) info "Run 'make stats' to update README.md."; \
	elif grep -hE 'Statistics match README\.md \([0-9]+ fonts, [0-9]+ families\)' "$$TEMP_COMPARE_LOG" "$$TEMP_COMPARE_ERR" >/dev/null; then \
		status=$$(grep -hE 'Statistics match README\.md \([0-9]+ fonts, [0-9]+ families\)' "$$TEMP_COMPARE_LOG" "$$TEMP_COMPARE_ERR" | tail -1); \
		fonts=$$(printf '%s\n' "$$status" | grep -oP '\(\K\d+(?= fonts)'); \
		families=$$(printf '%s\n' "$$status" | grep -oP ', \K\d+(?= families)'); \
		smoke_row "Repository statistics" "PASS" "$$fonts fonts, $$families families; README.md matches."; \
		smoke_report success "Statistics match README.md ($$fonts fonts, $$families families)."; \
	else \
		smoke_row "Repository statistics" "FAIL" "Comparison exited with status $$compare_status."; \
		$(UI) error "Statistics comparison failed (exit status $$compare_status)."; \
		cat "$$TEMP_COMPARE_LOG"; \
		cat "$$TEMP_COMPARE_ERR" >&2; \
		smoke_summary; \
		exit 1; \
	fi; \
	smoke_summary; \
	$(UI) success "Smoke test complete."

.PHONY: clean
clean: | _check-gum
	@TEMP_TARGETS=$$(mktemp) || { $(UI) error "Could not prepare the clean target list."; exit 1; }; \
	TEMP_TABLE=$$(mktemp) || { rm -f "$$TEMP_TARGETS"; $(UI) error "Could not prepare the clean target list."; exit 1; }; \
	trap 'rm -f "$$TEMP_TARGETS" "$$TEMP_TABLE"' EXIT; \
	find "$(FONTS_DIR)" -type d \( -name ".duplicate" -o -name ".delete" \) -print0 2>/dev/null > "$$TEMP_TARGETS" || true; \
	printf '"Directory","Files"\n' > "$$TEMP_TABLE" || { $(UI) error "Could not prepare the clean target table."; exit 1; }; \
	csv_field() { local value=$${1//\"/\"\"}; printf '"%s"' "$$value"; }; \
	if [ -t 1 ]; then \
		while IFS= read -r -d '' dir; do \
			count=$$(find "$$dir" -type f -printf . 2>/dev/null | wc -c | tr -d '[:space:]'); \
			case "$$dir" in /*) full_path=$$dir ;; *) full_path="$(CURDIR)/$$dir" ;; esac; \
			csv_field "$$full_path" >> "$$TEMP_TABLE"; printf ',' >> "$$TEMP_TABLE"; \
			csv_field "$$count" >> "$$TEMP_TABLE"; printf '\n' >> "$$TEMP_TABLE"; \
		done < "$$TEMP_TARGETS"; \
		$(UI) table < "$$TEMP_TABLE" || exit 1; \
	else \
		$(UI) info "Scanning for directories to prune."; \
		while IFS= read -r -d '' dir; do \
			count=$$(find "$$dir" -type f -printf . 2>/dev/null | wc -c | tr -d '[:space:]'); \
			$(UI) info "  $$dir ($$count files)"; \
		done < "$$TEMP_TARGETS"; \
	fi; \
	if $(UI) confirm "Remove these directories?"; then \
		$(UI) info "Remove duplicate and delete directories."; \
		xargs -0 -r rm -rf -- < "$$TEMP_TARGETS" 2>/dev/null || true; \
		$(UI) info "Remove empty directories."; \
		REPO_ROOT="$(CURDIR)" $(BIN_DIR)/rename-fonts.sh --prune-empty force; \
		$(UI) info "Remove the rename list file."; \
		rm -f .font-renames.txt; \
		$(UI) success "Clean complete."; \
	else \
		$(UI) info "Clean cancelled."; \
	fi

.PHONY: fontconfig
fontconfig: | _check-gum
	@XDG_CONFIG_HOME="$(XDG_CONFIG_HOME)" XDG_DATA_HOME="$(XDG_DATA_HOME)" $(BIN_DIR)/gen-fontconfig.sh
	@$(UI) info "Update the font cache."
	@fc-cache -f "$(INSTALL_FONTS_DIR)" 2>/dev/null || true
	@$(UI) success "Fontconfig update complete."

.PHONY: install
install: | _check-gum
	@$(UI) info "Install fonts to $(INSTALL_FONTS_DIR)."
	@install -d "$(INSTALL_FONTS_DIR)"
	@cp -r "$(FONTS_DIR)"/* "$(INSTALL_FONTS_DIR)/"
	@$(UI) success "Fonts installed."
	@$(MAKE) --no-print-directory fontconfig

.PHONY: uninstall
uninstall: | _check-gum
	@$(UI) info "Uninstall fonts from $(INSTALL_FONTS_DIR)."
	@if [ -d "$(INSTALL_FONTS_DIR)" ]; then \
		$(UI) info "Font families to remove:"; \
		ls -1 "$(INSTALL_FONTS_DIR)" 2>/dev/null | head -20 | while IFS= read -r family; do $(UI) info "  $$family"; done; \
		count=$$(ls -1 "$(INSTALL_FONTS_DIR)" 2>/dev/null | wc -l); \
		if [ $$count -gt 20 ]; then $(UI) info "... and $$((count - 20)) more"; fi; \
		if $(UI) confirm "Remove all fonts from $(INSTALL_FONTS_DIR)?"; then \
			rm -rf "$(INSTALL_FONTS_DIR)"; \
			$(UI) info "Update the font cache."; \
			fc-cache -f 2>/dev/null || true; \
			$(UI) success "Uninstall complete."; \
		else \
			$(UI) info "Uninstall cancelled."; \
		fi; \
	else \
		$(UI) info "No fonts found at $(INSTALL_FONTS_DIR)."; \
	fi

_release-%: | _check-gum
	@$(UI) info "Prepare release ($(*))."
	@# Check for unstaged changes
	@if ! git diff-index --quiet HEAD --; then \
		$(UI) error "Commit or stash your changes before you create a release."; \
		git status --short; \
		exit 1; \
	fi
	@$(UI) info "Determine the next version."
	@# Try to use svu, install if not available
	@if command -v svu >/dev/null 2>&1; then \
		NEXT_VERSION=$$(svu $(*) --tag-mode current-branch 2>/dev/null || svu $(*) 2>/dev/null || echo "v0.1.0"); \
	else \
		$(UI) info "svu is not installed. Install it with Go."; \
		NEXT_VERSION=$$(go run github.com/caarlos0/svu@latest $(*) --tag-mode current-branch 2>/dev/null || go run github.com/caarlos0/svu@latest $(*) 2>/dev/null || echo "v0.1.0"); \
	fi; \
	$(UI) info "Next version: $$NEXT_VERSION"; \
	ARCHIVE_NAME="fonts-$$NEXT_VERSION.zip"; \
	$(UI) info "Create the release archive."; \
	git archive -o "$$ARCHIVE_NAME" --prefix=fonts/ HEAD; \
	$(UI) info "Created archive: $$ARCHIVE_NAME"; \
	$(UI) info "Publish the release on GitHub."; \
	gh release create "$$NEXT_VERSION" "$$ARCHIVE_NAME" \
		--generate-notes \
		--title "$$NEXT_VERSION"; \
	$(UI) success "Release complete. Version: $$NEXT_VERSION. Archive: $$ARCHIVE_NAME."

.PHONY: release-minor
release-minor: _release-minor | _check-gum
.PHONY: release-major
release-major: _release-major | _check-gum
.PHONY: release-patch
release-patch: _release-patch | _check-gum

.PHONY: release-amend
release-amend: | _check-gum
	@$(UI) info "Amend the latest release."
	@# Check for unstaged changes
	@if ! git diff-index --quiet HEAD --; then \
		$(UI) error "Commit or stash your changes before you amend the release."; \
		git status --short; \
		exit 1; \
	fi
	@# Get latest tag
	LATEST_TAG=$$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.1.0"); \
	$(UI) info "Latest tag: $$LATEST_TAG"; \
	ARCHIVE_NAME="fonts-$$LATEST_TAG-amend.zip"; \
	$(UI) info "Create the release archive."; \
	git archive -o "$$ARCHIVE_NAME" --prefix=fonts/ HEAD; \
	$(UI) info "Created archive: $$ARCHIVE_NAME"; \
	$(UI) info "Amend the release on GitHub."; \
	gh release upload "$$LATEST_TAG" "$$ARCHIVE_NAME" --clobber; \
	$(UI) success "Amend complete. Tag: $$LATEST_TAG. Archive: $$ARCHIVE_NAME."
