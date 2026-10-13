#!/usr/bin/env bash
# Checks that every library the bundled macOS engines link against exists on
# this machine. The engines travel as .tar.gz resources inside stepss.jar and
# are extracted at run time, so neither jpackage nor Homebrew can see what they
# need: the cask's depends_on is written by hand, and this is what catches it
# going stale. A missing library otherwise shows up as an application that
# opens normally and fails on the first simulation.
set -euo pipefail

app="${1:-/Applications/STEPSS.app}"
jar="${app}/Contents/app/stepss.jar"
if [[ ! -f "${jar}" ]]
then
  echo "No stepss.jar under ${app}/Contents/app."
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

unzip -q "${jar}" 'my/stepss/payload/*macos*.tar.gz' -d "${work}"
for archive in "${work}"/my/stepss/payload/*macos*.tar.gz
do
  dest="${work}/$(basename "${archive}" .tar.gz)"
  mkdir -p "${dest}"
  tar -xzf "${archive}" -C "${dest}"
done

checked=0
missing=0
while IFS= read -r -d '' binary
do
  file -b "${binary}" | grep -q 'Mach-O' || continue
  checked=$((checked + 1))
  while IFS= read -r lib
  do
    # System libraries live in the dyld shared cache, not on disk.
    case "${lib}" in
      /usr/lib/* | /System/*) continue ;;
      *) ;;
    esac
    if [[ -e "${lib}" ]]
    then
      echo "ok       $(basename "${binary}") -> ${lib}"
    else
      echo "MISSING  $(basename "${binary}") -> ${lib}"
      missing=$((missing + 1))
    fi
  done < <(otool -L "${binary}" | tail -n +2 | awk '{print $1}')
done < <(find "${work}" -type f -not -name '*.tar.gz' -print0)

# A scan that finds nothing is not a pass: it means the payload moved.
if [[ "${checked}" -eq 0 ]]
then
  echo "No Mach-O binary found in the macOS payloads of ${jar}."
  exit 1
fi
if [[ "${missing}" -ne 0 ]]
then
  echo "${missing} library reference(s) unresolved across ${checked} engine binaries."
  exit 1
fi
echo "All libraries resolve across ${checked} engine binaries."
