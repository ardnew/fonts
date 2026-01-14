# Font Repository Makefile

# Variables
PREFIX ?= $(HOME)/.local
FONTS_DIR = share/fonts
BIN_DIR = bin
INSTALL_FONTS_DIR = $(PREFIX)/$(FONTS_DIR)

# Helper function to find duplicate/delete directories
define find_prune_targets
	@echo "==> Scanning for directories to prune..."
	@find $(FONTS_DIR) -type d \( -name ".duplicate" -o -name ".delete" \) 2>/dev/null | while read dir; do \
		count=$$(find "$$dir" -type f 2>/dev/null | wc -l); \
		echo "  $$dir ($$count files)"; \
	done
	@echo ""
endef

.PHONY: help
help:
	@echo "Font Repository Management"
	@echo ""
	@echo "Available targets:"
	@echo "  make help        - Show this help message"
	@echo ""
	@echo "Font Organization:"
	@echo "  make normal              - Organize fonts using FontConfig metadata"
	@echo "  make normal-staged       - Organize only staged font files"
	@echo "  make normal-untracked    - Organize only untracked font files"
	@echo "  make dryrun              - Preview font organization changes (dry-run mode)"
	@echo "  make dryrun-staged       - Preview staged font organization"
	@echo "  make dryrun-untracked    - Preview untracked font organization"
	@echo "  make clean               - Remove .duplicate/.delete directories (with confirmation)"
	@echo ""
	@echo "Single File Processing:"
	@echo "  Process individual font files with custom destinations:"
	@echo "    $(BIN_DIR)/rename-fonts.sh --file /path/to/font.ttf:share/fonts"
	@echo "  The font will be organized under share/fonts/<Family>/<format>/..."
	@echo ""
	@echo "Font Previews & Stats:"
	@echo "  make previews            - Generate font preview images and catalog"
	@echo "  make previews-staged     - Generate previews for staged font files"
	@echo "  make previews-untracked  - Generate previews for untracked font files"
	@echo "  make stats               - Generate repository statistics"
	@echo ""
	@echo "Installation:"
	@echo "  make install     - Install fonts to PREFIX (default: $(PREFIX))"
	@echo "  make uninstall   - Uninstall fonts from PREFIX"
	@echo ""
	@echo "Release Management:"
	@echo "  make release     - Create and publish a new release"
	@echo ""
	@echo "Environment variables:"
	@echo "  PREFIX=$(PREFIX)"

.PHONY: previews
previews:
	@echo "==> Generating font previews..."
	$(BIN_DIR)/gen-previews.sh

.PHONY: previews-staged
previews-staged:
	@echo "==> Generating previews for staged fonts..."
	$(BIN_DIR)/gen-previews.sh --staged

.PHONY: previews-untracked
previews-untracked:
	@echo "==> Generating previews for untracked fonts..."
	$(BIN_DIR)/gen-previews.sh --untracked

.PHONY: stats
stats:
	@echo "==> Generating repository statistics..."
	$(BIN_DIR)/gen-stats.sh

.PHONY: normal
normal:
	@echo "==> Organizing fonts..."
	$(BIN_DIR)/rename-fonts.sh

.PHONY: normal-staged
normal-staged:
	@echo "==> Organizing staged fonts..."
	$(BIN_DIR)/rename-fonts.sh --staged

.PHONY: normal-untracked
normal-untracked:
	@echo "==> Organizing untracked fonts..."
	$(BIN_DIR)/rename-fonts.sh --untracked

.PHONY: dryrun
dryrun:
	@echo "==> Running font organization in dry-run mode..."
	$(BIN_DIR)/rename-fonts.sh --dry-run --verbose

.PHONY: dryrun-staged
dryrun-staged:
	@echo "==> Previewing staged font organization..."
	$(BIN_DIR)/rename-fonts.sh --staged --dry-run --verbose

.PHONY: dryrun-untracked
dryrun-untracked:
	@echo "==> Previewing untracked font organization..."
	$(BIN_DIR)/rename-fonts.sh --untracked --dry-run --verbose

.PHONY: clean
clean:
	$(call find_prune_targets)
	@echo "Do you want to delete these directories? [y/N] " && read answer && \
	if [ "$$answer" = "y" ] || [ "$$answer" = "Y" ]; then \
		echo "==> Pruning duplicate and delete directories..."; \
		find $(FONTS_DIR) -type d \( -name ".duplicate" -o -name ".delete" \) -exec rm -rf {} + 2>/dev/null || true; \
		echo "==> Removing empty directories..."; \
		REPO_ROOT=$(CURDIR) $(BIN_DIR)/rename-fonts.sh --prune-empty force; \
		echo "==> Removing rename list file..."; \
		rm -f .font-renames.txt; \
		echo "==> Clean complete!"; \
	else \
		echo "==> Clean cancelled."; \
	fi

.PHONY: install
install:
	@echo "==> Installing fonts to $(INSTALL_FONTS_DIR)..."
	@install -d $(INSTALL_FONTS_DIR)
	@cp -r $(FONTS_DIR)/* $(INSTALL_FONTS_DIR)/
	@echo "==> Updating font cache..."
	@fc-cache -f $(INSTALL_FONTS_DIR) 2>/dev/null || true
	@echo "==> Installation complete!"
	@echo "    Fonts installed to: $(INSTALL_FONTS_DIR)"

.PHONY: uninstall
uninstall:
	@echo "==> Uninstalling fonts from $(INSTALL_FONTS_DIR)..."
	@if [ -d "$(INSTALL_FONTS_DIR)" ]; then \
		echo "The following font families will be removed:"; \
		ls -1 $(INSTALL_FONTS_DIR) 2>/dev/null | head -20; \
		count=$$(ls -1 $(INSTALL_FONTS_DIR) 2>/dev/null | wc -l); \
		if [ $$count -gt 20 ]; then echo "... and $$((count - 20)) more"; fi; \
		echo ""; \
		echo "Remove all fonts from $(INSTALL_FONTS_DIR)? [y/N] " && read answer && \
		if [ "$$answer" = "y" ] || [ "$$answer" = "Y" ]; then \
			rm -rf $(INSTALL_FONTS_DIR); \
			echo "==> Updating font cache..."; \
			fc-cache -f 2>/dev/null || true; \
			echo "==> Uninstall complete!"; \
		else \
			echo "==> Uninstall cancelled."; \
		fi; \
	else \
		echo "No fonts found at $(INSTALL_FONTS_DIR)"; \
	fi

.PHONY: release
release:
	@echo "==> Preparing new release..."
	@# Check for unstaged changes
	@if ! git diff-index --quiet HEAD --; then \
		echo "Error: You have unstaged changes. Please commit or stash them first."; \
		git status --short; \
		exit 1; \
	fi
	@echo "==> Determining next version..."
	@# Try to use svu, install if not available
	@if command -v svu >/dev/null 2>&1; then \
		NEXT_VERSION=$$(svu next --tag-mode current-branch 2>/dev/null || svu next 2>/dev/null || echo "v0.1.0"); \
	else \
		echo "    svu not found, installing..."; \
		NEXT_VERSION=$$(go run github.com/caarlos0/svu@latest next --tag-mode current-branch 2>/dev/null || go run github.com/caarlos0/svu@latest next 2>/dev/null || echo "v0.1.0"); \
	fi; \
	echo "    Next version: $$NEXT_VERSION"; \
	echo ""; \
	echo "==> Creating release archive..."; \
	ARCHIVE_NAME="fonts-$$NEXT_VERSION.zip"; \
	git archive -o "$$ARCHIVE_NAME" --prefix=fonts/ HEAD; \
	echo "    Created: $$ARCHIVE_NAME"; \
	echo ""; \
	echo "==> Publishing to GitHub..."; \
	gh release create "$$NEXT_VERSION" "$$ARCHIVE_NAME" \
		--generate-notes \
		--title "$$NEXT_VERSION"; \
	echo ""; \
	echo "==> Release complete!"; \
	echo "    Version: $$NEXT_VERSION"; \
	echo "    Archive: $$ARCHIVE_NAME"
