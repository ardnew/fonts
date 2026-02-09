# fonts

This repository serves two personal use cases:

1. A curated library of **163 font families** (1,388 font files) organized for easy installation and browsing.
   - ### [Browse previews →](share/doc/fonts/README.md)
2. Tools for managing font file libraries, including: 
   - GNU Makefile to orchestrate all management operations with maximum concurrency
   - Supports self-testing to verify all required tools are available and functioning (smoke test)
   - Normalize file paths and names using a common, catalog-wide schema (dry-run capable)
   - De-duplicate _all_ fonts – across any combination of static font files and [variable font](https://en.wikipedia.org/wiki/Variable_font) embeddings (dry-run capable)
   - Stores duplicates with unique names in backup directories for manual confirmation and pruning
   - Clear all access restrictions (see field [`fsType`](https://learn.microsoft.com/en-us/typography/opentype/spec/os2#fstype) defined in the [OpenType metrics table (OS/2)](https://learn.microsoft.com/en-us/typography/opentype/spec/os2))
   - Generate exemplar preview images with groupings to compare frequently similar glyphs
   - Construct FontConfig standard files and directories for all fonts (symlink-based font enablement)
   - Automatically updates dynamic Markdown content including library statistics and preview gallery
   - Bump version, create Git tag, and publish release including a `.zip` distribution package

## Quick Start

Add any additional fonts anywhere under [`share/fonts/`](share/fonts/) and run:

```bash
# Validate everything is working
make smoke all

# Install fonts system-wide
sudo make install PREFIX=/usr
```

## Common Tasks

| [`Makefile`](Makefile) Target | Description |
|:-------:|:-----------|
| `help` | **Summarize available targets** |
| `smoke` | **Validate repository, required tools** |
| `all` | **Targets: `normal` `usage` `previews` `stats`** |
| `dryrun` | **Preview font changes** |
| `normal` | **Organize fonts** |
| `usage` | **Clear access/usage restrictions** |
| `previews` | **Generate preview images** |
| `stats` | **Update statistics** |
| `install` | **Install fonts** |
| `uninstall` | **Uninstall fonts** |
| `fontconfig` | **Generate FontConfig metadata** |
| `clean` | **Remove duplicates** (_with confirmation_) |
| `release` | **Version, tag, publish to GitHub** |

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

> Generated 2026-02-08 • [view details](bin/gen-stats.sh)

- **Font Files:** 1,388
- **Families:** 163
- **Variable Fonts:** 44
- **Formats:** 919 OTF, 469 TTF

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
- [`gen-fontconfig.sh`](bin/gen-fontconfig.sh) - Generate FontConfig config files and directories

**Requirements:** fontconfig, fontforge, fonttools, GNU parallel
