#!/usr/bin/env bash

set -euo pipefail

SCRIPT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rename-fonts.sh
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  [[ $1 == *"$2"* ]] || fail "expected output to contain: $2"
}

assert_not_contains() {
  [[ $1 != *"$2"* ]] || fail "expected output not to contain: $2"
}

make_repo() {
  local repo="$1"
  mkdir -p "$repo/share/fonts" "$repo/fake-bin"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  git -C "$repo" config commit.gpgsign false
  cat >"$repo/fake-bin/fc-query" <<'EOF'
#!/usr/bin/env bash
file=${!#}
name=$(basename "$file")
family=${name%%-*}
style=${name#*-}
style=${style%.*}
[[ $style == "$family" ]] && style=Regular
if [[ " $* " == *" --brief "* ]]; then
  printf 'variable: False\n'
else
  printf '%s\n%s\nFalse\n' "$family" "$style"
fi
EOF
  chmod +x "$repo/fake-bin/fc-query"
}

run_fonts() {
  local repo="$1"
  shift
  PATH="$repo/fake-bin:$PATH" TERM=dumb REPO_ROOT="$repo" "$SCRIPT" "$@" 2>&1
}

repo="$TEST_ROOT/repo"
make_repo "$repo"
printf base >"$repo/share/fonts/Family-Regular.ttf"
printf base >"$repo/share/fonts/Other-Regular.ttf"
git -C "$repo" add .
git -C "$repo" commit -qm base

# Staged additions (including spaces), modifications, and renames are selected;
# untracked and unstaged paths are classification context only.
printf changed >"$repo/share/fonts/Family-Regular.ttf"
git -C "$repo" add "$repo/share/fonts/Family-Regular.ttf"
printf new >"$repo/share/fonts/Added-Bold.ttf"
printf spaced >"$repo/share/fonts/Space Family-Italic.ttf"
git -C "$repo" add "$repo/share/fonts/Added-Bold.ttf" "$repo/share/fonts/Space Family-Italic.ttf"
git -C "$repo" mv share/fonts/Other-Regular.ttf share/fonts/Renamed-Regular.ttf
printf untracked >"$repo/share/fonts/Loose-Regular.ttf"
output=$(run_fonts "$repo" --staged --dry-run --rename-list -)
assert_contains "$output" "Family-Regular.ttf ->"
assert_contains "$output" "Added-Bold.ttf ->"
assert_contains "$output" "Space Family-Italic.ttf ->"
assert_contains "$output" "Renamed-Regular.ttf ->"
assert_not_contains "$output" "Loose-Regular.ttf ->"

# Additional unstaged bytes on a staged path fail before any planned move.
printf extra >>"$repo/share/fonts/Added-Bold.ttf"
if output=$(run_fonts "$repo" --staged --dry-run 2>&1); then
  fail "--staged accepted a selected file with unstaged changes"
fi
assert_contains "$output" "also has unstaged changes"
git -C "$repo" checkout -- share/fonts/Added-Bold.ttf

# Untracked excludes ignored files and leaves tracked context untouched.
printf 'share/fonts/Ignored-Regular.ttf\n' >"$repo/.gitignore"
printf ignored >"$repo/share/fonts/Ignored-Regular.ttf"
output=$(run_fonts "$repo" --untracked --dry-run --rename-list -)
assert_contains "$output" "Loose-Regular.ttf ->"
assert_not_contains "$output" "Ignored-Regular.ttf"
assert_not_contains "$output" "Family-Regular.ttf ->"

if run_fonts "$repo" --staged --untracked >/dev/null 2>&1; then
  fail "--staged --untracked was accepted"
fi
if run_fonts "$repo" --staged --unstaged >/dev/null 2>&1; then
  fail "--staged --unstaged was accepted"
fi
if run_fonts "$repo" --staged --file "$repo/share/fonts/Family-Regular.ttf:share/fonts" >/dev/null 2>&1; then
  fail "scoped mode with --file was accepted"
fi

# Empty selection succeeds before fc-query or collection analysis.
empty="$TEST_ROOT/empty"
make_repo "$empty"
printf '#!/usr/bin/env bash\nexit 99\n' >"$empty/fake-bin/fc-query"
chmod +x "$empty/fake-bin/fc-query"
output=$(run_fonts "$empty" --untracked --dry-run)
assert_contains "$output" "nothing to do"

# Unstaged mode selects tracked working-tree changes, including paths with
# spaces, while excluding staged-only and untracked files.
unstaged="$TEST_ROOT/unstaged"
make_repo "$unstaged"
printf base >"$unstaged/share/fonts/Work-Regular.ttf"
printf base >"$unstaged/share/fonts/Work Space-Italic.ttf"
printf base >"$unstaged/share/fonts/Staged-Regular.ttf"
git -C "$unstaged" add .
git -C "$unstaged" commit -qm base
printf changed >"$unstaged/share/fonts/Work-Regular.ttf"
printf changed >"$unstaged/share/fonts/Work Space-Italic.ttf"
printf staged >"$unstaged/share/fonts/Staged-Regular.ttf"
git -C "$unstaged" add share/fonts/Staged-Regular.ttf
printf loose >"$unstaged/share/fonts/Loose-Regular.ttf"
output=$(run_fonts "$unstaged" --unstaged --dry-run --rename-list -)
assert_contains "$output" "Work-Regular.ttf ->"
assert_contains "$output" "Work Space-Italic.ttf ->"
assert_not_contains "$output" "Staged-Regular.ttf ->"
assert_not_contains "$output" "Loose-Regular.ttf ->"

# A tracked OTF supplies duplicate context for an untracked TTF but remains
# ineligible itself. Unrestricted mode still plans moves for the full set.
context="$TEST_ROOT/context"
make_repo "$context"
printf otf >"$context/share/fonts/Dupe-Regular.otf"
git -C "$context" add .
git -C "$context" commit -qm base
printf ttf >"$context/share/fonts/Dupe-Regular.ttf"
output=$(run_fonts "$context" --untracked --dry-run --rename-list -)
assert_contains "$output" "Dupe-Regular.ttf -> share/fonts/Dupe/ttf/.duplicate/"
assert_not_contains "$output" "Dupe-Regular.otf ->"
output=$(run_fonts "$context" --dry-run --rename-list -)
assert_contains "$output" "Dupe-Regular.otf ->"
assert_contains "$output" "Dupe-Regular.ttf ->"

printf 'PASS: Git-scoped font organization\n'
