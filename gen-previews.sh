#!/usr/bin/env bash
#
# Generate preview images of all font files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$SCRIPT_DIR}"

fontimage=$( type -P fontimage )
fcquery=$( type -P fc-query )

pm="preview.md"
pp="${REPO_ROOT}/_preview"

truncate -s 0 "${pm}"
rm -rf "${pp}"
mkdir -pv "${pp}"

shopt -ss globstar extglob

for ff in "${REPO_ROOT}"/**/*.[ot]tf; do 
  fp=${ff#/opt/fonts/src/}
  fs=${fp//\//__}
  fs=${fs%.[ot]tf}
  if [[ ${fs} == *Variable ]] &&
    [[ $( fc-query -f '${variable}' "${ff}" ) == *True* ]]; then
    fn=$( "${fcquery}" -i 0 -f '%{family[0]} (Variable)' "${ff}" )
  else
    fn="$( "${fcquery}" -i 0 -f '%{fullname[0]}' "${ff}" )"
  fi
  fe='.png'

  #[[ ! -e "${pp}/${fs}${fe}" ]] || continue

  if "${fontimage}" -o "${pp}/${fs}${fe}" "${ff}" &>output.log; then
    printf -- '## %s\n![%s](%s)\n\n' "${fn}" "${fn}" "${pp##*/}/${fs}${fe}" | tee -a "${pm}"
  fi
done
