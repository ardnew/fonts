# fonts

A curated collection of **159 font families** (1,377 font files) organized for easy installation and browsing.

[**→ Browse font previews**](share/doc/fonts/README.md)

## Quick Start

Add any additional fonts anywhere under [`share/fonts/`](share/fonts/) and run:

```bash
# Validate everything is working
make smoke all

# Install fonts system-wide
sudo make install PREFIX=/usr
```

The included scripts will then automatically:

- locate, identify, and rename according to family/format/style,
- de-duplicate (with [variable font](https://en.wikipedia.org/wiki/Variable_font) support),
- clear all embedded usage restrictions, and
- generate [preview images](share/doc/fonts).

## Common Tasks

| Task | Command |
|------|---------|
| **Validate repository** | `make smoke` |
| **Preview font changes** | `make dryrun` |
| **Organize fonts** | `make normal` |
| **Remove usage restrictions** | `make usage` |
| **Generate previews** | `make previews` |
| **Update statistics** | `make stats` |
| **Install fonts** | `make install` |
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

> Generated 2026-02-05 • [view details](bin/gen-stats.sh)

- **Font Files:** 1,377
- **Families:** 159
- **Variable Fonts:** 37
- **Formats:** 919 OTF, 458 TTF

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
