# fonts

A curated collection of **158 font families** (1,359 font files) organized for easy installation and browsing.

[**→ Browse font previews**](share/doc/fonts/README.md)

## Quick Start

```bash
# Validate everything is working
make smoke

# Install fonts system-wide
sudo make install

# View all available commands
make help
```

## Common Tasks

| Task | Command |
|------|---------|
| **Validate repository** | `make smoke` |
| **Preview font changes** | `make dryrun` |
| **Organize fonts** | `make normal` |
| **Generate previews** | `make previews` |
| **Update statistics** | `make stats` |
| **Install fonts** | `sudo make install` |
| **Remove duplicates** | `make clean` |

## Repository Structure

```
share/fonts/
└── FamilyName/
    ├── otf/                      # OpenType fonts
    │   ├── Style/                # Static fonts
    │   └── FamilyName-Variable.otf
    └── ttf/                      # TrueType fonts
        └── ...
```

Fonts are auto-organized by family and format using FontConfig metadata.

## Statistics

> Generated 2026-02-03 • [view details](bin/gen-stats.sh)

- **Font Files:** 1,359
- **Families:** 158
- **Variable Fonts:** 37
- **Formats:** 919 OTF, 440 TTF

## Installation

```bash
# Default location (~/.local/share/fonts)
make install

# System-wide (/usr/share/fonts)
sudo make install PREFIX=/usr
```

Fonts are automatically available after installation.

<details>
<summary><strong>Advanced Usage</strong></summary>

### Smoke Test
Validates font organization, checks prerequisites, and compares statistics:
```bash
make smoke
```

### Font Organization
```bash
# Preview changes with details
bin/rename-fonts.sh --dry-run --verbose

# Apply changes and remove empty directories
bin/rename-fonts.sh --prune-empty
```

### Preview Generation
```bash
# Custom dimensions
bin/gen-previews.sh --width 1000 --pixelsize 28
```

### Statistics
```bash
# Update README.md stats
make stats

# Compare without updating
bin/gen-stats.sh --compare
```

</details>

## Tools

All scripts include `--help` for detailed options:
- [`gen-previews.sh`](bin/gen-previews.sh) - Generate preview images
- [`gen-stats.sh`](bin/gen-stats.sh) - Calculate repository statistics
- [`rename-fonts.sh`](bin/rename-fonts.sh) - Organize fonts by metadata
- [`set-usage.sh`](bin/set-usage.sh) - Remove font usage restrictions

**Requirements:** fontconfig, fontforge, fonttools, GNU parallel
