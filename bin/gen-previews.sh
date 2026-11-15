#!/usr/bin/env bash
#
# Generate preview images of all font files (OPTIMIZED VERSION)
#
# Performance improvements:
# - Parallel processing (8+ jobs simultaneously)
# - Batch metadata extraction
# - Pre-filtered CFF2 detection
# - Better progress tracking
# - Expected speedup: 6-10x
#
# Usage: ./gen-previews.sh [options]
#
# Options:
#   --width NUM      Set preview image width in pixels (default: 800)
#   --pixelsize NUM  Set font size in pixels (default: 24)
#   --jobs NUM       Number of parallel jobs (default: CPU cores)
#   --help, -h       Show this help message
#
# Output:
#   - Preview images: share/doc/fonts/*.png
#   - Preview catalog: share/doc/fonts/README.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"
ui_require_gum || exit 1
REPO_ROOT="${REPO_ROOT:-$(dirname "$SCRIPT_DIR")}"
FONTS_DIR="${FONTS_DIR:-$REPO_ROOT/share/fonts}"

# Configuration
PREVIEW_WIDTH=800
PIXEL_SIZE=24
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 4)}"

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
  --jobs)
    PARALLEL_JOBS="$2"
    shift 2
    ;;
  --help | -h)
    ui_heading "$(sed -n '2,/^$/p' "$0" | sed 's/^# \?//')"
    exit 0
    ;;
  *)
    ui_error "Unknown option: $1. Run with --help for usage."
    exit 1
    ;;
  esac
done

fontimage=$(type -P fontimage)
fcquery=$(type -P fc-query)

# Output paths
pp="${REPO_ROOT}/share/doc/fonts"
pm="${pp}/README.md"

# Clean and recreate output directory
ui_info "Create preview output directory: ${pp}."
rm -rf "${pp}"
mkdir -p "${pp}"

# Initialize README
cat >"${pm}" <<'EOF'
# Font Preview Gallery

This document contains preview images for all fonts in the repository.

Preview images are generated using FontForge's `fontimage` tool, displaying uppercase and lowercase alphabets, digits, and common symbols for each font style.

---

EOF

shopt -s globstar extglob nullglob

# Get total count
total=$(find "${FONTS_DIR}" -type f \( -name "*.otf" -o -name "*.ttf" \) | wc -l)
ui_info "Generate previews for ${total} font files."

# Phase 1: Pre-scan for CFF2 fonts (unsupported by fontimage)
CFF2_FONTS_FILE=$(mktemp)
if [[ -n $(find "${FONTS_DIR}" -name "*.otf" -print -quit) ]]; then
  find "${FONTS_DIR}" -name "*.otf" -exec grep -l "CFF2" {} \; 2>/dev/null >"$CFF2_FONTS_FILE" || true
fi

# Phase 2: Generate previews in parallel

# Create temporary directory for font entries
ENTRIES_DIR=$(mktemp -d)

# Function to process a single font
process_font() {
  local ff="$1"
  local pp="$2"
  local PREVIEW_WIDTH="$3"
  local PIXEL_SIZE="$4"
  local ENTRIES_DIR="$5"

  # Generate safe filename from path
  local fp="${ff#"${FONTS_DIR}"/}"
  local fs="${fp//\//__}"
  fs="${fs%.[ot]tf}"

  # Compute font name (can't use cached data in parallel)
  local fn
  if [[ ${fs} == *Variable* ]] && fc-query --brief "${ff}" 2>/dev/null | grep -q "variable: True"; then
    fn=$(fc-query -i 0 -f '%{family[0]} (Variable)' "${ff}" 2>/dev/null || echo "Unknown Font")
  else
    fn=$(fc-query -i 0 -f '%{fullname[0]}' "${ff}" 2>/dev/null || echo "Unknown Font")
  fi

  local output_file="${pp}/${fs}.png"

  # Check if CFF2 (skip)
  if grep -qxF "$ff" "$CFF2_FONTS_FILE" 2>/dev/null; then
    echo "SKIP|CFF2|${fp}" >&2
    return 0
  fi

  # Generate preview with explicit dimensions and safe character set
  if fontimage \
    --width "${PREVIEW_WIDTH}" \
    --pixelsize "${PIXEL_SIZE}" \
    --text "ABCDEFGHIJKLMNOPQRSTUVWXYZ" \
    --text "abcdefghijklmnopqrstuvwxyz" \
    --text "0123456789" \
    --text "!@#$%^&*()_+-=[]{}|;:',.<>?/" \
    --text "oO08 iIlL1 g9qCGQ 8%& <([{}])> .,;: -_=" \
    --text '<= >= == === != !== /= >>= <<= ||= |= // /// \\ =~ !~' \
    -o "${output_file}" \
    "${ff}" &>/dev/null; then
    # Write entry data to individual file for later sorting
    # Format: fontname|imagefile|fontpath
    echo "${fn}|${fs}.png|${fp}" >"${ENTRIES_DIR}/${fs}.entry"
    echo "SUCCESS|${fp}" >&2
  else
    # Log failures
    echo "FAIL|${fp}" >&2
    return 1
  fi
}

export -f process_font
export FONTS_DIR pp PREVIEW_WIDTH PIXEL_SIZE CFF2_FONTS_FILE ENTRIES_DIR

# Process fonts in parallel
JOBLOG_FILE=$(mktemp)
ERRORS_FILE=$(mktemp)

run_preview_jobs() {
  if [[ -t 1 && -t 2 && ${TERM-} != dumb && -z ${NO_COLOR-} ]]; then
    gum spin --show-stdout --show-stderr --title "Generate previews." -- \
      bash -c 'errors=$1; shift; exec "$@" 2>"$errors"' _ "$ERRORS_FILE" "$@"
  else
    "$@" 2>"$ERRORS_FILE"
  fi
}

if command -v parallel &>/dev/null && parallel --version 2>/dev/null | grep -q "GNU parallel"; then
  # GNU parallel with job logging for error tracking
  find "${FONTS_DIR}" -type f \( -name "*.otf" -o -name "*.ttf" \) |
    run_preview_jobs parallel -j "$PARALLEL_JOBS" --joblog "$JOBLOG_FILE" \
      process_font {} "$pp" "$PREVIEW_WIDTH" "$PIXEL_SIZE" "$ENTRIES_DIR" || {
    status=$?
    ui_error "Preview generation failed."
    cat "$ERRORS_FILE" >&2
    rm -f "$JOBLOG_FILE" "$ERRORS_FILE"
    exit "$status"
  }
else
  # Fallback to xargs -P
  find "${FONTS_DIR}" -type f \( -name "*.otf" -o -name "*.ttf" \) |
    run_preview_jobs xargs -P "$PARALLEL_JOBS" -I {} bash -c "process_font '{}' '$pp' '$PREVIEW_WIDTH' '$PIXEL_SIZE' '$ENTRIES_DIR'" || {
    status=$?
    ui_error "Preview generation failed."
    cat "$ERRORS_FILE" >&2
    rm -f "$JOBLOG_FILE" "$ERRORS_FILE"
    exit "$status"
  }
fi

# Display error diagnostics if any failures occurred
FAILED_COUNT=0
if [[ -f $JOBLOG_FILE ]]; then
  FAILED_COUNT=$(awk 'NR>1 && $7!=0 {count++} END {print count+0}' "$JOBLOG_FILE")
fi

if [[ $FAILED_COUNT -gt 0 ]]; then
  ui_error "Failed to generate previews for $FAILED_COUNT jobs."
  if [[ -s $ERRORS_FILE ]]; then
    failed_paths=$(grep -E "^FAIL\|" "$ERRORS_FILE" |
      while IFS='|' read -r _ path; do printf '  - %s\n' "$path"; done || true)
    if [[ -n $failed_paths ]]; then
      ui_error "Failed fonts:
$failed_paths"
    fi
  fi
fi

rm -f "$JOBLOG_FILE" "$ERRORS_FILE"

# Phase 3: Generate README with table of contents

# Read all entries and sort alphabetically by font name
declare -a entries
while IFS='|' read -r fontname imgfile fontpath; do
  entries+=("${fontname}|${imgfile}|${fontpath}")
done < <(cat "${ENTRIES_DIR}"/*.entry 2>/dev/null | sort -t'|' -k1,1)

# Generate table of contents
echo "" >>"${pm}"
echo "## Table of Contents" >>"${pm}"
echo "" >>"${pm}"

for entry in "${entries[@]}"; do
  IFS='|' read -r fontname imgfile fontpath <<<"$entry"
  # Create anchor from font name (lowercase, replace spaces with hyphens)
  anchor=$(echo "$fontname" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -d '()')
  # Create download link to font file
  fontfile_link="${fontpath}"
  echo "- [${fontname}](#${anchor}) [💾](../../fonts/${fontfile_link})" >>"${pm}"
done

echo "" >>"${pm}"
echo "---" >>"${pm}"
echo "" >>"${pm}"

# Generate font preview sections
for entry in "${entries[@]}"; do
  IFS='|' read -r fontname imgfile fontpath <<<"$entry"
  anchor=$(echo "$fontname" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -d '()')
  fontfile_link="${fontpath}"
  echo "## ${fontname} [💾](../../fonts/${fontfile_link})" >>"${pm}"
  echo "![${fontname}](${imgfile})" >>"${pm}"
  echo "" >>"${pm}"
done

# Cleanup temporary directory
rm -rf "$ENTRIES_DIR"

# Summary
image_count=$(find "${pp}" -name "*.png" 2>/dev/null | wc -l)
if [[ $FAILED_COUNT -gt 0 ]]; then
  ui_error "Generated ${image_count} previews, but ${FAILED_COUNT} jobs failed."
elif [[ -t 1 ]]; then
  ui_success "Complete: ${image_count} previews. Output: ${pp}."
else
  ui_success "Generated ${image_count} preview images in ${pp}."
fi

# Cleanup temporary files
rm -f "$CFF2_FONTS_FILE"
