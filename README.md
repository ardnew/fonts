# fonts
##### Essential fonts

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
├── gen-previews.sh   # Preview generation tool
├── gen-stats.sh      # Repository statistics tool
└── rename-fonts.sh   # Font organization tool
```

### Organizing Fonts

The [*`rename-fonts.sh`*](rename-fonts.sh) script discovers, analyzes, and organizes all font files according to FontConfig metadata:

```bash
# Preview changes before applying
./rename-fonts.sh --dry-run --verbose

# Apply changes and clean up empty directories
./rename-fonts.sh --prune-empty force

# Interactive cleanup
./rename-fonts.sh --prune-empty confirm
```

#### Usage

```text
./rename-fonts.sh [options]

Options:
  --repo-root PATH        Override repository root (default: script directory)
  --dry-run               Preview changes without applying
  --verbose               Show detailed analysis and processing
  --prune-empty [MODE]    Remove empty directories (force|confirm)
  --help, -h              Show usage information
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

Preview images are generated using the [*`gen-previews.sh`*](gen-previews.sh) script:

```bash
# Generate previews with default settings
./gen-previews.sh

# Generate previews with custom dimensions
./gen-previews.sh --width 1000 --pixelsize 28
```

#### Usage

```text
./gen-previews.sh [options]

Options:
  --width NUM      Set preview image width in pixels (default: 800)
  --pixelsize NUM  Set font size in pixels (default: 24)
  --help, -h       Show this help message
```

The preview generation tool:

- Uses FontForge's `fontimage` to create PNG previews
- Displays safe character sets to avoid missing glyph placeholders
- Handles both static and variable fonts
- Queries font metadata using FontConfig's `fc-query`
- Generates a complete markdown catalog with embedded images

---

## Statistics

*Generated on 2025-12-13 using* [*`gen-stats.sh`*](gen-stats.sh)

- **Total Font Files**: 1529
- **Font Families**: 164
- **OpenType (.otf)**: 920
- **TrueType (.ttf)**: 609
- **Variable Fonts**: 43
- **Static Fonts**: 1486

### Tools Used

- **FontConfig Version**: 2.17.1
- **fontimage Version**: 20251009
