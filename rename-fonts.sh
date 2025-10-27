#!/usr/bin/env bash
#
# Organise font files according to FontConfig metadata.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$SCRIPT_DIR}"

DRY_RUN=false
PRUNE_EMPTY=false
PRUNE_MODE="force"
VERBOSE=false

usage() {
  cat <<'EOF'
Usage: rename_fonts.sh [options]

Organises all font files in the repository according to the
FontConfig-driven layout described in .github/copilot-instructions.md.

Options:
  --repo-root PATH        Override the repository root (defaults to script dir)
  --dry-run               Show planned changes without applying them
  --prune-empty [MODE]    Remove now-empty directories after moves
                            MODE can be either one of the following:
                              - force    # remove all directories (default)
                              - confirm  # interactively remove directories
  --verbose               Enable verbose logging (analysis and processing details)
                          Combine with --dry-run to review how every font would
                          be identified and renamed without applying any changes
  --help, -h              Show this cruft and exit
EOF
}

# Map color names to terminfo setaf/setab codes.
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

nocolor() { printf "%s%s" "$(tput op)" "${1:-}"; }
color() { printf "%s%s%s" "$(tput setaf "${colors[${1}]:-7}")" "${2:-}" "$(nocolor)"; }

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

sanitize_family() {
  local family="${1:-}"
  family="${family// /}"
  family=$(printf '%s' "$family" | sed 's/[^A-Za-z0-9-]//g')
  # Strip VF, Variable, or Var suffix from family names
  family="${family%VF}"
  family="${family%Variable}"
  family="${family%Var}"
  if [[ -z $family ]]; then
    family="UnknownFamily"
  fi
  printf '%s' "$family"
}

sanitize_style() {
  local style="${1:-}"
  style="${style// /}"
  style=$(printf '%s' "$style" | sed 's/[^A-Za-z0-9-]//g')
  if [[ -z $style ]]; then
    style="Regular"
  fi
  printf '%s' "$style"
}

unique_join() {
  if [[ $# -eq 0 ]]; then
    echo ""
    return
  fi
  local joined
  joined=$(printf '%s\n' "$@" | awk 'NF' | sort -u | paste -sd'+' -)
  printf '%s' "$joined"
}

resolve_destination() {
  local src="$1"
  local desired="$2"
  local dir name ext candidate

  dir=$(dirname "$desired")
  local filename
  filename=$(basename "$desired")
  if [[ $filename == *.* ]]; then
    name="${filename%.*}"
    ext=".${filename##*.}"
  else
    name="$filename"
    ext=""
  fi
  candidate="$desired"

  if [[ -e $candidate ]]; then
    local src_real dest_real
    if src_real=$(realpath "$src" 2>/dev/null) && dest_real=$(realpath "$candidate" 2>/dev/null); then
      if [[ $src_real == "$dest_real" ]]; then
        printf '%s' "$candidate"
        return
      fi
    fi
  fi

  local counter=1
  while [[ -e $candidate ]]; do
    candidate="$dir/${name}-${counter}${ext}"
    ((counter++))
  done

  printf '%s' "$candidate"
}

declare -i PLANNED_MOVES=0
declare -i EXECUTED_MOVES=0

perform_move() {
  local src="$1"
  local desired="$2"

  if [[ ! -e $src ]]; then
    log_warn "Source missing: $(relative_path "$src")"
    return
  fi

  local resolved
  resolved=$(resolve_destination "$src" "$desired")

  if [[ $src == "$resolved" ]]; then
    return
  fi

  if [[ $resolved != "$desired" ]]; then
    log_warn "Destination conflict for $(relative_path "$desired"); using $(relative_path "$resolved")"
  fi

  # Must use pre-increment so that this line evaluates to non-zero
  # to prevent exiting when shell option -e (errexit) is set.
  ((++PLANNED_MOVES))

  if [[ $DRY_RUN == "true" ]]; then
    log_info "Would move $(relative_path "$src") -> $(relative_path "$resolved")"
  else
    mkdir -p "$(dirname "$resolved")"
    mv "$src" "$resolved"
    log_info "Moved $(relative_path "$src") -> $(relative_path "$resolved")"
    ((++EXECUTED_MOVES))
  fi
}

prune_empty_directories() {
  log_info "Pruning empty directories under $(relative_path "$REPO_ROOT")"

  # Store empty directories in an array to avoid read conflicts
  local empty_dirs=()
  while IFS= read -r dir; do
    empty_dirs+=("$dir")
  done < <(find "$REPO_ROOT" -mindepth 1 -type d -empty -not -path "$REPO_ROOT/.git/*" | sort -r)

  if [[ ${#empty_dirs[@]} -eq 0 ]]; then
    log_verbose "No empty directories found"
    return
  fi

  log_verbose "Found ${#empty_dirs[@]} empty directories to process"

  if [[ $DRY_RUN == "true" ]]; then
    for dir in "${empty_dirs[@]}"; do
      log_info "Would remove $(relative_path "$dir")"
    done
  else
    for dir in "${empty_dirs[@]}"; do
      if [[ $PRUNE_MODE == "confirm" ]]; then
        while true; do
          printf 'Remove %s? [Y/n/q] ' "$(relative_path "$dir")" >&2
          read -r response
          # Default to yes if empty
          if [[ -z $response ]]; then
            response="y"
          fi
          # Convert to lowercase
          response="${response,,}"

          # Check for unambiguous match
          case "$response" in
          y | ye | yes)
            log_info "Removing $(relative_path "$dir")"
            rmdir "$dir"
            break
            ;;
          n | no)
            log_info "Skipping $(relative_path "$dir")"
            break
            ;;
          q | qu | qui | quit)
            log_info "Quit requested; stopping prune operation"
            return
            ;;
          *)
            printf 'Unrecognized input "%s". Please enter [Y]es, [n]o, or [q]uit.\n' "$response" >&2
            ;;
          esac
        done
      else
        log_info "Removing $(relative_path "$dir")"
        rmdir "$dir"
      fi
    done
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --repo-root)
    shift
    if [[ $# -eq 0 ]]; then
      log_error "--repo-root requires a path"
      exit 1
    fi
    REPO_ROOT="$(realpath "$1")"
    ;;
  --dry-run)
    DRY_RUN=true
    ;;
  --verbose)
    VERBOSE=true
    ;;
  --prune-empty)
    PRUNE_EMPTY=true
    shift
    # Check if next argument is a mode (not starting with --)
    if [[ $# -gt 0 && $1 != --* ]]; then
      case "$1" in
      force | confirm)
        PRUNE_MODE="$1"
        ;;
      *)
        log_error "Invalid --prune-empty mode: $1 (expected 'force' or 'confirm')"
        exit 1
        ;;
      esac
    else
      # No mode specified, default to force and don't consume next arg
      PRUNE_MODE="force"
      continue
    fi
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    log_error "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

if [[ ! -d $REPO_ROOT ]]; then
  log_error "Repository root not found: $REPO_ROOT"
  exit 1
fi

if ! command -v fc-query >/dev/null 2>&1; then
  log_error "fc-query is required but was not found in PATH"
  exit 1
fi

declare -a FILE_PATHS=()
declare -a FAMILY_CLEAN=()
declare -a FAMILY_RAW=()
declare -a STYLE_CLEAN=()
declare -a FORMAT=()
declare -a IS_VARIABLE=()

declare -A GROUP_INDICES=()
declare -A FAMILY_SEEN=()

mapfile -t FONT_FILES < <(find "$REPO_ROOT" -type f \( -iname '*.otf' -o -iname '*.ttf' \) -not -path "$REPO_ROOT/.git/*" | sort)

if [[ ${#FONT_FILES[@]} -eq 0 ]]; then
  log_info "No font files found under $(relative_path "$REPO_ROOT")"
  exit 0
fi

log_verbose "Found ${#FONT_FILES[@]} font files to analyze"

for font_file in "${FONT_FILES[@]}"; do
  log_verbose "Analyzing: $(relative_path "$font_file")"

  metadata=$(fc-query --format '%{family[0]}\n%{style[0]}\n%{variable}\n' "$font_file" 2>/dev/null || true)
  if [[ -z $metadata ]]; then
    log_warn "Skipping (fc-query failed): $(relative_path "$font_file")"
    continue
  fi

  {
    read -r family
    read -r style
    read -r variable
  } <<<"$metadata"

  log_verbose "  Raw metadata: family='$family', style='$style', variable='$variable'"

  if [[ -z $family ]]; then
    family=$(basename "$(dirname "$font_file")")
    log_warn "Missing family metadata; using directory name '$family' for $(relative_path "$font_file")"
  fi

  if [[ -z $style ]]; then
    style="Regular"
    log_verbose "  Empty style, defaulting to 'Regular'"
  fi

  local_format="${font_file##*.}"
  local_format="${local_format,,}"
  if [[ $local_format != "otf" && $local_format != "ttf" ]]; then
    log_warn "Unsupported font extension in $(relative_path "$font_file")"
    continue
  fi

  local_is_var="false"
  # Check if ANY instance in the font has variable: True
  if fc-query --brief "$font_file" 2>/dev/null | grep -q "variable: True"; then
    local_is_var="true"
    log_verbose "  Detected as VARIABLE font (has at least one variable instance)"
  else
    log_verbose "  Detected as STATIC font"
  fi

  family_clean=$(sanitize_family "$family")
  style_clean=$(sanitize_style "$style")

  log_verbose "  Sanitized: family_clean='$family_clean', style_clean='$style_clean'"

  idx=${#FILE_PATHS[@]}
  FILE_PATHS+=("$font_file")
  FAMILY_CLEAN+=("$family_clean")
  FAMILY_RAW+=("$family")
  STYLE_CLEAN+=("$style_clean")
  FORMAT+=("$local_format")
  IS_VARIABLE+=("$local_is_var")

  key="$family_clean|$local_format"
  if [[ -n ${GROUP_INDICES[$key]:-} ]]; then
    GROUP_INDICES[$key]="${GROUP_INDICES[$key]} $idx"
  else
    GROUP_INDICES[$key]="$idx"
  fi

  if [[ -z ${FAMILY_SEEN[$family_clean]:-} ]]; then
    FAMILY_SEEN[$family_clean]="$family"
  fi

done

if [[ ${#FILE_PATHS[@]} -eq 0 ]]; then
  log_info "No usable font files found under $(relative_path "$REPO_ROOT")"
  exit 0
fi

log_verbose "Analysis complete: ${#FILE_PATHS[@]} usable font files grouped into ${#GROUP_INDICES[@]} family/format combinations"

mapfile -t GROUP_KEYS < <(printf '%s\n' "${!GROUP_INDICES[@]}" | sort)

for key in "${GROUP_KEYS[@]}"; do
  IFS='|' read -r family_clean format <<<"$key"
  read -ra indices <<<"${GROUP_INDICES[$key]}"

  family_raw="${FAMILY_RAW[${indices[0]}]}"
  dest_format_dir="$REPO_ROOT/$family_clean/$format"

  log_info "Processing family '$family_raw' as '$family_clean' [$format]"
  log_verbose "  Group has ${#indices[@]} font file(s)"

  static_indices=()
  variable_indices=()

  for idx in "${indices[@]}"; do
    if [[ ${IS_VARIABLE[$idx]} == "true" ]]; then
      variable_indices+=("$idx")
      log_verbose "    Variable: $(relative_path "${FILE_PATHS[$idx]}")"
    else
      static_indices+=("$idx")
      log_verbose "    Static: $(relative_path "${FILE_PATHS[$idx]}")"
    fi
  done

  log_verbose "  Summary: ${#static_indices[@]} static, ${#variable_indices[@]} variable"

  static_styles=()
  for idx in "${static_indices[@]}"; do
    static_styles+=("${STYLE_CLEAN[$idx]}")
  done

  static_summary=$(unique_join "${static_styles[@]}")

  if [[ ${#variable_indices[@]} -gt 0 ]]; then
    if [[ ${#static_indices[@]} -gt 0 ]]; then
      log_info "  Variable font present; parking ${#static_indices[@]} static fonts into .duplicate/"
      log_verbose "  Static fonts will be moved to .duplicate/ because variable fonts exist"
      for idx in "${static_indices[@]}"; do
        style_clean="${STYLE_CLEAN[$idx]}"
        dest_path="$dest_format_dir/.duplicate/$style_clean/${family_clean}-${style_clean}.${format}"
        perform_move "${FILE_PATHS[$idx]}" "$dest_path"
      done
    fi

    # For variable fonts: check for duplicates and group by checksum
    # Deduplicate by MD5 hash
    log_verbose "  Deduplicating variable fonts by MD5 checksum..."
    unset var_checksums var_unique_indices
    declare -A var_checksums
    declare -a var_unique_indices

    for idx in "${variable_indices[@]}"; do
      checksum=$(md5sum "${FILE_PATHS[$idx]}" 2>/dev/null | awk '{print $1}')
      if [[ -z ${var_checksums[$checksum]:-} ]]; then
        var_checksums[$checksum]="$idx"
        var_unique_indices+=("$idx")
        log_verbose "    Unique: $(relative_path "${FILE_PATHS[$idx]}") [checksum: ${checksum:0:8}...]"
      else
        log_verbose "    Duplicate: $(relative_path "${FILE_PATHS[$idx]}") (same as index ${var_checksums[$checksum]})"
      fi
    done

    log_info "  Found ${#var_unique_indices[@]} unique variable font(s) (${#variable_indices[@]} total files)"

    # If there's only one unique variable font, name it simply
    if [[ ${#var_unique_indices[@]} -eq 1 ]]; then
      log_verbose "  Single variable font - using simple naming: <Family>-Variable.<format>"
      for idx in "${var_unique_indices[@]}"; do
        dest_path="$dest_format_dir/${family_clean}-Variable.${format}"
        perform_move "${FILE_PATHS[$idx]}" "$dest_path"
      done
    else
      # Multiple unique variable fonts - use style to differentiate
      log_verbose "  Multiple variable fonts - differentiating by style (Italic vs Upright)"
      for idx in "${var_unique_indices[@]}"; do
        style_clean="${STYLE_CLEAN[$idx]}"
        # Determine if this is an italic or upright variable font
        if [[ $style_clean == *"Italic"* ]]; then
          dest_path="$dest_format_dir/${family_clean}-VariableItalic.${format}"
          log_verbose "    Italic variable: $(relative_path "${FILE_PATHS[$idx]}") -> $(relative_path "$dest_path")"
        else
          dest_path="$dest_format_dir/${family_clean}-Variable.${format}"
          log_verbose "    Upright variable: $(relative_path "${FILE_PATHS[$idx]}") -> $(relative_path "$dest_path")"
        fi
        perform_move "${FILE_PATHS[$idx]}" "$dest_path"
      done
    fi
  else
    log_verbose "  No variable fonts - processing ${#static_indices[@]} static fonts normally"
    for idx in "${static_indices[@]}"; do
      style_clean="${STYLE_CLEAN[$idx]}"
      dest_path="$dest_format_dir/$style_clean/${family_clean}-${style_clean}.${format}"
      perform_move "${FILE_PATHS[$idx]}" "$dest_path"
    done
  fi

done

if [[ $PRUNE_EMPTY == "true" ]]; then
  log_verbose "Prune empty directories mode: $PRUNE_MODE"
  prune_empty_directories
fi

total_families=${#FAMILY_SEEN[@]}
log_info "Processed ${#FILE_PATHS[@]} font files across $total_families families"
log_verbose "Repository root: $(realpath "$REPO_ROOT")"
log_verbose "Dry-run mode: $DRY_RUN"
log_verbose "Verbose mode: $VERBOSE"
if [[ $DRY_RUN == "true" ]]; then
  log_info "Planned moves: $PLANNED_MOVES (dry run)"
else
  log_info "Executed moves: $EXECUTED_MOVES"
fi

exit 0
