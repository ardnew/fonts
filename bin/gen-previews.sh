#!/usr/bin/env bash
#
# Generate preview images of all font files
#
# Usage: ./gen-previews.sh [options]
#
# Options:
#   --width NUM      Set preview image width in pixels (default: 800)
#   --pixelsize NUM  Set font size in pixels (default: 24)
#   --staged, -s     Only process font files staged for commit
#   --untracked, -u  Only process untracked font files
#   --help, -h       Show this help message
#
# Output:
#   - Preview images: share/doc/fonts/*.png
#   - Preview catalog: share/doc/fonts/README.md

set -euo pipefail

SCRIPT_DIR=$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )
REPO_ROOT=$( dirname "${SCRIPT_DIR}" )
FONTS_DIR=${FONTS_DIR:-$REPO_ROOT/share/fonts}

# Configuration
PREVIEW_WIDTH=800
PIXEL_SIZE=24
GIT_FILTER=""

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
    --staged|-s)
      GIT_FILTER="staged"
      shift
      ;;
    --untracked|-u)
      GIT_FILTER="untracked"
      shift
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

# For git filter modes, preserve existing README and images
if [[ -n $GIT_FILTER ]]; then
  mkdir -pv "${pp}"
  # Initialize README if it doesn't exist
  if [[ ! -f "${pm}" ]]; then
    cat > "${pm}" << 'EOF'
# Font Preview Gallery

This document contains preview images for all fonts in the repository.

Preview images are generated using FontForge's `fontimage` tool, displaying uppercase and lowercase alphabets, digits, and common symbols for each font style.

---

EOF
  fi
else
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
fi

shopt -s globstar extglob nullglob

# Build list of font files based on git filter
if [[ $GIT_FILTER == "staged" ]]; then
  echo "Processing staged font files..."
  mapfile -t FONT_FILES < <(
    git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR | \
    grep -iE '\.(otf|ttf)$' | \
    sed "s|^|$REPO_ROOT/|"
  )
elif [[ $GIT_FILTER == "untracked" ]]; then
  echo "Processing untracked font files..."
  mapfile -t FONT_FILES < <(
    git -C "$REPO_ROOT" ls-files --others --exclude-standard | \
    grep -iE '\.(otf|ttf)$' | \
    sed "s|^|$REPO_ROOT/|"
  )
else
  mapfile -t FONT_FILES < <(find "${FONTS_DIR}" -type f \( -name "*.otf" -o -name "*.ttf" \))
fi

# Counter for progress
count=0
total=${#FONT_FILES[@]}

echo "Generating previews for ${total} font files..."

# Array to store preview entries for sorting
declare -a PREVIEW_ENTRIES=()

for ff in "${FONT_FILES[@]}"; do 
  # Skip if file doesn't exist
  [[ -f "${ff}" ]] || continue

  ((++count))

  # Generate safe filename from path
  fp=${ff#"${FONTS_DIR}"/}
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

    # Store preview entry for sorting
    PREVIEW_ENTRIES+=("${fn}||${fs}.png")

    # Progress indicator
    if (( count % 50 == 0 )); then
      echo "  Processed ${count}/${total} fonts..."
    fi
  else
    # Log failures but continue
    echo "  Warning: Failed to generate preview for: ${fp}" >&2
  fi
done

# Sort and write preview entries to README
if [[ -n $GIT_FILTER ]]; then
  # In git filter mode, merge new entries with existing ones
  # Extract existing entries from README (skip header)
  if [[ -f "${pm}" ]]; then
    while IFS= read -r line; do
      if [[ $line == "## "* ]]; then
        # Extract font name from heading
        font_name="${line#\#\# }"
        # Read next line which should be the image
        read -r img_line
        if [[ $img_line == "!["*"]("*")" ]]; then
          # Extract image filename
          img_file="${img_line##*\(}"
          img_file="${img_file%\)}"
          PREVIEW_ENTRIES+=("${font_name}||${img_file}")
        fi
      fi
    done < "${pm}"
  fi
  
  # Remove duplicates and sort
  mapfile -t SORTED_ENTRIES < <(printf '%s\n' "${PREVIEW_ENTRIES[@]}" | sort -u -t'|' -k1,1)
  
  # Rewrite README with sorted entries
  cat > "${pm}" << 'EOF'
# Font Preview Gallery

This document contains preview images for all fonts in the repository.

Preview images are generated using FontForge's `fontimage` tool, displaying uppercase and lowercase alphabets, digits, and common symbols for each font style.

---

EOF
  
  for entry in "${SORTED_ENTRIES[@]}"; do
    IFS='||' read -r font_name img_file <<< "$entry"
    printf '## %s\n![%s](%s)\n\n' "${font_name}" "${font_name}" "${img_file}" >> "${pm}"
  done
else
  # Normal mode: just sort and write all entries
  mapfile -t SORTED_ENTRIES < <(printf '%s\n' "${PREVIEW_ENTRIES[@]}" | sort -t'|' -k1,1)
  
  for entry in "${SORTED_ENTRIES[@]}"; do
    IFS='||' read -r font_name img_file <<< "$entry"
    printf '## %s\n![%s](%s)\n\n' "${font_name}" "${font_name}" "${img_file}" >> "${pm}"
  done
fi

echo "Preview generation complete!"
echo "  Output directory: ${pp}"
echo "  Preview catalog: ${pm}"
echo "  Total images: $(find "${pp}" -name "*.png" | wc -l)"
