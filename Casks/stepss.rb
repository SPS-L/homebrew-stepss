cask "stepss" do
  version "3.83.1"
  sha256 "d80cb876c0ef5d7016bffd583f55a24ef8d7cbef77fd8d303cc9b5cedb8e9cfc"

  url "https://github.com/SPS-L/stepss-java-ui/releases/download/v#{version}/STEPSS-#{version}.dmg"
  name "STEPSS"
  desc "Static and transient electric power systems simulation platform"
  homepage "https://stepss.sps-lab.org/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  # Runtime requirements of the bundled engines: RAMSES loads OpenBLAS, and
  # RAMSES, CODEGEN and DYNGRAPH load libgfortran from Homebrew's gcc.
  depends_on formula: ["openblas", "gcc"]
  depends_on :macos

  app "STEPSS.app"

  caveats <<~EOS
    STEPSS is not free software taken as a whole. The licence is shown on
    first launch; see https://stepss.sps-lab.org/getting-started/license/
  EOS
end
