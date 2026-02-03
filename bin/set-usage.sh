#!/usr/bin/env bash
#
# Modify font usage restrictions by setting fsType bits 0-3 to 0.
#
# This allows embedding/editing/installing for private use.
# Uses fonttools ttx to extract OS/2 table, modify fsType, and merge back.
#
# Usage: set-usage.sh [options]
#
# Options:
#   --repo-root PATH    Override the repository root (defaults to script dir)
#   --jobs NUM          Number of parallel jobs (default: CPU cores)
#   --dry-run           Show what would be modified without making changes
#   --verbose           Enable verbose logging
#   --help, -h          Show this help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(dirname "$SCRIPT_DIR")}"
FONTS_DIR="${FONTS_DIR:-$REPO_ROOT/share/fonts}"
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 4)}"
DRY_RUN=false
VERBOSE=false

# Map color names to terminfo setaf/setab codes
declare -A colors=(
  [black]=0
  [red]=1
  [green]=2
  [yellow]=3
  [blue]=4
  [magenta]=5
  [cyan]=6
  [white]=7
)

nocolor() { printf "%s%s" "$(tput op 2>/dev/null || true)" "${1:-}"; }
color() { printf "%s%s%s" "$(tput setaf "${colors[${1}]:-7}" 2>/dev/null || true)" "${2:-}" "$(nocolor)"; }

log_info() {
  printf '[%s] %s\n' "$(nocolor INFO)" "${1}"
}

log_verbose() {
  if [[ ${VERBOSE} == "true" ]]; then
    printf '[%s] %s\n' "$(color cyan DBUG)" "${1}"
  fi
}

log_warn() {
  printf '[%s] %s\n' "$(color yellow WARN)" "${1}" >&2
}

log_error() {
  printf '[%s] %s\n' "$(color red FAIL)" "${1}" >&2
}

usage() {
  cat <<'EOF'
Usage: set-usage.sh [options]

Modifies font usage restrictions by setting the OS/2 table fsType field
bits 0-3 to value 0, which allows embedding, editing, and installation
for private use.

Options:
  --repo-root PATH    Override the repository root (defaults to script dir)
  --jobs NUM          Number of parallel jobs (default: CPU cores)
  --dry-run           Show what would be modified without making changes
  --verbose           Enable verbose logging
  --help, -h          Show this help message
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="$2"
      shift 2
      ;;
    --jobs)
      PARALLEL_JOBS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$FONTS_DIR" ]]; then
  log_error "Fonts directory not found: $FONTS_DIR"
  exit 1
fi

# Check for fonttools
if ! command -v fonttools &>/dev/null; then
  log_error "fonttools is required but was not found in PATH"
  log_error "Install with: pip install fonttools"
  exit 1
fi

relative_path() {
  local path="$1"
  if [[ $path == "$REPO_ROOT" ]]; then
    echo "."
  elif [[ $path == "$REPO_ROOT"/* ]]; then
    echo "${path#$REPO_ROOT/}"
  else
    echo "$path"
  fi
}

# Function to process a single font file
# Arguments: font_file dry_run
# Output: STATUS|INFO|PATH
process_font() {
  local font_file="$1"
  local dry_run="$2"

  # Create a unique temp file for this font
  local ttx_file
  ttx_file=$(mktemp --suffix=.ttx)

  # Extract OS/2 table to TTX
  if ! fonttools ttx -t "OS/2" -o "$ttx_file" "$font_file" 2>/dev/null; then
    rm -f "$ttx_file"
    echo "SKIP|NO_OS2|$font_file"
    return 0
  fi

  # Check if ttx file was created
  if [[ ! -f "$ttx_file" ]]; then
    echo "SKIP|NO_TTX|$font_file"
    return 0
  fi

  # Read current fsType value - fonttools outputs it as binary string like "00000000 00000100"
  local current_fstype_raw
  current_fstype_raw=$(grep 'fsType value=' "$ttx_file" 2>/dev/null | sed 's/.*fsType value="\([^"]*\)".*/\1/' || echo "")

  if [[ -z "$current_fstype_raw" ]]; then
    rm -f "$ttx_file"
    echo "SKIP|NO_FSTYPE|$font_file"
    return 0
  fi

  # Convert binary string to decimal (remove spaces)
  local binary_str="${current_fstype_raw// /}"
  local current_fstype=$((2#$binary_str))

  # Calculate new fsType: clear bits 0-3 (mask 0xFFF0) to allow all usage
  # Bits 0-3 control embedding restrictions, setting them to 0 = Installable Embedding
  local new_fstype=$((current_fstype & 0xFFF0))

  if [[ "$current_fstype" -eq "$new_fstype" ]]; then
    rm -f "$ttx_file"
    echo "UNCHANGED|$current_fstype|$font_file"
    return 0
  fi

  if [[ "$dry_run" == "true" ]]; then
    rm -f "$ttx_file"
    echo "WOULD_MODIFY|$current_fstype->$new_fstype|$font_file"
    return 0
  fi

  # Convert new fsType to binary string format matching fonttools output
  # Format: "XXXXXXXX XXXXXXXX" (16 bits, space-separated)
  local new_binary
  new_binary=$(printf "%016d" "$(echo "obase=2; $new_fstype" | bc)")
  local new_fstype_str="${new_binary:0:8} ${new_binary:8:8}"

  # Modify the fsType value in the TTX file
  sed -i "s/fsType value=\"$current_fstype_raw\"/fsType value=\"$new_fstype_str\"/" "$ttx_file"

  # Merge the modified TTX back into the font
  if fonttools ttx -m "$font_file" -o "$font_file" "$ttx_file" 2>/dev/null; then
    rm -f "$ttx_file"
    echo "MODIFIED|$current_fstype->$new_fstype|$font_file"
  else
    rm -f "$ttx_file"
    echo "FAIL|MERGE|$font_file"
  fi
}

export -f process_font

log_verbose "Using $PARALLEL_JOBS parallel jobs"
log_verbose "Dry-run mode: $DRY_RUN"

# Find all font files
mapfile -t FONT_FILES < <(find "$FONTS_DIR" -type f \( -iname "*.otf" -o -iname "*.ttf" \) | sort)

if [[ ${#FONT_FILES[@]} -eq 0 ]]; then
  log_info "No font files found"
  exit 0
fi

echo "Processing ${#FONT_FILES[@]} font files..."

# Create temp file for results
RESULTS_FILE=$(mktemp)
trap "rm -f '$RESULTS_FILE'" EXIT

# Process fonts
JOBLOG_FILE=$(mktemp)
ERRORS_FILE=$(mktemp)

if command -v parallel &>/dev/null && parallel --version 2>/dev/null | grep -q "GNU parallel"; then
  log_verbose "Using GNU parallel for processing"
  printf '%s\n' "${FONT_FILES[@]}" | \
    parallel -j "$PARALLEL_JOBS" --bar --joblog "$JOBLOG_FILE" process_font {} "$DRY_RUN" > "$RESULTS_FILE" 2>"$ERRORS_FILE"
else
  log_verbose "Using sequential processing"
  for font_file in "${FONT_FILES[@]}"; do
    process_font "$font_file" "$DRY_RUN" >> "$RESULTS_FILE" 2>>"$ERRORS_FILE"
  done
fi

# Check for parallel job failures
PARALLEL_FAILED=0
if [[ -f "$JOBLOG_FILE" ]]; then
  PARALLEL_FAILED=$(awk 'NR>1 && $7!=0 {count++} END {print count+0}' "$JOBLOG_FILE")
fi

rm -f "$JOBLOG_FILE"

# Counters
declare -i modified=0 unchanged=0 skipped=0 failed=0

# Collect failed fonts for error diagnostics
declare -a FAILED_FONTS=()

# Process results
while IFS='|' read -r status info path; do
  [[ -z "$status" ]] && continue

  case "$status" in
    MODIFIED)
      ((++modified))
      log_verbose "Modified $(relative_path "$path"): fsType $info"
      ;;
    WOULD_MODIFY)
      ((++modified))
      log_verbose "Would modify $(relative_path "$path"): fsType $info"
      ;;
    UNCHANGED)
      ((++unchanged))
      log_verbose "Unchanged $(relative_path "$path"): fsType already $info"
      ;;
    SKIP)
      ((++skipped))
      log_verbose "Skipped $(relative_path "$path"): $info"
      ;;
    FAIL)
      ((++failed))
      FAILED_FONTS+=("$(relative_path "$path"): $info")
      ;;
  esac
done < "$RESULTS_FILE"

# Display error diagnostics if any failures occurred
if [[ $failed -gt 0 || $PARALLEL_FAILED -gt 0 ]]; then
  echo "" >&2
  echo "=== Error Diagnostics ===" >&2
  echo "Processing failures: $failed" >&2
  if [[ $PARALLEL_FAILED -gt 0 ]]; then
    echo "Parallel job failures: $PARALLEL_FAILED" >&2
  fi
  if [[ ${#FAILED_FONTS[@]} -gt 0 ]]; then
    echo "" >&2
    echo "Failed fonts:" >&2
    for font in "${FAILED_FONTS[@]}"; do
      echo "  - $font" >&2
    done
  fi
  if [[ -s "$ERRORS_FILE" ]]; then
    echo "" >&2
    echo "Additional errors:" >&2
    cat "$ERRORS_FILE" >&2
  fi
  echo "=========================" >&2
fi

rm -f "$ERRORS_FILE"

# Summary
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Done: $modified would be modified, $unchanged unchanged, $skipped skipped"
else
  echo "Done: $modified modified, $unchanged unchanged, $skipped skipped"
fi
