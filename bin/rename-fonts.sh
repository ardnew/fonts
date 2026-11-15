#!/usr/bin/env bash
#
# Organise font files according to FontConfig metadata.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/ui.sh"
ui_require_gum || exit 1
REPO_ROOT=${REPO_ROOT:-$(dirname "${SCRIPT_DIR}")}
FONTS_DIR=${FONTS_DIR:-$REPO_ROOT/share/fonts}

DRY_RUN=false
PRUNE_EMPTY=false
PRUNE_MODE="force"
VERBOSE=false
TABLE_MODE=false
FILE_MODE=false
FILE_PATH=""
DEST_ROOT=""
RENAME_LIST_PATH=""
SCOPED_MODE=""
SPINNER_ENABLED=false
SPINNER_DIR=""
SPINNER_PID=""
declare -A MOVE_ELIGIBLE=()
declare -i SELECTED_COUNT=0
declare -i CONTEXT_ONLY_MOVE_COUNT=0

usage() {
  local help
  help=$(
    cat <<'EOF'
Usage: rename-fonts.sh [options]

Organize font files by FontConfig metadata.

Options:
--repo-root PATH        Set the repository root (default: script directory)
--file PATH:DEST        Process one font file and place it under DEST.
                        Example: --file /tmp/font.ttf:share/fonts
--staged                Organize staged .otf/.ttf files. Fail if they also
                        have unstaged changes.
--unstaged              Organize tracked .otf/.ttf files with unstaged changes
--untracked             Organize non-ignored, untracked .otf/.ttf files
--dry-run               Show planned moves. Do not move files.
--prune-empty [MODE]    Remove empty directories after moves.
                        MODE: force (default) or confirm
--rename-list PATH      Write rename operations to PATH.
                        Use "-" to print to stdout. Without this option, print
                        a short list or write a long list to a file.
--verbose               Show analysis and processing details.
                        Combine with --dry-run to review planned moves.
--help, -h              Show this help and exit
EOF
  )
  ui_heading "$help"
}

log_verbose() {
  if [[ ${VERBOSE} == "true" ]]; then
    ui_debug "$1"
  fi
}

log_info() {
  if [[ $TABLE_MODE != "true" ]]; then
    ui_info "$1"
  fi
}


start_spinner() {
  [[ $SPINNER_ENABLED == "true" && -z $SPINNER_PID ]] || return 0
  if ! SPINNER_DIR=$(mktemp -d); then
    SPINNER_DIR=""
    return 0
  fi
  gum spin --title "Analyze fonts and plan moves." -- \
    bash -c 'while [[ ! -e $1/stop ]]; do sleep 0.1; done' _ "$SPINNER_DIR" &
  SPINNER_PID=$!
}

stop_spinner() {
  if [[ -n $SPINNER_PID ]]; then
    : >"$SPINNER_DIR/stop" || kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  if [[ -n $SPINNER_DIR ]]; then
    rm -rf "$SPINNER_DIR" 2>/dev/null || true
  fi
  SPINNER_PID=""
  SPINNER_DIR=""
  trap - INT TERM
}

cleanup_spinner() {
  local status=$?
  stop_spinner
  return "$status"
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

normalize_family() {
  local family="${1:-}"
  local style="${2:-}"

  # If style is embedded in family name, strip it
  # e.g., "AudioLink Console Bold" with style "Bold" -> "AudioLink Console"
  if [[ -n $style && -n $family ]]; then
    # Create regex-safe version of style (escape special chars)
    local style_pattern="${style//[^[:alnum:]]/.}"
    # Check if family ends with the style (with optional space before it)
    if [[ $family =~ ^(.+)[[:space:]]+${style_pattern}$ ]]; then
      family="${BASH_REMATCH[1]}"
    fi
  fi

  printf '%s' "$family"
}

sanitize_family() {
  local family="${1:-}"
  family="${family// /}"             # Remove spaces
  family="${family//[^[:alnum:]-]/}" # Remove non-alphanumeric (except -)
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
  style="${style// /}"             # Remove spaces
  style="${style//[^[:alnum:]-]/}" # Remove non-alphanumeric (except -)
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
    ((++counter))
  done

  printf '%s' "$candidate"
}

declare -i PLANNED_MOVES=0
declare -i EXECUTED_MOVES=0
declare -a RENAME_SOURCES=()
declare -a RENAME_DESTS=()

perform_move() {
  local src="$1"
  local desired="$2"

  if [[ -n $SCOPED_MODE && -z ${MOVE_ELIGIBLE[$src]:-} ]]; then
    ((++CONTEXT_ONLY_MOVE_COUNT))
    log_verbose "Context only; leaving untouched: $(relative_path "$src")"
    return
  fi

  if [[ ! -e $src ]]; then
    stop_spinner
    ui_warn "Source missing: $(relative_path "$src")"
    return
  fi

  local resolved
  resolved=$(resolve_destination "$src" "$desired")

  if [[ $src == "$resolved" ]]; then
    return
  fi

  if [[ $resolved != "$desired" ]]; then
    stop_spinner
    ui_warn "Destination conflict for $(relative_path "$desired"); using $(relative_path "$resolved")"
  fi

  # Must use pre-increment so that this line evaluates to non-zero
  # to prevent exiting when shell option -e (errexit) is set.
  ((++PLANNED_MOVES))

  # Record this rename operation
  RENAME_SOURCES+=("$src")
  RENAME_DESTS+=("$resolved")

  if [[ $DRY_RUN == "true" ]]; then
    if [[ $TABLE_MODE != "true" ]]; then
      ui_info "Would move $(relative_path "$src") -> $(relative_path "$resolved")"
    fi
  else
    mkdir -p "$(dirname "$resolved")"
    mv "$src" "$resolved"
    ui_info "Moved $(relative_path "$src") -> $(relative_path "$resolved")"
    ((++EXECUTED_MOVES))
  fi
}

# Quote CSV cells so commas, quotes, and embedded newlines remain intact.

print_rename_table_csv() {
  printf '"Source","Destination"\n'
  local i source_path destination_path
  for i in "${!RENAME_SOURCES[@]}"; do
    source_path=${RENAME_SOURCES[$i]}
    destination_path=${RENAME_DESTS[$i]}
    if [[ $source_path == "$REPO_ROOT" ]]; then
      source_path="."
    elif [[ $source_path == "$REPO_ROOT"/* ]]; then
      source_path=${source_path#"$REPO_ROOT"/}
    fi
    if [[ $destination_path == "$REPO_ROOT" ]]; then
      destination_path="."
    elif [[ $destination_path == "$REPO_ROOT"/* ]]; then
      destination_path=${destination_path#"$REPO_ROOT"/}
    fi
    source_path=${source_path//\"/\"\"}
    destination_path=${destination_path//\"/\"\"}
    printf '"%s","%s"\n' "$source_path" "$destination_path"
  done
}

display_rename_list() {
  if [[ ${#RENAME_SOURCES[@]} -eq 0 ]]; then
    return
  fi
  if [[ $TABLE_MODE == "true" ]]; then
    print_rename_table_csv | ui_table
    return
  fi


  # Build the list content
  local list_lines=()
  for i in "${!RENAME_SOURCES[@]}"; do
    list_lines+=("$(relative_path "${RENAME_SOURCES[$i]}") -> $(relative_path "${RENAME_DESTS[$i]}")")
  done

  # If explicit path is provided
  if [[ -n $RENAME_LIST_PATH ]]; then
    if [[ $RENAME_LIST_PATH == "-" ]]; then
      # Always print to stdout
      ui_heading $'\n=== Rename Operations ==='
      printf '%s\n' "${list_lines[@]}"
    else
      # Write to file
      printf '%s\n' "${list_lines[@]}" >"$RENAME_LIST_PATH"
      ui_info "Rename operations written to: $RENAME_LIST_PATH"
    fi
    return
  fi

  # Auto mode: decide based on terminal size and list length
  local num_renames=${#RENAME_SOURCES[@]}
  local should_write_file=false

  # Check if stdout is a terminal
  if [[ ! -t 1 ]]; then
    should_write_file=true
  else
    # Get terminal height
    local term_height
    term_height=$(tput lines 2>/dev/null || echo 24)
    local max_lines=$((term_height / 2))

    if [[ $num_renames -gt $max_lines ]]; then
      should_write_file=true
    fi
  fi

  if [[ $should_write_file == "true" ]]; then
    # Write to a temporary file in the repo root
    local list_file="$REPO_ROOT/.font-renames.txt"
    printf '%s\n' "${list_lines[@]}" >"$list_file"
    ui_info "Rename operations written to: $(relative_path "$list_file")"
    ui_info "  ($num_renames operations - too many to display)"
  else
    # Print to stdout
    ui_heading $'\n=== Rename Operations ==='
    printf '%s\n' "${list_lines[@]}"
  fi
}

prune_empty_directories() {
  ui_info "Pruning empty directories under $(relative_path "$FONTS_DIR")"

  local empty_dirs=()
  local dir response choice
  while IFS= read -r dir; do
    empty_dirs+=("$dir")
  done < <(find "$FONTS_DIR" -mindepth 1 -type d -empty | sort -r)

  if [[ ${#empty_dirs[@]} -eq 0 ]]; then
    log_verbose "No empty directories found"
    return
  fi

  log_verbose "Found ${#empty_dirs[@]} empty directories to process"

  if [[ $DRY_RUN == "true" ]]; then
    for dir in "${empty_dirs[@]}"; do
      ui_info "Would remove $(relative_path "$dir")"
    done
  else
    for dir in "${empty_dirs[@]}"; do
      if [[ $PRUNE_MODE == "confirm" ]]; then
        if [[ -t 0 ]]; then
          if ! choice=$(ui_choose_prune "Remove $(relative_path "$dir")?"); then
            return
          fi
          case "$choice" in
          Remove)
            ui_info "Removing $(relative_path "$dir")"
            rmdir "$dir"
            ;;
          Skip)
            ui_info "Skipping $(relative_path "$dir")"
            ;;
          Quit)
            ui_info "Quit requested; stopping prune operation"
            return
            ;;
          *)
            return
            ;;
          esac
        else
          while true; do
            ui_info "Remove $(relative_path "$dir")? [Y/n/q]" >&2
            if ! IFS= read -r response; then
              return
            fi
            if [[ -z $response ]]; then
              response="y"
            fi
            response="${response,,}"

            case "$response" in
            y | ye | yes)
              ui_info "Removing $(relative_path "$dir")"
              rmdir "$dir"
              break
              ;;
            n | no)
              ui_info "Skipping $(relative_path "$dir")"
              break
              ;;
            q | qu | qui | quit)
              ui_info "Quit requested; stopping prune operation"
              return
              ;;
            *)
              ui_warn "Input '$response' is not valid. Enter yes, no, or quit."
              ;;
            esac
          done
        fi
      else
        ui_info "Removing $(relative_path "$dir")"
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
      ui_error "--repo-root requires a path"
      exit 1
    fi
    REPO_ROOT="$(realpath "$1")"
    ;;
  --file)
    shift
    if [[ $# -eq 0 ]]; then
      ui_error "--file requires a PATH:DEST argument"
      exit 1
    fi
    if [[ ! $1 =~ ^([^:]+):(.+)$ ]]; then
      ui_error "--file argument must be in format PATH:DEST (e.g., /tmp/font.ttf:share/fonts)"
      exit 1
    fi
    FILE_PATH="${BASH_REMATCH[1]}"
    DEST_ROOT="${BASH_REMATCH[2]}"
    FILE_MODE=true
    ;;
  --staged)
    if [[ -n $SCOPED_MODE ]]; then
      ui_error "Git scope flags are mutually exclusive; cannot combine --$SCOPED_MODE and --staged"
      exit 1
    fi
    SCOPED_MODE="staged"
    ;;
  --unstaged)
    if [[ -n $SCOPED_MODE ]]; then
      ui_error "Git scope flags are mutually exclusive; cannot combine --$SCOPED_MODE and --unstaged"
      exit 1
    fi
    SCOPED_MODE="unstaged"
    ;;
  --untracked)
    if [[ -n $SCOPED_MODE ]]; then
      ui_error "Git scope flags are mutually exclusive; cannot combine --$SCOPED_MODE and --untracked"
      exit 1
    fi
    SCOPED_MODE="untracked"
    ;;
  --dry-run)
    DRY_RUN=true
    ;;
  --verbose)
    VERBOSE=true
    ;;
  --rename-list)
    shift
    if [[ $# -eq 0 ]]; then
      ui_error "--rename-list requires a path (use '-' for stdout)"
      exit 1
    fi
    RENAME_LIST_PATH="$1"
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
        ui_error "Invalid --prune-empty mode: $1 (expected 'force' or 'confirm')"
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
    ui_error "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

if [[ $DRY_RUN == "true" && $VERBOSE == "false" && -z $RENAME_LIST_PATH && -t 1 ]]; then
  TABLE_MODE=true
fi

if [[ $DRY_RUN == "true" && $VERBOSE == "false" && $TABLE_MODE == "true" &&
  -t 1 && -t 2 && ${TERM:-dumb} != "dumb" && -z ${NO_COLOR-} ]]; then
  SPINNER_ENABLED=true
fi


if [[ ! -d $REPO_ROOT ]]; then
  ui_error "Repository root not found: $REPO_ROOT"
  exit 1
fi

if [[ $FILE_MODE == "true" && -n $SCOPED_MODE ]]; then
  ui_error "--file cannot be combined with --$SCOPED_MODE"
  exit 1
fi

if [[ $FILE_MODE == "true" ]]; then
  if [[ ! -f $FILE_PATH ]]; then
    ui_error "Font file not found: $FILE_PATH"
    exit 1
  fi
  # Make FILE_PATH absolute
  FILE_PATH="$(realpath "$FILE_PATH")"
  # Make DEST_ROOT absolute (relative to current directory if not absolute)
  if [[ $DEST_ROOT != /* ]]; then
    DEST_ROOT="$(pwd)/$DEST_ROOT"
  fi
  DEST_ROOT="$(realpath -m "$DEST_ROOT")"
  # Override FONTS_DIR to use DEST_ROOT
  FONTS_DIR="$DEST_ROOT"
  log_verbose "File mode: processing $FILE_PATH -> $DEST_ROOT"
else
  if [[ ! -d $FONTS_DIR ]]; then
    ui_error "Fonts directory not found: $FONTS_DIR"
    exit 1
  fi
fi

declare -a SELECTED_FILES=()
if [[ -n $SCOPED_MODE ]]; then
  if ! GIT_TOPLEVEL=$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null); then
    ui_error "--$SCOPED_MODE requires REPO_ROOT to be inside a Git worktree"
    exit 1
  fi
  GIT_TOPLEVEL=$(realpath "$GIT_TOPLEVEL")
  FONTS_DIR=$(realpath "$FONTS_DIR")
  fonts_dir_lower=${FONTS_DIR,,}

  declare -a git_paths=()
  if [[ $SCOPED_MODE == "staged" ]]; then
    mapfile -d '' -t git_paths < <(
      git -C "$GIT_TOPLEVEL" diff --cached --name-only --diff-filter=ACMR -z
    )
  elif [[ $SCOPED_MODE == "unstaged" ]]; then
    mapfile -d '' -t git_paths < <(
      git -C "$GIT_TOPLEVEL" diff --name-only --diff-filter=ACMR -z
    )
  else
    mapfile -d '' -t git_paths < <(
      git -C "$GIT_TOPLEVEL" ls-files --others --exclude-standard -z
    )
  fi

  for git_path in "${git_paths[@]}"; do
    candidate=$(realpath -m "$GIT_TOPLEVEL/$git_path")
    case "${candidate,,}" in
    "$fonts_dir_lower"/*.otf | "$fonts_dir_lower"/*.ttf)
      if [[ -f $candidate ]]; then
        SELECTED_FILES+=("$candidate")
        MOVE_ELIGIBLE[$candidate]="true"
      fi
      ;;
    esac
  done
  SELECTED_COUNT=${#SELECTED_FILES[@]}

  if [[ $SELECTED_COUNT -eq 0 ]]; then
    ui_info "No $SCOPED_MODE font files selected under $(relative_path "$FONTS_DIR"); nothing to do"
    exit 0
  fi

  if [[ $SCOPED_MODE == "staged" ]]; then
    for selected_file in "${SELECTED_FILES[@]}"; do
      selected_git_path="${selected_file#$GIT_TOPLEVEL/}"
      if ! git -C "$GIT_TOPLEVEL" diff --quiet -- "$selected_git_path"; then
        ui_error "Staged font also has unstaged changes: $selected_git_path"
        ui_error "Stage or discard its working-tree changes before using --staged"
        exit 1
      fi
    done
  fi
fi

if ! command -v fc-query >/dev/null 2>&1; then
  ui_error "fc-query is required but was not found in PATH"
  exit 1
fi

declare -a FILE_PATHS=()
declare -a FAMILY_CLEAN=()
declare -a FAMILY_RAW=()
declare -a STYLE_CLEAN=()
declare -a FORMAT=()
declare -a IS_VARIABLE=()
declare -a ALL_STYLES=()

declare -A GROUP_INDICES=()
declare -A FAMILY_SEEN=()
declare -A SANITIZED_FAMILIES=()

if [[ $FILE_MODE == "true" ]]; then
  # Single file mode: process only the specified file
  FONT_FILES=("$FILE_PATH")
  log_verbose "Processing single file: $(relative_path "$FILE_PATH")"
else
  # Normal mode: process all files in FONTS_DIR
  mapfile -t FONT_FILES < <(find "$FONTS_DIR" -type f \( -iname '*.otf' -o -iname '*.ttf' \) | sort)

  if [[ ${#FONT_FILES[@]} -eq 0 ]]; then
    ui_info "No font files found under $(relative_path "$FONTS_DIR")"
    exit 0
  fi

  log_verbose "Found ${#FONT_FILES[@]} font files to analyze"
  if [[ -n $SCOPED_MODE ]]; then
    log_verbose "Selected $SELECTED_COUNT $SCOPED_MODE font file(s); remaining files are classification context only"
  fi
fi

# Progress tracking for analysis phase
total_files=${#FONT_FILES[@]}
processed=0
progress_interval=50
is_tty=false
if [[ -t 2 ]]; then
  is_tty=true
fi
last_percent=-1

if [[ $SPINNER_ENABLED == "true" && $total_files -gt 0 ]]; then
  trap cleanup_spinner EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  start_spinner
fi

for font_file in "${FONT_FILES[@]}"; do
  ((++processed))

  if [[ $VERBOSE == "false" && $TABLE_MODE == "false" ]]; then
    if [[ $is_tty == "true" ]]; then
      if [[ $((processed % progress_interval)) -eq 0 ]]; then
        ui_info "Analyzing fonts: $processed/$total_files" >&2
      fi
    else
      percent=$((processed * 100 / total_files))
      milestone=$((percent / 10 * 10))
      if [[ $milestone -ne $last_percent && $((percent % 10)) -le $((progress_interval * 100 / total_files)) ]]; then
        ui_info "Analyzing fonts: $milestone%" >&2
        last_percent=$milestone
      fi
    fi
  fi

  log_verbose "Analyzing: $(relative_path "$font_file")"

  metadata=$(fc-query --format '%{family[0]}\n%{style[0]}\n%{variable}\n' "$font_file" 2>/dev/null || true)
  if [[ -z $metadata ]]; then
    stop_spinner
    ui_warn "Skipping (fc-query failed): $(relative_path "$font_file")"
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
    stop_spinner
    ui_warn "Missing family metadata; using directory name '$family' for $(relative_path "$font_file")"
  fi

  if [[ -z $style ]]; then
    style="Regular"
    log_verbose "  Empty style, defaulting to 'Regular'"
  fi

  # Normalize family name by stripping redundant style suffix
  original_family="$family"
  family=$(normalize_family "$family" "$style")
  if [[ $family != "$original_family" ]]; then
    log_verbose "  Normalized family: '$original_family' -> '$family' (stripped redundant style suffix)"
  fi

  local_format="${font_file##*.}"
  local_format="${local_format,,}"
  if [[ $local_format != "otf" && $local_format != "ttf" ]]; then
    stop_spinner
    ui_warn "Unsupported font extension in $(relative_path "$font_file")"
    continue
  fi

  local_is_var="false"
  all_styles=""
  # Check if ANY instance in the font has variable: True
  if fc-query --brief "$font_file" 2>/dev/null | grep -q "variable: True"; then
    local_is_var="true"
    log_verbose "  Detected as VARIABLE font (has at least one variable instance)"
    # For variable fonts, collect all style instances to determine italic vs upright
    all_styles=$(fc-query --format '%{style}\n' "$font_file" 2>/dev/null | tr '\n' ' ')
    log_verbose "  All styles: $all_styles"
  else
    log_verbose "  Detected as STATIC font"
  fi

  # Cache sanitized family names to avoid redundant processing
  if [[ -z ${SANITIZED_FAMILIES[$family]:-} ]]; then
    SANITIZED_FAMILIES[$family]=$(sanitize_family "$family")
  fi
  family_clean="${SANITIZED_FAMILIES[$family]}"
  style_clean=$(sanitize_style "$style")

  log_verbose "  Sanitized: family_clean='$family_clean', style_clean='$style_clean'"

  idx=${#FILE_PATHS[@]}
  FILE_PATHS+=("$font_file")
  FAMILY_CLEAN+=("$family_clean")
  FAMILY_RAW+=("$family")
  STYLE_CLEAN+=("$style_clean")
  FORMAT+=("$local_format")
  IS_VARIABLE+=("$local_is_var")
  ALL_STYLES+=("$all_styles")

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

if [[ $VERBOSE == "false" && $TABLE_MODE == "false" && $total_files -gt 0 ]]; then
  if [[ $is_tty == "true" ]]; then
    ui_info "Analyzing fonts: $total_files/$total_files (complete)" >&2
  else
    ui_info "Analyzing fonts: 100% (complete)" >&2
  fi
fi

if [[ ${#FILE_PATHS[@]} -eq 0 ]]; then
  stop_spinner
  ui_info "No usable font files found under $(relative_path "$FONTS_DIR")"
  exit 0
fi

log_verbose "Analysis complete: ${#FILE_PATHS[@]} usable font files grouped into ${#GROUP_INDICES[@]} family/format combinations"

# Identify cross-format duplicates (prefer OTF over TTF)
declare -A CROSS_FORMAT_DUPE_INDICES=()
declare -A OTF_STYLES_BY_FAMILY=()

log_verbose "Detecting cross-format duplicates (OTF vs TTF)..."

# First pass: collect all OTF styles for each family
for key in "${!GROUP_INDICES[@]}"; do
  IFS='|' read -r family_clean format <<<"$key"
  if [[ $format == "otf" ]]; then
    read -ra indices <<<"${GROUP_INDICES[$key]}"
    otf_styles=()
    for idx in "${indices[@]}"; do
      otf_styles+=("${STYLE_CLEAN[$idx]}")
    done
    # Store styles as a space-separated string for easy lookup
    OTF_STYLES_BY_FAMILY[$family_clean]="${otf_styles[*]}"
    log_verbose "  Family '$family_clean' has ${#otf_styles[@]} OTF styles: ${otf_styles[*]}"
  fi
done

# Second pass: mark TTF files that have OTF equivalents
for key in "${!GROUP_INDICES[@]}"; do
  IFS='|' read -r family_clean format <<<"$key"
  if [[ $format == "ttf" ]]; then
    # Check if this family has OTF versions
    if [[ -n ${OTF_STYLES_BY_FAMILY[$family_clean]:-} ]]; then
      read -ra indices <<<"${GROUP_INDICES[$key]}"
      otf_styles_str="${OTF_STYLES_BY_FAMILY[$family_clean]}"
      dupe_count=0
      for idx in "${indices[@]}"; do
        ttf_style="${STYLE_CLEAN[$idx]}"
        # Check if this TTF style exists in OTF format
        if [[ " $otf_styles_str " == *" $ttf_style "* ]]; then
          CROSS_FORMAT_DUPE_INDICES[$idx]="true"
          ((++dupe_count))
          log_verbose "  Marking as cross-format duplicate: $(relative_path "${FILE_PATHS[$idx]}") [has OTF equivalent]"
        fi
      done
      if [[ $dupe_count -gt 0 ]]; then
        log_info "  Found $dupe_count TTF file(s) in '$family_clean' with OTF equivalents"
      fi
    fi
  fi
done

if [[ ${#CROSS_FORMAT_DUPE_INDICES[@]} -gt 0 ]]; then
  log_info "Detected ${#CROSS_FORMAT_DUPE_INDICES[@]} cross-format duplicate(s) (TTF files with OTF equivalents)"
else
  log_verbose "No cross-format duplicates detected"
fi

mapfile -t GROUP_KEYS < <(printf '%s\n' "${!GROUP_INDICES[@]}" | sort)

for key in "${GROUP_KEYS[@]}"; do
  IFS='|' read -r family_clean format <<<"$key"
  read -ra indices <<<"${GROUP_INDICES[$key]}"

  family_raw="${FAMILY_RAW[${indices[0]}]}"
  dest_format_dir="$FONTS_DIR/$family_clean/$format"

  log_info "Processing family '$family_raw' as '$family_clean' [$format]"
  log_verbose "  Group has ${#indices[@]} font file(s)"

  # Handle cross-format duplicates first (TTF files with OTF equivalents)
  if [[ $format == "ttf" ]]; then
    cross_format_dupes=()
    remaining_indices=()
    for idx in "${indices[@]}"; do
      if [[ -n ${CROSS_FORMAT_DUPE_INDICES[$idx]:-} ]]; then
        cross_format_dupes+=("$idx")
      else
        remaining_indices+=("$idx")
      fi
    done

    if [[ ${#cross_format_dupes[@]} -gt 0 ]]; then
      log_info "  Moving ${#cross_format_dupes[@]} TTF file(s) to .duplicate/ (OTF equivalents exist)"
      for idx in "${cross_format_dupes[@]}"; do
        style_clean="${STYLE_CLEAN[$idx]}"
        dest_path="$dest_format_dir/.duplicate/$style_clean/${family_clean}-${style_clean}.${format}"
        perform_move "${FILE_PATHS[$idx]}" "$dest_path"
      done
      # Update indices to only process non-duplicate TTF files
      indices=("${remaining_indices[@]}")
      log_verbose "  ${#indices[@]} unique TTF file(s) remaining (no OTF equivalent)"
    fi

    # If all TTF files were duplicates, skip further processing
    if [[ ${#indices[@]} -eq 0 ]]; then
      log_verbose "  All TTF files were duplicates; skipping further processing for this group"
      continue
    fi
  fi

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

    # Collect paths and compute checksums (parallelized if available)
    declare -a var_paths=()
    declare -a var_path_indices=()
    for idx in "${variable_indices[@]}"; do
      var_paths+=("${FILE_PATHS[$idx]}")
      var_path_indices+=("$idx")
    done

    # Compute checksums in parallel if GNU parallel is available
    if command -v parallel &>/dev/null && [[ ${#var_paths[@]} -gt 1 ]]; then
      log_verbose "    Using parallel MD5 computation for ${#var_paths[@]} files"
      checksum_errors=$(mktemp)
      mapfile -t checksums < <(printf '%s\n' "${var_paths[@]}" | parallel -j "$(nproc)" 'md5sum {} 2>/dev/null | awk "{print \$1}"' 2>"$checksum_errors")
      if [[ -s $checksum_errors ]]; then
        stop_spinner
        ui_warn "Errors during MD5 computation:"
        cat "$checksum_errors" >&2
      fi
      rm -f "$checksum_errors"
    else
      # Fallback to sequential processing
      declare -a checksums=()
      for path in "${var_paths[@]}"; do
        checksums+=("$(md5sum "$path" 2>/dev/null | awk '{print $1}')")
      done
    fi

    # Process checksums and identify unique fonts. In scoped mode, prefer an
    # eligible representative so a context-only identical file cannot prevent
    # the selected file from being organized.
    for i in "${!var_path_indices[@]}"; do
      idx="${var_path_indices[$i]}"
      checksum="${checksums[$i]}"
      if [[ -z ${var_checksums[$checksum]:-} ]]; then
        var_checksums[$checksum]="$idx"
        log_verbose "    Unique: $(relative_path "${FILE_PATHS[$idx]}") [checksum: ${checksum:0:8}...]"
      elif [[ -n $SCOPED_MODE && -n ${MOVE_ELIGIBLE[${FILE_PATHS[$idx]}]:-} &&
        -z ${MOVE_ELIGIBLE[${FILE_PATHS[${var_checksums[$checksum]}]}]:-} ]]; then
        log_verbose "    Selected duplicate becomes move representative: $(relative_path "${FILE_PATHS[$idx]}")"
        var_checksums[$checksum]="$idx"
      else
        log_verbose "    Duplicate: $(relative_path "${FILE_PATHS[$idx]}") (same as index ${var_checksums[$checksum]})"
      fi
    done
    for checksum in "${!var_checksums[@]}"; do
      var_unique_indices+=("${var_checksums[$checksum]}")
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
        # For variable fonts, check all style instances (not just the first one)
        # to determine if this is italic or upright
        is_italic="false"
        idx_all_styles="${ALL_STYLES[$idx]}"
        if [[ -n $idx_all_styles && $idx_all_styles == *"Italic"* ]]; then
          is_italic="true"
        elif [[ ${STYLE_CLEAN[$idx]} == *"Italic"* ]]; then
          # Fallback to checking the first style if all_styles wasn't captured
          is_italic="true"
        fi

        if [[ $is_italic == "true" ]]; then
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
stop_spinner

if [[ $PRUNE_EMPTY == "true" ]]; then
  log_verbose "Prune empty directories mode: $PRUNE_MODE"
  prune_empty_directories
fi

# Display or write the rename list
display_rename_list

total_families=${#FAMILY_SEEN[@]}
if [[ -n $SCOPED_MODE ]]; then
  ui_info "Selected $SELECTED_COUNT $SCOPED_MODE font files; analyzed ${#FILE_PATHS[@]} files across $total_families families"
  if [[ $CONTEXT_ONLY_MOVE_COUNT -gt 0 ]]; then
    ui_warn "Full normalization would move unselected family members; run the unrestricted target to organize them"
  fi
else
  ui_info "Processed ${#FILE_PATHS[@]} font files across $total_families families"
fi
log_verbose "Repository root: $(realpath "$REPO_ROOT")"
log_verbose "Fonts directory: $(realpath "$FONTS_DIR")"
log_verbose "Dry-run mode: $DRY_RUN"
log_verbose "Verbose mode: $VERBOSE"
if [[ $DRY_RUN == "true" ]]; then
  ui_info "Planned moves: $PLANNED_MOVES (dry run)"
else
  ui_info "Executed moves: $EXECUTED_MOVES"
fi

exit 0
