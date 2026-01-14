# fonts
### Essential fonts

A personal collection of approximately ~1,500 font files across ~150 font families, organized according to FontConfig conventions.

[**View complete preview gallery →**](share/doc/fonts/README.md)

---

## Repository Organization

Fonts are organized by family, format, and style according to FontConfig conventions:

```text
./
├── share/
│   ├── fonts/                           # Font files directory
│   │   └── <FamilyName>/                # One directory per font family
│   │       ├── otf/                     # OpenType format fonts
│   │       │   ├── <Style>/             # Static font style subdirectory
│   │       │   │   └── <Family>-<Style>.otf
│   │       │   └── .duplicate/          # Deprecated static fonts (when variable exists)
│   │       └── ttf/                     # TrueType format fonts
│   │           ├── <Style>/             # Static font style subdirectory
│   │           │   └── <Family>-<Style>.ttf
│   │           ├── <Family>-Variable.ttf        # Variable font (upright)
│   │           └── <Family>-VariableItalic.ttf  # Variable font (italic)
│   └── doc/
│       └── fonts/                       # Preview images and catalog
│           ├── *.png                    # Individual font preview images
│           └── README.md                # Preview gallery with all images
│
├── bin/              # Maintenance scripts
│   ├── gen-previews.sh   # Preview generation tool
│   ├── gen-stats.sh      # Repository statistics tool
│   └── rename-fonts.sh   # Font organization tool
│
└── Makefile          # Build and maintenance automation
```

### Organizing Fonts

The [*`rename-fonts.sh`*](bin/rename-fonts.sh) script discovers, analyzes, and organizes all font files according to FontConfig metadata.

Use the Makefile for convenient access:

```bash
# Preview changes before applying
make dryrun

# Apply font organization
make normal

# Clean up duplicate and temporary directories
make clean
```

#### Direct Script Usage

```bash
# Preview changes with detailed output
./bin/rename-fonts.sh --dry-run --verbose

# Apply changes and clean up empty directories
./bin/rename-fonts.sh --prune-empty force

# Interactive cleanup
./bin/rename-fonts.sh --prune-empty confirm
```

The font organization tool:

- Walks the `share/fonts/` directory to find `*.otf` and `*.ttf` files
- Uses `fc-query` to extract authoritative font metadata (ignores misleading filenames)
- Sanitizes family and style names (removes spaces, special characters, variable suffixes)
- Groups fonts by family and format
- Detects variable vs static fonts automatically
- Handles duplicate detection via MD5 checksums
- Moves static fonts to `.duplicate/` subdirectories when variable fonts exist
- Can prune empty directories after reorganization

## Font Previews

[**View complete preview gallery →**](share/doc/fonts/README.md)

Each font style includes sample images showing uppercase and lowercase alphabets, digits, and common symbols.

### Generating Previews

Preview images are generated using the [*`gen-previews.sh`*](bin/gen-previews.sh) script:

```bash
# Generate previews with default settings
make previews

# Or call the script directly with custom dimensions
./bin/gen-previews.sh --width 1000 --pixelsize 28
```

The preview generation tool:

- Uses FontForge's `fontimage` to create PNG previews
- Displays safe character sets to avoid missing glyph placeholders
- Handles both static and variable fonts
- Queries font metadata using FontConfig's `fc-query`
- Generates a complete markdown catalog with embedded images

---

## Using the Makefile

The repository includes a Makefile for convenient management:

```bash
# Show all available targets
make help

# Font organization
make normal      # Organize fonts using FontConfig metadata
make dryrun      # Preview changes without applying
make clean       # Remove .duplicate/.delete directories (with confirmation)

# Previews and statistics
make previews    # Generate font preview images
make stats       # Generate repository statistics

# Installation
make install             # Install fonts to /usr/local/share/fonts
make install PREFIX=/usr # Install to /usr/share/fonts
make uninstall           # Uninstall fonts (with confirmation)

# Release management
make release     # Create and publish a new release
```

### Installation

Install fonts to your system using the Makefile:

```bash
# Install to default location (/usr/local/share/fonts)
sudo make install

# Install to custom location
sudo make install PREFIX=/usr

# Update font cache
fc-cache -f
```

The install target will:
- Copy all font families to `$PREFIX/share/fonts`
- Automatically update the font cache
- Make fonts available system-wide

To uninstall:

```bash
sudo make uninstall
```

---

## Statistics

*Generated on 2026-01-13 using* [*`gen-stats.sh`*](bin/gen-stats.sh) (`make stats`)

- **Total Font Files**: 1538
- **Font Families**: 167
- **OpenType (.otf)**: 920
- **TrueType (.ttf)**: 618
- **Variable Fonts**: 46
- **Static Fonts**: 1492

### Tools Used

- **FontConfig Version**: 2.17.1
- **fontimage Version**: 20251009
