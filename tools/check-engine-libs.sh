#!/usr/bin/env bash
# Checks that every library the bundled macOS engines link against exists on
# this machine and comes from a formula the cask declares. The engines travel
# as .tar.gz resources inside stepss.jar and are extracted at run time, so
# neither jpackage nor Homebrew can see what they need: the cask's depends_on
# is written by hand, and this is what catches it going stale. A missing
# library otherwise shows up as an application that opens normally and fails
# on the first simulation.
#
# Usage: check-engine-libs.sh [path-to-STEPSS.app] [path-to-cask]
#
# Presence alone is not the test. A CI runner, and many a developer's Mac, has
# formulae installed for unrelated reasons, so a library can be on disk without
# the cask being what put it there. Each Homebrew path is therefore traced to
# its formula, and the formula has to be named in the cask.
set -euo pipefail

app="${1:-/Applications/STEPSS.app}"
cask="${2:-$(dirname "$0")/../Casks/stepss.rb}"
jar="${app}/Contents/app/stepss.jar"
if [[ ! -f "${jar}" ]]
then
  echo "No stepss.jar under ${app}/Contents/app."
  exit 1
fi
if [[ ! -f "${cask}" ]]
then
  echo "No cask at ${cask}."
  exit 1
fi

# The formula names on the cask's `depends_on formula:` line.
declared=$(grep -E '^[[:space:]]*depends_on formula:' "${cask}" | grep -oE '"[^"]+"' | tr -d '"' || true)
if [[ -z "${declared}" ]]
then
  echo "${cask} declares no formula dependency."
  exit 1
fi

# Listed before extracting, so that a jar with no macOS payload is reported as
# that and not as an unzip error.
payloads=$(unzip -Z1 "${jar}" | grep -E '^my/stepss/payload/.*macos.*\.tar\.gz$' || true)
if [[ -z "${payloads}" ]]
then
  echo "No macOS payload under my/stepss/payload/ in ${jar}."
  exit 1
fi

work=$(mktemp -d)
list=$(mktemp)
trap 'rm -rf "${work}" "${list}"' EXIT

unzip -q "${jar}" 'my/stepss/payload/*macos*.tar.gz' -d "${work}"
for archive in "${work}"/my/stepss/payload/*macos*.tar.gz
do
  dest="${work}/$(basename "${archive}" .tar.gz)"
  mkdir -p "${dest}"
  tar -xzf "${archive}" -C "${dest}"
done

# Written to a file, not read from a process substitution, so that a find
# failure stops the script.
find "${work}" -type f -not -name '*.tar.gz' -print0 >"${list}"

brew_prefix=$(brew --prefix)
prefix="${brew_prefix}/opt/"
checked=0
problems=0
while IFS= read -r -d '' binary
do
  file -b "${binary}" | grep -q 'Mach-O' || continue
  checked=$((checked + 1))
  name=$(basename "${binary}")
  # Captured first, not read from a process substitution, so that an otool
  # failure stops the script instead of counting the binary as clean.
  libs=$(otool -L "${binary}" | tail -n +2 | awk '{print $1}')
  while IFS= read -r lib
  do
    case "${lib}" in
      "") continue ;;
      # System libraries live in the dyld shared cache, not on disk.
      /usr/lib/* | /System/*) continue ;;
      "${prefix}"*)
        formula="${lib#"${prefix}"}"
        formula="${formula%%/*}"
        if ! grep -qxF "${formula}" <<<"${declared}"
        then
          echo "UNDECLARED  ${name} -> ${lib} (formula ${formula} is not in the cask)"
          problems=$((problems + 1))
        elif [[ -e "${lib}" ]]
        then
          echo "ok          ${name} -> ${lib}"
        else
          echo "MISSING     ${name} -> ${lib}"
          problems=$((problems + 1))
        fi
        ;;
      *)
        # Not a system path and not under Homebrew's opt/: an @rpath entry or
        # a build-machine path, which no cask dependency can satisfy.
        echo "UNRESOLVABLE ${name} -> ${lib}"
        problems=$((problems + 1))
        ;;
    esac
  done <<<"${libs}"
done <"${list}"

# A scan that finds nothing is not a pass: it means the payload moved.
if [[ "${checked}" -eq 0 ]]
then
  echo "No Mach-O binary found in the macOS payloads of ${jar}."
  exit 1
fi
if [[ "${problems}" -ne 0 ]]
then
  echo "${problems} library reference(s) unresolved across ${checked} engine binaries."
  exit 1
fi
echo "All libraries resolve across ${checked} engine binaries."
