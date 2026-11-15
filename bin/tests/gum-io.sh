#!/usr/bin/env bash

set -euo pipefail

SOURCE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
ORIGINAL_PATH=$PATH
MAKE_BIN=$(command -v make || true)
PYTHON_BIN=$(command -v python3 || true)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

assert_file() {
  [[ -f $1 ]] || fail "expected file: $1"
}

assert_dir() {
  [[ -d $1 ]] || fail "expected directory: $1"
}

assert_absent() {
  [[ ! -e $1 ]] || fail "expected path to be absent: $1"
}

assert_contains_file() {
  local file=$1
  local text=$2
  grep -Fq -- "$text" "$file" || fail "expected $file to contain: $text"
}

assert_precedes_file() {
  local file=$1
  local first=$2
  local second=$3
  "$PYTHON_BIN" - "$file" "$first" "$second" <<'PY' || fail "expected '$first' before '$second' in $file"
import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
first = data.find(sys.argv[2].encode())
second = data.find(sys.argv[3].encode())
if first < 0 or second < 0 or first >= second:
    sys.exit(1)
PY
}

assert_not_contains_file() {
  local file=$1
  local text=$2
  if grep -Fq -- "$text" "$file"; then
    fail "expected $file not to contain: $text"
  fi
}

assert_no_ansi() {
  local file=$1
  if LC_ALL=C grep -q $'\033' "$file"; then
    fail "ANSI escape sequence found in $file"
  fi
}

if [[ -z $MAKE_BIN || -z $PYTHON_BIN ]]; then
  fail 'GNU Make and Python 3 are required'
fi
if ! command -v gum >/dev/null 2>&1 || ! gum version-check '>= 2.0.2' >/dev/null 2>&1; then
  fail 'Gum 2.0.2 or later is required to run the interactive tests'
fi

FAKE_BIN="$TEST_ROOT/fake-bin"
mkdir -p "$FAKE_BIN"

cat >"$FAKE_BIN/fc-query" <<'EOF'
#!/usr/bin/env bash
arguments=("$@")
last_argument=$((${#arguments[@]} - 1))
font=${arguments[$last_argument]}
format=''
brief=false
while (($#)); do
  case $1 in
    -f|--format)
      format=${2:-}
      shift 2
      ;;
    --brief)
      brief=true
      shift
      ;;
    *) shift ;;
  esac
done
name=$(basename "$font")
family=${name%%-*}
style=${name#*-}
style=${style%.*}
[[ $style == "$name" || -z $style ]] && style=Regular
if [[ $brief == true ]]; then
  printf 'variable: False\n'
elif [[ $format == *'%{family[0]}'* && $format == *'%{style[0]}'* ]]; then
  printf '%s\n%s\nFalse\n' "$family" "$style"
elif [[ $format == *'%{family[0]}|%{variable}'* ]]; then
  printf '%s|False\n' "$family"
elif [[ $format == *'%{fullname[0]}'* ]]; then
  printf '%s %s\n' "$family" "$style"
elif [[ $format == *'%{spacing}'* ]]; then
  printf '100\n'
elif [[ $format == *'%{family}'* || $format == *'%{family[0]}'* ]]; then
  printf '%s\n' "$family"
else
  printf '%s\n' "$family"
fi
EOF

cat >"$FAKE_BIN/fontimage" <<'EOF'
#!/usr/bin/env bash
output=''
while (($#)); do
  if [[ $1 == -o ]]; then
    output=${2:-}
    shift 2
  else
    shift
  fi
done
[[ -n $output ]] || exit 2
printf 'fixture preview\n' >"$output"
EOF

cat >"$FAKE_BIN/fonttools" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == ttx && ${2:-} == -t ]] || exit 0
output=''
while (($#)); do
  if [[ $1 == -o ]]; then
    output=${2:-}
    shift 2
  else
    shift
  fi
done
[[ -n $output ]] || exit 2
printf '<ttFont><OS_2><fsType value="00000000 00000100"/></OS_2></ttFont>\n' >"$output"
EOF

cat >"$FAKE_BIN/fc-cache" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FC_CACHE_LOG:-/dev/null}"
EOF

cat >"$FAKE_BIN/parallel" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then
  printf 'fixture parallel stub\n'
  exit 0
fi
printf 'unexpected parallel invocation\n' >&2
exit 99
EOF

cat >"$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_BIN"/*

new_fixture() {
  local name=$1
  FIXTURE="$TEST_ROOT/$name"
  mkdir -p "$FIXTURE"
  cp "$SOURCE_ROOT/Makefile" "$FIXTURE/Makefile"
  cp -R "$SOURCE_ROOT/bin" "$FIXTURE/bin"
  mkdir -p "$FIXTURE/share/fonts" "$FIXTURE/home"
}

capture() {
  local label=$1
  local cwd=$2
  local path=$3
  shift 3
  CAPTURE_OUT="$TEST_ROOT/$label.stdout"
  CAPTURE_ERR="$TEST_ROOT/$label.stderr"
  if (
    cd "$cwd"
    env PATH="$path" TERM=dumb NO_COLOR=1 HOME="$cwd/home" \
      XDG_DATA_HOME="$cwd/xdg-data" XDG_CONFIG_HOME="$cwd/xdg-config" \
      REPO_ROOT="$cwd" FONTS_DIR="$cwd/share/fonts" PARALLEL_JOBS=1 \
      "$@"
  ) >"$CAPTURE_OUT" 2>"$CAPTURE_ERR"; then
    CAPTURE_STATUS=0
  else
    CAPTURE_STATUS=$?
  fi
}

capture_input() {
  local label=$1
  local cwd=$2
  local path=$3
  local input=$4
  shift 4
  CAPTURE_OUT="$TEST_ROOT/$label.stdout"
  CAPTURE_ERR="$TEST_ROOT/$label.stderr"
  if (
    printf '%s' "$input" |
      (cd "$cwd" && env PATH="$path" TERM=dumb NO_COLOR=1 HOME="$cwd/home" \
        XDG_DATA_HOME="$cwd/xdg-data" XDG_CONFIG_HOME="$cwd/xdg-config" \
        REPO_ROOT="$cwd" FONTS_DIR="$cwd/share/fonts" PARALLEL_JOBS=1 "$@")
  ) >"$CAPTURE_OUT" 2>"$CAPTURE_ERR"; then
    CAPTURE_STATUS=0
  else
    CAPTURE_STATUS=$?
  fi
}

pty_capture() {
  local label=$1
  local cwd=$2
  local input=$3
  shift 3
  CAPTURE_OUT="$TEST_ROOT/$label.pty"
  local status_file="$TEST_ROOT/$label.status"
  if ! PATH="$FAKE_BIN:$ORIGINAL_PATH" TERM=xterm-256color NO_COLOR=1 \
    HOME="$cwd/home" XDG_DATA_HOME="$cwd/xdg-data" XDG_CONFIG_HOME="$cwd/xdg-config" \
    REPO_ROOT="$cwd" FONTS_DIR="$cwd/share/fonts" PARALLEL_JOBS=1 \
    "$PYTHON_BIN" - "$CAPTURE_OUT" "$status_file" "$input" "$cwd" "$@" <<'PY'
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

output_path, status_path, input_text, cwd, *argv = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(cwd)
    os.environ.update({"TERM": "xterm-256color", "COLUMNS": "120", "LINES": "40"})
    if os.environ.get("PTY_NO_COLOR") == "0":
        os.environ.pop("NO_COLOR", None)
    else:
        os.environ["NO_COLOR"] = "1"
    os.execvpe(argv[0], argv, os.environ)

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
output = bytearray()
input_sent = not input_text
deadline = time.monotonic() + 12
exit_status = None
try:
    while time.monotonic() < deadline:
        readable, _, _ = select.select([fd], [], [], 0.1)
        if readable:
            try:
                chunk = os.read(fd, 8192)
            except OSError:
                chunk = b""
            if chunk:
                output.extend(chunk)
        if not input_sent and b"?" in output:
            if input_text:
                os.write(fd, input_text.encode())
            input_sent = True
        waited, status = os.waitpid(pid, os.WNOHANG)
        if waited:
            exit_status = status
            # Drain output already written by the child.
            while select.select([fd], [], [], 0.05)[0]:
                try:
                    chunk = os.read(fd, 8192)
                except OSError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
            break
    if exit_status is None:
        os.killpg(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        raise TimeoutError("PTY child did not finish within 12 seconds")
    if not input_sent:
        raise TimeoutError("PTY child exited without displaying an interactive prompt")
finally:
    os.close(fd)

with open(output_path, "wb") as output_file:
    output_file.write(output)
if os.WIFEXITED(exit_status):
    code = os.WEXITSTATUS(exit_status)
elif os.WIFSIGNALED(exit_status):
    code = 128 + os.WTERMSIG(exit_status)
else:
    code = 1
with open(status_path, "w", encoding="ascii") as status_file:
    status_file.write(str(code))
PY
  then
    fail "PTY interaction failed or timed out: $label"
  fi
  CAPTURE_STATUS=$(<"$status_file")
}

FIXTURE_PATH="$FAKE_BIN:$ORIGINAL_PATH"

# Terminal and redirected confirmations are exercised only in disposable copies.
for choice in default-no explicit-no escape yes; do
  new_fixture "clean-$choice"
  mkdir -p "$FIXTURE/share/fonts/Family/.duplicate" "$FIXTURE/share/fonts/Family/.delete"
  : >"$FIXTURE/share/fonts/Family/.duplicate/font.ttf"
  : >"$FIXTURE/share/fonts/Family/.delete/font.ttf"
  case $choice in
  default-no) input=$'\r' ;;
  explicit-no) input=$'n\r' ;;
  escape) input=$'\033' ;;
  yes) input=$'y\r' ;;
  esac
  pty_capture "clean-$choice" "$FIXTURE" "$input" "$MAKE_BIN" -j2 clean
  [[ $CAPTURE_STATUS -eq 0 ]] || fail 'terminal make clean failed'
  assert_contains_file "$CAPTURE_OUT" 'Directory'
  assert_contains_file "$CAPTURE_OUT" 'Files'
  assert_contains_file "$CAPTURE_OUT" '.duplicate'
  assert_contains_file "$CAPTURE_OUT" '.delete'
  assert_precedes_file "$CAPTURE_OUT" '.duplicate' 'Remove these directories?'
  assert_precedes_file "$CAPTURE_OUT" '.delete' 'Remove these directories?'
  if [[ $choice == yes ]]; then
    assert_absent "$FIXTURE/share/fonts/Family/.duplicate"
    assert_absent "$FIXTURE/share/fonts/Family/.delete"
  else
    assert_dir "$FIXTURE/share/fonts/Family/.duplicate"
    assert_dir "$FIXTURE/share/fonts/Family/.delete"
  fi
done

new_fixture clean-pipe-yes
mkdir -p "$FIXTURE/share/fonts/Family/.duplicate" "$FIXTURE/share/fonts/Family/.delete"
: >"$FIXTURE/share/fonts/Family/.duplicate/font.ttf"
: >"$FIXTURE/share/fonts/Family/.delete/font.ttf"
capture_input clean-pipe-yes "$FIXTURE" "$FIXTURE_PATH" $'Y\n' "$MAKE_BIN" clean
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'piped Y did not approve make clean'
assert_absent "$FIXTURE/share/fonts/Family/.duplicate"
assert_absent "$FIXTURE/share/fonts/Family/.delete"

new_fixture clean-pipe-eof
mkdir -p "$FIXTURE/share/fonts/Family/.duplicate" "$FIXTURE/share/fonts/Family/.delete"
: >"$FIXTURE/share/fonts/Family/.duplicate/font.ttf"
: >"$FIXTURE/share/fonts/Family/.delete/font.ttf"
capture_input clean-pipe-eof "$FIXTURE" "$FIXTURE_PATH" '' "$MAKE_BIN" clean
assert_dir "$FIXTURE/share/fonts/Family/.duplicate"
assert_dir "$FIXTURE/share/fonts/Family/.delete"

for choice in default-no explicit-no escape yes; do
  new_fixture "uninstall-$choice"
  mkdir -p "$FIXTURE/xdg-data/fonts/Fixture"
  printf 'sentinel font\n' >"$FIXTURE/xdg-data/fonts/Fixture/sentinel.ttf"
  case $choice in
  default-no) input=$'\r' ;;
  explicit-no) input=$'n\r' ;;
  escape) input=$'\033' ;;
  yes) input=$'y\r' ;;
  esac
  pty_capture "uninstall-$choice" "$FIXTURE" "$input" "$MAKE_BIN" -j2 uninstall
  assert_contains_file "$CAPTURE_OUT" "$FIXTURE/xdg-data/fonts"
  prompt="Remove all fonts from $FIXTURE/xdg-data/fonts?"
  assert_contains_file "$CAPTURE_OUT" "$prompt"
  assert_precedes_file "$CAPTURE_OUT" 'Font families to remove:' "$prompt"
  if [[ $choice == yes ]]; then
    assert_absent "$FIXTURE/xdg-data/fonts"
  else
    assert_file "$FIXTURE/xdg-data/fonts/Fixture/sentinel.ttf"
  fi
done

new_fixture uninstall-pipe-yes
mkdir -p "$FIXTURE/xdg-data/fonts/Fixture"
printf 'sentinel font\n' >"$FIXTURE/xdg-data/fonts/Fixture/sentinel.ttf"
capture_input uninstall-pipe-yes "$FIXTURE" "$FIXTURE_PATH" $'Y\n' "$MAKE_BIN" uninstall
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'piped Y did not approve make uninstall'
assert_absent "$FIXTURE/xdg-data/fonts"

new_fixture uninstall-pipe-eof
mkdir -p "$FIXTURE/xdg-data/fonts/Fixture"
printf 'sentinel font\n' >"$FIXTURE/xdg-data/fonts/Fixture/sentinel.ttf"
capture_input uninstall-pipe-eof "$FIXTURE" "$FIXTURE_PATH" '' "$MAKE_BIN" uninstall
assert_file "$FIXTURE/xdg-data/fonts/Fixture/sentinel.ttf"
pass 'make clean/uninstall PTY and piped-input safeguards'

make_prune_fixture() {
  local name=$1
  new_fixture "$name"
  mkdir -p "$FIXTURE/share/fonts/Fixture/ttf/Regular"
  printf 'font bytes\n' >"$FIXTURE/share/fonts/Fixture/ttf/Regular/Fixture-Regular.ttf"
}

make_prune_fixture prune-enter
mkdir -p "$FIXTURE/share/fonts/empty-enter"
pty_capture prune-enter "$FIXTURE" $'\r' "$FIXTURE/bin/rename-fonts.sh" --prune-empty confirm
assert_absent "$FIXTURE/share/fonts/empty-enter"

make_prune_fixture prune-skip
mkdir -p "$FIXTURE/share/fonts/empty-skip"
pty_capture prune-skip "$FIXTURE" $'\033[B\r' "$FIXTURE/bin/rename-fonts.sh" --prune-empty confirm
assert_dir "$FIXTURE/share/fonts/empty-skip"

make_prune_fixture prune-quit
mkdir -p "$FIXTURE/share/fonts/empty-a" "$FIXTURE/share/fonts/empty-b" "$FIXTURE/share/fonts/empty-c"
pty_capture prune-quit "$FIXTURE" $'\033[B\033[B\r' "$FIXTURE/bin/rename-fonts.sh" --prune-empty confirm
assert_dir "$FIXTURE/share/fonts/empty-a"
assert_dir "$FIXTURE/share/fonts/empty-b"
assert_dir "$FIXTURE/share/fonts/empty-c"

make_prune_fixture prune-escape
mkdir -p "$FIXTURE/share/fonts/empty-a" "$FIXTURE/share/fonts/empty-b" "$FIXTURE/share/fonts/empty-c"
pty_capture prune-escape "$FIXTURE" $'\033' "$FIXTURE/bin/rename-fonts.sh" --prune-empty confirm
assert_dir "$FIXTURE/share/fonts/empty-a"
assert_dir "$FIXTURE/share/fonts/empty-b"
assert_dir "$FIXTURE/share/fonts/empty-c"

make_prune_fixture prune-piped
mkdir -p "$FIXTURE/share/fonts/empty-a" "$FIXTURE/share/fonts/empty-b" "$FIXTURE/share/fonts/empty-c"
capture_input prune-piped "$FIXTURE" "$FIXTURE_PATH" $'\nno\nquit\n' "$FIXTURE/bin/rename-fonts.sh" --prune-empty confirm
assert_absent "$FIXTURE/share/fonts/empty-c"
assert_dir "$FIXTURE/share/fonts/empty-b"
assert_dir "$FIXTURE/share/fonts/empty-a"

make_prune_fixture prune-eof
mkdir -p "$FIXTURE/share/fonts/empty-a" "$FIXTURE/share/fonts/empty-b" "$FIXTURE/share/fonts/empty-c"
capture_input prune-eof "$FIXTURE" "$FIXTURE_PATH" '' "$FIXTURE/bin/rename-fonts.sh" --prune-empty confirm
assert_dir "$FIXTURE/share/fonts/empty-a"
assert_dir "$FIXTURE/share/fonts/empty-b"
assert_dir "$FIXTURE/share/fonts/empty-c"

make_prune_fixture prune-dryrun
mkdir -p "$FIXTURE/share/fonts/empty-a" "$FIXTURE/share/fonts/empty-b"
capture prune-dryrun "$FIXTURE" "$FIXTURE_PATH" "$FIXTURE/bin/rename-fonts.sh" --dry-run --prune-empty confirm
assert_dir "$FIXTURE/share/fonts/empty-a"
assert_dir "$FIXTURE/share/fonts/empty-b"

make_prune_fixture prune-force
mkdir -p "$FIXTURE/share/fonts/empty-a" "$FIXTURE/share/fonts/empty-b"
capture prune-force "$FIXTURE" "$FIXTURE_PATH" "$FIXTURE/bin/rename-fonts.sh" --prune-empty force
assert_absent "$FIXTURE/share/fonts/empty-a"
assert_absent "$FIXTURE/share/fonts/empty-b"
pass 'rename-fonts prune choices, piped parser, EOF, dry-run, and force mode'

# Terminal dry runs show one table row per planned move, without hiding paths.
new_fixture dryrun-table
font_name='Fixture,"quoted"-Regular.ttf'
printf 'font bytes\n' >"$FIXTURE/share/fonts/$font_name"
pty_capture dryrun-table "$FIXTURE" '' "$MAKE_BIN" dryrun
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'terminal make dryrun failed'
assert_contains_file "$CAPTURE_OUT" 'Source'
assert_contains_file "$CAPTURE_OUT" 'Destination'
assert_contains_file "$CAPTURE_OUT" "$font_name"
assert_not_contains_file "$CAPTURE_OUT" 'Would move'
assert_file "$FIXTURE/share/fonts/$font_name"
pass 'terminal dry-run table preserves paths and does not move files'

# Rename-list records stay machine-readable, including paths with percent signs.
new_fixture 'rename%fixture'
printf 'font bytes\n' >"$FIXTURE/share/fonts/Fixture-Regular.ttf"
capture rename-stdout "$FIXTURE" "$FIXTURE_PATH" "$FIXTURE/bin/rename-fonts.sh" --dry-run --rename-list -
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'rename-list stdout mode failed'
expected_record='share/fonts/Fixture-Regular.ttf -> share/fonts/Fixture/ttf/Regular/Fixture-Regular.ttf'
grep -Fxq -- "$expected_record" "$CAPTURE_OUT" || fail 'rename-list stdout record changed'
assert_no_ansi "$CAPTURE_OUT"
assert_no_ansi "$CAPTURE_ERR"

capture rename-file "$FIXTURE" "$FIXTURE_PATH" "$FIXTURE/bin/rename-fonts.sh" --dry-run --rename-list "$FIXTURE/renames.txt"
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'rename-list file mode failed'
assert_contains_file "$CAPTURE_OUT" "$FIXTURE/renames.txt"
assert_file "$FIXTURE/renames.txt"
grep -Fxq -- "$expected_record" "$FIXTURE/renames.txt" || fail 'rename-list file record changed'
assert_file "$FIXTURE/share/fonts/Fixture-Regular.ttf"
assert_absent "$FIXTURE/share/fonts/Fixture/ttf/Regular/Fixture-Regular.ttf"
assert_no_ansi "$FIXTURE/renames.txt"
assert_no_ansi "$CAPTURE_OUT"
assert_no_ansi "$CAPTURE_ERR"

capture ui-percent "$FIXTURE" "$FIXTURE_PATH" "$FIXTURE/bin/ui.sh" info 'Progress is 100% literal'
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'direct UI info operation failed'
assert_contains_file "$CAPTURE_OUT" 'Progress is 100% literal'
assert_no_ansi "$CAPTURE_OUT"
assert_no_ansi "$CAPTURE_ERR"
capture ui-warning "$FIXTURE" "$FIXTURE_PATH" "$FIXTURE/bin/ui.sh" warn 'Literal 50% warning'
assert_contains_file "$CAPTURE_ERR" 'Literal 50% warning'
assert_not_contains_file "$CAPTURE_OUT" 'Literal 50% warning'
assert_no_ansi "$CAPTURE_OUT"
assert_no_ansi "$CAPTURE_ERR"
capture ui-error "$FIXTURE" "$FIXTURE_PATH" "$FIXTURE/bin/ui.sh" error 'Literal 25% error'
assert_contains_file "$CAPTURE_ERR" 'Literal 25% error'
assert_not_contains_file "$CAPTURE_OUT" 'Literal 25% error'
pass 'rename-list data, literal percent messages, output streams, and redirected ANSI behavior'

# Help and invalid-option paths must use the shared UI without ANSI under NO_COLOR.
new_fixture help-fixture
for script in rename-fonts.sh gen-previews.sh gen-stats.sh gen-fontconfig.sh set-usage.sh; do
  capture "help-$script" "$FIXTURE" "$FIXTURE_PATH" "$FIXTURE/bin/$script" --help
  [[ $CAPTURE_STATUS -eq 0 ]] || fail "$script --help failed"
  [[ -s $CAPTURE_OUT ]] || fail "$script --help produced no output"
  assert_no_ansi "$CAPTURE_OUT"
  assert_no_ansi "$CAPTURE_ERR"
  capture "invalid-$script" "$FIXTURE" "$FIXTURE_PATH" "$FIXTURE/bin/$script" '--invalid-50%-option'
  [[ $CAPTURE_STATUS -ne 0 ]] || fail "$script accepted an invalid option"
  [[ -s $CAPTURE_ERR ]] || fail "$script did not report an invalid option on stderr"
  assert_contains_file "$CAPTURE_ERR" '%'
  assert_no_ansi "$CAPTURE_OUT"
  assert_no_ansi "$CAPTURE_ERR"
done

# An isolated PATH retains host utilities but deliberately omits Gum.
NO_GUM_BIN="$TEST_ROOT/no-gum-bin"
mkdir -p "$NO_GUM_BIN"
IFS=: read -r -a path_dirs <<<"$ORIGINAL_PATH"
for path_dir in "${path_dirs[@]}"; do
  [[ -n $path_dir && -d $path_dir ]] || continue
  for executable in "$path_dir"/*; do
    [[ -x $executable && ! -d $executable ]] || continue
    command_name=${executable##*/}
    [[ $command_name == gum ]] && continue
    [[ -e $NO_GUM_BIN/$command_name ]] || ln -s "$executable" "$NO_GUM_BIN/$command_name"
  done
done
NO_GUM_PATH="$NO_GUM_BIN:$FAKE_BIN"

new_fixture missing-gum
printf 'keep\n' >"$FIXTURE/share/fonts/Fixture-Regular.ttf"
mkdir -p "$FIXTURE/share/doc/fonts"
printf 'keep preview\n' >"$FIXTURE/share/doc/fonts/keep.txt"
for script in rename-fonts.sh gen-previews.sh gen-stats.sh gen-fontconfig.sh set-usage.sh; do
  capture "missing-gum-$script" "$FIXTURE" "$NO_GUM_PATH" "$FIXTURE/bin/$script" --help
  [[ $CAPTURE_STATUS -ne 0 ]] || fail "$script did not reject missing Gum"
  assert_contains_file "$CAPTURE_ERR" 'Gum 2.0.2 or later is required. Install gum.'
done
assert_file "$FIXTURE/share/fonts/Fixture-Regular.ttf"
assert_file "$FIXTURE/share/doc/fonts/keep.txt"

mkdir -p "$FIXTURE/share/fonts/Family/.duplicate" "$FIXTURE/xdg-data/fonts/Fixture"
printf 'keep duplicate\n' >"$FIXTURE/share/fonts/Family/.duplicate/font.ttf"
printf 'keep installed font\n' >"$FIXTURE/xdg-data/fonts/Fixture/sentinel.ttf"
capture_input missing-gum-make-clean "$FIXTURE" "$NO_GUM_PATH" $'Y\n' "$MAKE_BIN" -j2 clean
[[ $CAPTURE_STATUS -ne 0 ]] || fail 'make clean did not reject missing Gum'
assert_contains_file "$CAPTURE_ERR" 'Gum 2.0.2 or later is required. Install gum.'
assert_file "$FIXTURE/share/fonts/Family/.duplicate/font.ttf"
capture_input missing-gum-make-uninstall "$FIXTURE" "$NO_GUM_PATH" $'Y\n' "$MAKE_BIN" -j2 uninstall
[[ $CAPTURE_STATUS -ne 0 ]] || fail 'make uninstall did not reject missing Gum'
assert_contains_file "$CAPTURE_ERR" 'Gum 2.0.2 or later is required. Install gum.'
assert_file "$FIXTURE/xdg-data/fonts/Fixture/sentinel.ttf"
capture missing-gum-make-install "$FIXTURE" "$NO_GUM_PATH" "$MAKE_BIN" -j2 install
[[ $CAPTURE_STATUS -ne 0 ]] || fail 'make install did not reject missing Gum'
assert_absent "$FIXTURE/xdg-data/fonts/Fixture-Regular.ttf"
pass 'missing-Gum refusal before script and Makefile mutations'

# Exercise make smoke parsing with controlled child output, never the real repository.
new_fixture smoke-fixture
mkdir -p "$FIXTURE/share/fonts"
printf 'font bytes\n' >"$FIXTURE/share/fonts/Fixture-Regular.ttf"
cat >"$FIXTURE/bin/rename-fonts.sh" <<'EOF'
#!/usr/bin/env bash
printf 'Processed 4 font files across 2 families\n'
EOF
cat >"$FIXTURE/bin/gen-stats.sh" <<'EOF'
#!/usr/bin/env bash
case ${SMOKE_STATS_CASE:-match} in
  match)
    printf 'Statistics match README.md (4 fonts, 2 families)\n'
    ;;
  difference)
    printf 'Statistics differ from README.md:\n'
    exit 1
    ;;
  error)
    printf 'stats stdout marker\n'
    printf 'stats stderr marker\n' >&2
    exit 7
    ;;
esac
EOF
chmod +x "$FIXTURE/bin/rename-fonts.sh" "$FIXTURE/bin/gen-stats.sh"
capture smoke-match "$FIXTURE" "$FIXTURE_PATH" env SMOKE_STATS_CASE=match "$MAKE_BIN" smoke
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'make smoke failed on matching statistics'
assert_contains_file "$CAPTURE_OUT" '4 fonts'
assert_contains_file "$CAPTURE_OUT" '2 families'
assert_no_ansi "$CAPTURE_OUT"
assert_no_ansi "$CAPTURE_ERR"
capture smoke-difference "$FIXTURE" "$FIXTURE_PATH" env SMOKE_STATS_CASE=difference "$MAKE_BIN" smoke
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'make smoke did not report differing statistics'
assert_contains_file "$CAPTURE_OUT" 'Statistics differ from README.md'
assert_contains_file "$CAPTURE_ERR" 'Statistics differ from README.md'
assert_no_ansi "$CAPTURE_OUT"
capture smoke-error "$FIXTURE" "$FIXTURE_PATH" env SMOKE_STATS_CASE=error "$MAKE_BIN" smoke
[[ $CAPTURE_STATUS -ne 0 ]] || fail 'make smoke accepted an unexpected statistics error'
assert_contains_file "$CAPTURE_OUT" 'stats stdout marker'
assert_contains_file "$CAPTURE_ERR" 'stats stderr marker'
pass 'make smoke match/difference/error parsing and stream preservation'

pty_capture smoke-table "$FIXTURE" '' "$MAKE_BIN" smoke
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'terminal make smoke failed'
assert_contains_file "$CAPTURE_OUT" 'Check'
assert_contains_file "$CAPTURE_OUT" 'Result'
assert_contains_file "$CAPTURE_OUT" 'Details'
assert_contains_file "$CAPTURE_OUT" '4 fonts'
assert_contains_file "$CAPTURE_OUT" '2 families'
pty_capture help-table "$FIXTURE" '' "$MAKE_BIN" help
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'terminal make help failed'
assert_contains_file "$CAPTURE_OUT" 'Target'
assert_contains_file "$CAPTURE_OUT" 'Action'
assert_contains_file "$CAPTURE_OUT" 'dryrun'
pass 'terminal help and smoke tables'

# A spinner must not hide a failed preview job or change its exit status.
new_fixture spinner-failure
printf 'font bytes\n' >"$FIXTURE/share/fonts/Fixture-Regular.ttf"
spin_bin="$TEST_ROOT/spin-bin"
cp -R "$FAKE_BIN" "$spin_bin"
export REAL_GUM="$(command -v gum)" SPIN_LOG="$TEST_ROOT/spin.log"
cat >"$spin_bin/gum" <<'EOF'
#!/usr/bin/env bash
if [[ ${1-} == spin ]]; then echo spin >>"$SPIN_LOG"; fi
exec "$REAL_GUM" "$@"
EOF
chmod +x "$spin_bin/gum"
cat >"$spin_bin/parallel" <<'EOF'
#!/usr/bin/env bash
if [[ ${1-} == --version ]]; then
  echo 'GNU parallel'
  exit 0
fi
echo 'worker failure marker' >&2
exit 42
EOF
chmod +x "$spin_bin/parallel"
FAKE_BIN="$spin_bin"
PTY_NO_COLOR=0 pty_capture spinner-failure "$FIXTURE" '' "$FIXTURE/bin/gen-previews.sh" --jobs 1
[[ $CAPTURE_STATUS -eq 42 ]] || fail 'preview spinner changed the job exit status'
assert_contains_file "$SPIN_LOG" 'spin'
assert_contains_file "$CAPTURE_OUT" 'worker failure marker'
assert_contains_file "$CAPTURE_OUT" 'Preview generation failed.'
pass 'preview spinner preserves worker failure'

# Each spinner must preserve the work result and stay off in plain output.
new_fixture dryrun-spinner
printf 'font bytes\n' >"$FIXTURE/share/fonts/Fixture-Regular.ttf"
: >"$SPIN_LOG"
PTY_NO_COLOR=0 pty_capture dryrun-spinner "$FIXTURE" '' "$FIXTURE/bin/rename-fonts.sh" --dry-run
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'dry-run spinner failed'
assert_contains_file "$SPIN_LOG" 'spin'
assert_contains_file "$CAPTURE_OUT" 'Fixture-Regular.ttf'
assert_contains_file "$CAPTURE_OUT" 'Planned moves: 1'
assert_file "$FIXTURE/share/fonts/Fixture-Regular.ttf"
: >"$SPIN_LOG"
capture dryrun-plain "$FIXTURE" "$FAKE_BIN:$ORIGINAL_PATH" "$FIXTURE/bin/rename-fonts.sh" --dry-run
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'redirected dry run failed'
assert_not_contains_file "$SPIN_LOG" 'spin'
assert_no_ansi "$CAPTURE_OUT"
assert_no_ansi "$CAPTURE_ERR"
pass 'dry-run spinner preserves results and plain output'

for script in gen-stats.sh set-usage.sh; do
  new_fixture "$script-spinner"
  printf 'font bytes\n' >"$FIXTURE/share/fonts/Fixture-Regular.ttf"
  : >"$SPIN_LOG"
  PTY_NO_COLOR=0 pty_capture "$script-spinner" "$FIXTURE" '' "$FIXTURE/bin/$script" --jobs 1
  [[ $CAPTURE_STATUS -eq 42 ]] || fail "$script spinner changed the job exit status"
  assert_contains_file "$SPIN_LOG" 'spin'
  assert_contains_file "$CAPTURE_OUT" 'worker failure marker'
done
pass 'statistics and usage spinners preserve worker failures'

# The sequential fallback also reports a complete dry-run result.
cat >"$spin_bin/parallel" <<'EOF'
#!/usr/bin/env bash
echo 'not GNU parallel'
exit 1
EOF
chmod +x "$spin_bin/parallel"
new_fixture usage-sequential-spinner
printf 'font bytes\n' >"$FIXTURE/share/fonts/Fixture-Regular.ttf"
: >"$SPIN_LOG"
PTY_NO_COLOR=0 pty_capture usage-sequential-spinner "$FIXTURE" '' "$FIXTURE/bin/set-usage.sh" --dry-run --jobs 1
[[ $CAPTURE_STATUS -eq 0 ]] || fail 'sequential usage dry run failed'
assert_contains_file "$SPIN_LOG" 'spin'
assert_contains_file "$CAPTURE_OUT" '1 would be modified'
assert_file "$FIXTURE/share/fonts/Fixture-Regular.ttf"
pass 'usage spinner preserves sequential dry-run results'

pass 'Gum I/O regression coverage completed'
