#!/bin/bash
set -euo pipefail

# gen-fontconfig.sh - Generate fontconfig configuration files
# 
# This script generates fontconfig .conf files for each font family
# in the repository and sets up the proper fontconfig directory structure.
#
# Directory structure:
#   ${XDG_CONFIG_HOME}/fontconfig/fonts.conf      - Main user config
#   ${XDG_CONFIG_HOME}/fontconfig/conf.avail/     - Available configurations
#   ${XDG_CONFIG_HOME}/fontconfig/conf.d/         - Enabled configurations (symlinks)

# Configuration
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FONTS_DIR="${FONTS_DIR:-$REPO_ROOT/share/fonts}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

FONTCONFIG_DIR="$XDG_CONFIG_HOME/fontconfig"
CONF_AVAIL_DIR="$FONTCONFIG_DIR/conf.avail"
CONF_D_DIR="$FONTCONFIG_DIR/conf.d"
FONTS_CONF="$FONTCONFIG_DIR/fonts.conf"
INSTALL_FONTS_DIR="$XDG_DATA_HOME/fonts"

# Parse command line options
VERBOSE=0
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generate fontconfig configuration files for installed font families.

OPTIONS:
    --verbose           Enable verbose output
    --dry-run           Preview changes without modifying files
    --help, -h          Show this help message

ENVIRONMENT VARIABLES:
    XDG_CONFIG_HOME     Config directory (default: \$HOME/.config)
    XDG_DATA_HOME       Data directory (default: \$HOME/.local/share)
    FONTS_DIR           Source fonts directory (default: REPO_ROOT/share/fonts)
    REPO_ROOT           Repository root directory

DIRECTORY STRUCTURE:
    \${XDG_CONFIG_HOME}/fontconfig/fonts.conf      - Main user config
    \${XDG_CONFIG_HOME}/fontconfig/conf.avail/     - Available configurations
    \${XDG_CONFIG_HOME}/fontconfig/conf.d/         - Enabled configurations

EXAMPLES:
    # Generate fontconfig files
    $(basename "$0")

    # Preview changes
    $(basename "$0") --dry-run --verbose

    # Use custom directories
    XDG_CONFIG_HOME=~/.config $(basename "$0")

EOF
}

log() {
    echo "$@"
}

log_verbose() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo "$@"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Validate dependencies
if ! command -v fc-query &>/dev/null; then
    echo "Error: fc-query not found. Please install fontconfig." >&2
    exit 1
fi

if [[ ! -d "$FONTS_DIR" ]]; then
    echo "Error: Fonts directory not found: $FONTS_DIR" >&2
    exit 1
fi

# Create directory structure
create_dirs() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] Would create directories:"
        log "  - $FONTCONFIG_DIR"
        log "  - $CONF_AVAIL_DIR"
        log "  - $CONF_D_DIR"
    else
        log_verbose "Creating fontconfig directories..."
        mkdir -p "$FONTCONFIG_DIR"
        mkdir -p "$CONF_AVAIL_DIR"
        mkdir -p "$CONF_D_DIR"
    fi
}

# Generate main fonts.conf if it doesn't exist
generate_main_config() {
    if [[ -f "$FONTS_CONF" ]]; then
        log_verbose "Main config already exists: $FONTS_CONF"
        return
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] Would create: $FONTS_CONF"
        return
    fi

    log "Creating main fontconfig file: $FONTS_CONF"

    cat > "$FONTS_CONF" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <description>User font configuration</description>

  <!-- Load user-specific font directories -->
  <dir>~/.local/share/fonts</dir>

  <!-- Include enabled configurations from conf.d -->
  <include ignore_missing="yes">conf.d</include>

</fontconfig>
EOF
}

# Detect font classification (monospace, serif, or sans-serif)
detect_font_classification() {
    local sample_font="$1"
    local fc_family="$2"
    
    # Check spacing property (100 = monospace, 0 = proportional)
    local spacing
    spacing=$(fc-query -f '%{spacing}\n' "$sample_font" 2>/dev/null | head -1)
    
    if [[ "$spacing" == "100" ]]; then
        echo "monospace"
        return
    fi
    
    # If spacing not set, use heuristics based on family name
    local family_lower
    family_lower=$(echo "$fc_family" | tr '[:upper:]' '[:lower:]')
    
    # Check for monospace indicators in name
    if [[ "$family_lower" =~ (mono|code|console|terminal|typewriter|courier|fixed) ]]; then
        echo "monospace"
        return
    fi
    
    # Check for serif indicators in name
    if [[ "$family_lower" =~ serif ]]; then
        echo "serif"
        return
    fi
    
    # Default to sans-serif
    echo "sans-serif"
}

# Generate .conf file for a font family
generate_family_config() {
    local family_name="$1"
    local family_dir="$2"
    local conf_file="$CONF_AVAIL_DIR/60-${family_name}.conf"

    # Extract font metadata using fc-query
    local sample_font
    sample_font=$(find "$family_dir" -type f \( -name "*.otf" -o -name "*.ttf" \) -not -path "*/.duplicate/*" -not -path "*/.delete/*" | head -1)

    if [[ -z "$sample_font" ]]; then
        log_verbose "Warning: No valid fonts found in $family_dir"
        return 1
    fi

    # Get the canonical family name from fontconfig
    local fc_family
    fc_family=$(fc-query -f '%{family}\n' "$sample_font" 2>/dev/null | head -1 | cut -d',' -f1 || echo "$family_name")

    # Detect font classification
    local font_class
    font_class=$(detect_font_classification "$sample_font" "$fc_family")

    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] Would generate: $(basename "$conf_file")"
        log_verbose "            Family: $fc_family ($font_class)"
        return 0
    fi

    log_verbose "Generating config for: $fc_family ($font_class)"

    # Generate the .conf file
    cat > "$conf_file" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <description>Configuration for ${fc_family}</description>

  <!-- Font directory for ${fc_family} -->
  <dir>${INSTALL_FONTS_DIR}/${family_name}</dir>

  <!-- Accept ${fc_family} as a valid font family -->
  <alias>
    <family>${fc_family}</family>
    <default>
      <family>${font_class}</family>
    </default>
  </alias>

</fontconfig>
EOF

    return 0
}

# Enable a configuration by creating a symlink in conf.d
enable_config() {
    local conf_name="$1"
    local src="$CONF_AVAIL_DIR/$conf_name"
    local dst="$CONF_D_DIR/$conf_name"

    # In dry-run mode, skip file existence checks
    if [[ $DRY_RUN -eq 0 ]]; then
        if [[ ! -f "$src" ]]; then
            log_verbose "Warning: Config file not found: $src"
            return 1
        fi

        if [[ -L "$dst" ]] || [[ -f "$dst" ]]; then
            log_verbose "Already enabled: $conf_name"
            return 0
        fi
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] Would enable: $conf_name"
        return 0
    fi

    log_verbose "Enabling: $conf_name"
    ln -s "../conf.avail/$conf_name" "$dst"
}

# Main processing
main() {
    log "==> Generating fontconfig configuration"
    # Create directory structure
    create_dirs
    # Generate main config
    generate_main_config
    # Find all font families
    local families=()
    while IFS= read -r -d '' family_dir; do
        local family_name
        family_name=$(basename "$family_dir")
        families+=("$family_name")
    done < <(find "$FONTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    if [[ ${#families[@]} -eq 0 ]]; then
        echo "Warning: No font families found in $FONTS_DIR" >&2
        exit 0
    fi

    # Generate configs for each family
    local generated=0
    local enabled=0

    for family_name in "${families[@]}"; do
        local family_dir="$FONTS_DIR/$family_name"

        if generate_family_config "$family_name" "$family_dir"; then
            generated=$((generated + 1))

            # Enable the config
            if enable_config "60-${family_name}.conf"; then
                enabled=$((enabled + 1))
            fi
        fi
    done

    log "    ${generated} available configs: $CONF_AVAIL_DIR"
    log "    ${enabled} enabled configs: $CONF_D_DIR"
}

main "$@"
