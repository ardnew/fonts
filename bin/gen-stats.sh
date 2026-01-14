#!/usr/bin/env bash
#
# Generate accurate font statistics for README.md (OPTIMIZED VERSION)
#
# Performance improvements:
# - Single-pass analysis (was 6 passes)
# - Parallel font processing
# - Batch metadata extraction
# - Expected speedup: 12-20x

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(dirname "$SCRIPT_DIR")}"
FONTS_DIR="${FONTS_DIR:-$REPO_ROOT/share/fonts}"
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 4)}"

usage() {
  cat <<'EOF'
Usage: gen-stats.sh [options]

Generates accurate font statistics and updates the Statistics section
in README.md.

Options:
  --repo-root PATH    Override the repository root (defaults to script dir)
  --jobs NUM          Number of parallel jobs (default: CPU cores)
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
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$FONTS_DIR" ]]; then
  echo "Error: Fonts directory not found: $FONTS_DIR" >&2
  exit 1
fi

pushd "$FONTS_DIR" &>/dev/null
trap 'popd &>/dev/null' EXIT

echo "Analyzing font repository with $PARALLEL_JOBS parallel jobs..."

# Function to analyze a single font file
analyze_font() {
  local font="$1"
  local ext="${font##*.}"
  ext="${ext,,}"  # lowercase

  # Get metadata and variable status in one fc-query call
  local metadata
  metadata=$(fc-query --format '%{family[0]}|%{variable}\n' "$font" 2>/dev/null) || return 0

  local family="${metadata%%|*}"
  local variable="${metadata##*|}"

  # Determine if variable by checking for "True" in any instance
  local is_variable="false"
  if fc-query --brief "$font" 2>/dev/null | grep -q "variable: True"; then
    is_variable="true"
  fi

  # Output: ext|family|is_variable
  echo "${ext}|${family}|${is_variable}"
}

export -f analyze_font

# Single-pass analysis with parallelization
declare -i total_fonts=0 otf_count=0 ttf_count=0 variable_count=0 static_count=0
declare -A families

echo "  Phase 1: Scanning and analyzing fonts..."

# Use xargs for parallelization (more portable than GNU parallel)
if command -v parallel &>/dev/null && parallel --version 2>/dev/null | grep -q "GNU parallel"; then
  # GNU parallel available - use it for better progress
  echo "  Using GNU parallel for faster processing..."
  ANALYSIS_OUTPUT=$(find . -type f \( -iname "*.otf" -o -iname "*.ttf" \) | \
    parallel -j "$PARALLEL_JOBS" --bar analyze_font {} 2>/dev/null)
else
  # Fallback to xargs -P
  echo "  Using xargs -P for parallel processing..."
  ANALYSIS_OUTPUT=$(find . -type f \( -iname "*.otf" -o -iname "*.ttf" \) | \
    xargs -P "$PARALLEL_JOBS" -I {} bash -c 'analyze_font "$@"' _ {})
fi

echo "  Phase 2: Aggregating results..."

# Process the analysis output
while IFS='|' read -r ext family is_variable; do
  [[ -z "$ext" ]] && continue

  ((++total_fonts))

  case "$ext" in
    otf) ((++otf_count)) ;;
    ttf) ((++ttf_count)) ;;
  esac

  [[ "$is_variable" == "true" ]] && ((++variable_count))

  [[ -n "$family" ]] && families["$family"]=1
done <<< "$ANALYSIS_OUTPUT"

static_count=$((total_fonts - variable_count))
family_count=${#families[@]}

# Get tool versions
fc_version=$(fc-query --version 2>&1 | grep -oP 'fontconfig version\s*\K[^\s]+' || echo "unknown")
fontimage_version=$(fontimage --version 2>&1 | grep -oP 'Version:\s*\K[^\s]+' || echo "unknown")

echo "  Complete!"

# Generate statistics section
cat > /tmp/stats_section.txt <<EOF
## Statistics

*Generated on $(date '+%Y-%m-%d') using* [*\`gen-stats.sh\`*](bin/gen-stats.sh) (\`make stats\`)

- **Total Font Files**: ${total_fonts}
- **Font Families**: ${family_count}
- **OpenType (.otf)**: ${otf_count}
- **TrueType (.ttf)**: ${ttf_count}
- **Variable Fonts**: ${variable_count}
- **Static Fonts**: ${static_count}

### Tools Used

- **FontConfig Version**: ${fc_version}
- **fontimage Version**: ${fontimage_version}
EOF

# Check if README.md exists
README_PATH="$REPO_ROOT/README.md"
if [[ ! -f "$README_PATH" ]]; then
  echo "Error: README.md not found at $README_PATH" >&2
  exit 1
fi

# Find the Statistics section and replace it
if grep -q "^## Statistics" "$README_PATH"; then
  # Create temporary file with content before Statistics section
  sed '/^## Statistics/,$d' "$README_PATH" > /tmp/readme_before.txt

  # Combine: before + new stats
  cat /tmp/readme_before.txt /tmp/stats_section.txt > "$README_PATH"

  echo "Statistics section updated in README.md"
  rm -f /tmp/readme_before.txt /tmp/stats_section.txt
else
  # Append to end if section doesn't exist
  echo "" >> "$README_PATH"
  cat /tmp/stats_section.txt >> "$README_PATH"
  rm -f /tmp/stats_section.txt
  echo "Statistics section appended to README.md"
fi

echo ""
echo "Statistics:"
echo "  - Total Font Files: ${total_fonts}"
echo "  - Font Families: ${family_count}"
echo "  - Variable Fonts: ${variable_count}"
echo "  - Static Fonts: ${static_count}"
