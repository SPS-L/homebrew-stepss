#!/usr/bin/env bash
# Re-points the cask at the newest stepss-java-ui release that carries a .dmg.
# Rewrites exactly two lines, version and sha256, and reports whether they
# moved. It commits nothing and pushes nothing: the workflow does both, and
# only after the rewritten cask has installed on a macOS runner.
#
# Reads UPSTREAM, SCAN_RELEASES and CASK from the environment, and GH_TOKEN
# through gh. Writes `changed` and `version` to GITHUB_OUTPUT when it is set.
set -euo pipefail

upstream="${UPSTREAM:-SPS-L/stepss-java-ui}"
scan="${SCAN_RELEASES:-5}"
cask="${CASK:-Casks/stepss.rb}"

if [[ -n "${DISPATCHED_TAG:-}" ]]
then
  echo "Woken by ${DISPATCHED_TAG}."
fi

tags=$(gh release list --repo "${upstream}" --limit "${scan}" \
  --exclude-drafts --exclude-pre-releases --json tagName --jq '.[].tagName')

tag=""
line=""
for candidate in ${tags}
do
  # Deliberately no pipe and no `|| true` on this call. A request that fails
  # must stop the run. Read as "this release has no dmg", it sends the loop on
  # to an older release, and the cask is then rewritten backwards.
  #
  # `// ""` on the digest, because jq renders null as the string "null", which
  # is not empty and would be written into the cask as a hash.
  line=$(gh api "repos/${upstream}/releases/tags/${candidate}" \
    --jq '[.assets[] | select(.name | endswith(".dmg"))][0] // empty
          | "\(.name)\t\(.digest // "")\t\(.browser_download_url)"')
  if [[ -n "${line}" ]]
  then
    tag="${candidate}"
    break
  fi
  echo "no dmg in ${candidate}"
done
if [[ -z "${tag}" ]]
then
  echo "None of the last ${scan} releases of ${upstream} carries a .dmg."
  exit 1
fi

name=$(printf '%s' "${line}" | cut -f1)
digest=$(printf '%s' "${line}" | cut -f2)
url=$(printf '%s' "${line}" | cut -f3)

hash="${digest#sha256:}"
if [[ -z "${hash}" ]]
then
  echo "The API reports no digest for ${name}; hashing the download."
  asset=$(mktemp)
  curl -fsSL -o "${asset}" "${url}"
  sum=$(shasum -a 256 "${asset}")
  hash="${sum%% *}"
  rm -f "${asset}"
fi
version="${tag#v}"

# Both values are about to be written into a Ruby file.
if [[ ! "${hash}" =~ ^[0-9a-f]{64}$ ]]
then
  echo "Not a SHA-256: '${hash}'."
  exit 1
fi
if [[ ! "${version}" =~ ^[0-9]+(\.[0-9]+)+$ ]]
then
  echo "Not a version this cask can carry: '${version}'."
  exit 1
fi

# Never backwards. The scan above takes the newest release with a .dmg, which
# is older than the cask whenever the newest release has lost its .dmg or a
# maintenance release was cut on an older line. Neither is something to
# publish to every user's `brew upgrade` unattended.
current=$(sed -n 's/^  version "\(.*\)"$/\1/p' "${cask}")
if [[ -z "${current}" ]]
then
  echo "No version line found in ${cask}."
  exit 1
fi
newest=$(printf '%s\n%s\n' "${current}" "${version}" | sort -V | tail -1)
if [[ "${newest}" != "${version}" ]]
then
  echo "The cask is at ${current} and the newest release with a .dmg is ${version}."
  echo "Refusing to move the cask backwards; edit it by hand if that is intended."
  exit 1
fi

NEW_VERSION="${version}" perl -pi -e 's|^  version ".*"|  version "$ENV{NEW_VERSION}"|' "${cask}"
NEW_HASH="${hash}" perl -pi -e 's|^  sha256 ".*"|  sha256 "$ENV{NEW_HASH}"|' "${cask}"
grep -q "^  version \"${version}\"" "${cask}"
grep -q "^  sha256 \"${hash}\"" "${cask}"

echo "${name} from ${tag}, sha256 ${hash}"
if git diff --quiet -- "${cask}"
then
  changed=false
  echo "Already at ${version}."
else
  changed=true
  git --no-pager diff -- "${cask}"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]
then
  {
    echo "changed=${changed}"
    echo "version=${version}"
  } >>"${GITHUB_OUTPUT}"
fi
