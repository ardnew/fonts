#!/usr/bin/env bash
#
# Generate accurate font statistics for README.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$SCRIPT_DIR}"

usage() {
  cat <<'EOF'
Usage: gen-stats.sh [options]

Generates accurate font statistics and updates the Statistics section
in README.md.

Options:
  --repo-root PATH    Override the repository root (defaults to script dir)
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

pushd "$REPO_ROOT" &>/dev/null
trap 'popd &>/dev/null' EXIT

echo "Analyzing font repository..."

# Count total font files
total_fonts=$(find . -name "*.otf" -o -name "*.ttf" -o -name "*.OTF" -o -name "*.TTF" | wc -l)

# Count unique font families
families=$(find . \( -name "*.otf" -o -name "*.ttf" -o -name "*.OTF" -o -name "*.TTF" \) -exec fc-query -f '%{family[0]}\n' {} \; 2>/dev/null | sort -u | wc -l)

# Count OTF files
otf_count=$(find . -name "*.otf" -o -name "*.OTF" | wc -l)

# Count TTF files
ttf_count=$(find . -name "*.ttf" -o -name "*.TTF" | wc -l)

# Count variable fonts
variable_count=0
while IFS= read -r font; do
  if fc-query --brief "$font" 2>/dev/null | grep -q "variable: True"; then
    ((++variable_count))
  fi
done < <(find . \( -name "*.otf" -o -name "*.ttf" -o -name "*.OTF" -o -name "*.TTF" \))

# Count static fonts
static_count=$((total_fonts - variable_count))

# Get FontConfig version
fc_version=$(fc-query --version |& grep -oP 'fontconfig version\s*\K\S(\w|.(?!\s+$))+' || echo "unknown")

fontimage_version=$(fontimage --version |& grep -oP 'Version:\s*\K\S(\w|.(?!\s+$))+' || echo "unknown")

# Generate statistics section
cat > /tmp/stats_section.txt <<EOF
## Statistics

*Generated on $(date '+%Y-%m-%d') using* [*\`gen-stats.sh\`*](gen-stats.sh)

- **Total Font Files**: ${total_fonts}
- **Font Families**: ${families}
- **OpenType (.otf)**: ${otf_count}
- **TrueType (.ttf)**: ${ttf_count}
- **Variable Fonts**: ${variable_count}
- **Static Fonts**: ${static_count}

### Tools Used

- **FontConfig Version**: ${fc_version}
- **fontimage Version**: ${fontimage_version}
EOF

# Check if README.md exists
if [[ ! -f "README.md" ]]; then
  echo "Error: README.md not found in $REPO_ROOT" >&2
  exit 1
fi

# Find the Statistics section and replace it
if grep -q "^## Statistics" README.md; then
  # Create temporary file with content before Statistics section
  sed '/^## Statistics/,$d' README.md > /tmp/readme_before.txt

  # Combine: before + new stats
  cat /tmp/readme_before.txt /tmp/stats_section.txt > README.md

  echo "Statistics section updated in README.md"
  rm -f /tmp/readme_before.txt /tmp/stats_section.txt
else
  # Append to end if section doesn't exist
  echo "" >> README.md
  cat /tmp/stats_section.txt >> README.md
  rm -f /tmp/stats_section.txt
  echo "Statistics section appended to README.md"
fi

echo "Complete!"
echo ""
echo "Statistics:"
echo "  - Total Font Files: ${total_fonts}"
echo "  - Font Families: ${families}"
echo "  - Variable Fonts: ${variable_count}"
echo "  - Static Fonts: ${static_count}"
