#!/usr/bin/env bash
#
# Generate preview images of all font files
#
# Usage: ./gen-previews.sh [options]
#
# Options:
#   --width NUM      Set preview image width in pixels (default: 800)
#   --pixelsize NUM  Set font size in pixels (default: 24)
#   --help, -h       Show this help message
#
# Output:
#   - Preview images: share/doc/fonts/*.png
#   - Preview catalog: share/doc/fonts/README.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$SCRIPT_DIR}"

# Configuration
PREVIEW_WIDTH=800
PIXEL_SIZE=24

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --width)
      PREVIEW_WIDTH="$2"
      shift 2
      ;;
    --pixelsize)
      PIXEL_SIZE="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run with --help for usage information" >&2
      exit 1
      ;;
  esac
done

fontimage=$( type -P fontimage )
fcquery=$( type -P fc-query )

# Output paths
pp="${REPO_ROOT}/share/doc/fonts"
pm="${pp}/README.md"

# Clean and recreate output directory
rm -rf "${pp}"
mkdir -pv "${pp}"

# Initialize README
cat > "${pm}" << 'EOF'
# Font Preview Gallery

This document contains preview images for all fonts in the repository.

Preview images are generated using FontForge's `fontimage` tool, displaying uppercase and lowercase alphabets, digits, and common symbols for each font style.

---

EOF

shopt -s globstar extglob nullglob

# Counter for progress
count=0
total=$(find "${REPO_ROOT}" -type f \( -name "*.otf" -o -name "*.ttf" \) | wc -l)

echo "Generating previews for ${total} font files..."

for ff in "${REPO_ROOT}"/**/*.[ot]tf; do 
  # Skip if file doesn't exist (nullglob didn't work)
  [[ -f "${ff}" ]] || continue

  ((++count))

  # Generate safe filename from path
  fp=${ff#"${REPO_ROOT}"/}
  fs=${fp//\//__}
  fs=${fs%.[ot]tf}

  # Determine display name
  if [[ ${fs} == *Variable* ]]; then
    # Check if it's actually a variable font
    if fc-query --brief "${ff}" 2>/dev/null | grep -q "variable: True"; then
      fn=$( "${fcquery}" -i 0 -f '%{family[0]} (Variable)' "${ff}" 2>/dev/null || echo "Unknown Font" )
    else
      fn=$( "${fcquery}" -i 0 -f '%{fullname[0]}' "${ff}" 2>/dev/null || echo "Unknown Font" )
    fi
  else
    fn=$( "${fcquery}" -i 0 -f '%{fullname[0]}' "${ff}" 2>/dev/null || echo "Unknown Font" )
  fi

  output_file="${pp}/${fs}.png"

  # Check for CFF2 format (unsupported by fontimage)
  # CFF2 is used by variable OpenType fonts and cannot be processed by FontForge/fontimage
  if [[ ${ff} == *.otf ]] && strings -n 4 "${ff}" 2>/dev/null | grep -q "CFF2"; then
    echo "  Skipping CFF2 variable font (unsupported by fontimage): ${fp}" >&2
    continue
  fi

  # Generate preview with explicit dimensions and safe character set
  # Use only ASCII alphanumerics and common punctuation to avoid missing glyph boxes
  if "${fontimage}" \
      --width "${PREVIEW_WIDTH}" \
      --pixelsize "${PIXEL_SIZE}" \
      --text "ABCDEFGHIJKLMNOPQRSTUVWXYZ" \
      --text "abcdefghijklmnopqrstuvwxyz" \
      --text "0123456789" \
      --text "!@#$%^&*()_+-=[]{}|;:',.<>?/" \
      --text "oO08 iIlL1 g9qCGQ 8%& <([{}])> .,;: -_=" \
      --text "<= >= == === != !== /= >>= <<= ||= |= // /// \\\\ =~ !~" \
      -o "${output_file}" \
      "${ff}" &>/dev/null; then

    # Add to README with relative path
    printf '## %s\n![%s](%s)\n\n' "${fn}" "${fn}" "${fs}.png" >> "${pm}"

    # Progress indicator
    if (( count % 50 == 0 )); then
      echo "  Processed ${count}/${total} fonts..."
    fi
  else
    # Log failures but continue
    echo "  Warning: Failed to generate preview for: ${fp}" >&2
  fi
done

echo "Preview generation complete!"
echo "  Output directory: ${pp}"
echo "  Preview catalog: ${pm}"
echo "  Total images: $(find "${pp}" -name "*.png" | wc -l)"
