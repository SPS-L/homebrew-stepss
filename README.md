# STEPSS Homebrew tap

A [Homebrew](https://brew.sh/) tap for **STEPSS**, *Static and Transient Electric Power Systems Simulation*. It installs the desktop application on macOS and keeps it current, so a new release arrives through `brew upgrade` instead of being downloaded once per version.

```bash
brew install --cask sps-l/stepss/stepss
```

Thereafter:

```bash
brew upgrade --cask stepss
```

Uninstall with `brew uninstall --cask stepss`.

The cask brings Homebrew's `gcc` and `openblas` with it. That is the reason this route exists alongside the `.dmg`: the simulation engines load `libgfortran` and OpenBLAS from Homebrew at run time, and an application installed by hand opens normally and then fails on the first simulation unless both are already there.

If STEPSS is already in Applications from a `.dmg`, move it to the Trash first. Homebrew does not overwrite an application it did not install.

## What this route requires and what it is not

- **Apple Silicon.** There is no Intel macOS build of the engines.
- **The current release only.** The tap serves one version. To install a specific older build, take its `.dmg` from the [releases page](https://github.com/SPS-L/stepss-java-ui/releases).
- **A network connection on first launch.** The application is signed and notarized. The notarization ticket is stapled to the `.dmg`, not to the application inside it, so macOS verifies the installed copy with Apple the first time it opens.
- **This is not an official Homebrew cask**, and nothing in it has been through the Homebrew maintainers' review. Naming the cask in full, as the command above does, is what tells Homebrew you trust it; `brew trust --tap sps-l/stepss` trusts the whole tap instead.

## Licensing

**STEPSS is not Apache 2.0 taken as a whole**, and the cask's caveat says so deliberately.

- **RAMSES**, the dynamic simulation engine, is the property of the University of Liège: proprietary, free for non-commercial use, capped at 1000 buses and 2 cores.
- **Helios** and **CODEGEN** are under Academic Public Licences.
- The two user interfaces, **stepss-java-ui** and **stepss-python-ui**, are Apache 2.0.

<https://stepss.sps-lab.org/getting-started/license/> is the single owner of these facts; everything here is a summary that points at it. Installing through Homebrew agrees to nothing, because the licence appears the first time you launch STEPSS. The `.dmg` is downloaded from the SPS-L release page and never mirrored here: the licence granted for RAMSES is non-transferable.

## How the cask stays current

`Casks/stepss.rb` is rewritten by `.github/workflows/update-cask.yml`, which is triggered four ways:

| Trigger | When |
|---|---|
| `repository_dispatch` (`stepss-release`) | stepss-java-ui fires it from the `promote` job of its release workflow, once the release is published with every platform attached |
| `schedule`, weekly | insurance, because a dropped or 401ing dispatch is silent on this side |
| `workflow_dispatch` | by hand |
| `push` to `main` | checks a hand edit; rewrites nothing |

`tools/update-cask.sh` rewrites exactly two lines, `version` and `sha256`, and the workflow commits only if they moved. Everything else in the cask is hand-edited. The hash comes from the GitHub API's own per-asset digest. The script never moves the cask backwards: if the newest release carrying a `.dmg` is older than the cask, the run fails and a person decides.

Nothing is pushed until it has been installed. The job runs on macOS, commits the rewrite locally, installs the cask from that local commit, and runs `tools/check-engine-libs.sh`, which fails when a bundled engine links a library from a formula the cask does not declare. Only then does it push, so a cask that cannot install never reaches `brew upgrade`.

### Two things that will break this quietly

- **The release asset name is a contract.** The cask resolves `STEPSS-<version>.dmg` on tag `v<version>` of stepss-java-ui. Renaming it there breaks every release cut afterwards, and older tags stay un-resyncable because the new name never existed on them. Rename it in both repositories in one pass or not at all.
- **A published asset must stay where it is.** Homebrew downloads an exact URL and verifies an exact digest, so deleting or re-uploading a release asset breaks every install of that version.

### Maintenance

| When | Do |
|---|---|
| Every release | Nothing. The dispatch updates the cask; check the run is green. |
| `.app` renamed, or the dmg layout changes | Edit `app` in the cask by hand; the workflow only touches `version` and `sha256`. |
| Engine linking changes | Adjust `depends_on formula:`. `tools/check-engine-libs.sh` names the library. |
| Red run | Read the failing step: `brew audit` names the stanza, the library check names the library and its formula, and a refused downgrade names both versions. Nothing was pushed. |
| Dropped dispatch | The Monday schedule catches it, or run `gh workflow run update-cask.yml`. |

### Troubleshooting

- `Error: Cask 'stepss' is unavailable`: use the full name `sps-l/stepss/stepss`, or run `brew tap sps-l/stepss` first.
- `It seems there is already an App at '/Applications/STEPSS.app'`: a copy installed from a `.dmg` is in the way. Move it to the Trash and install again.
- `dyld: Library not loaded: .../libgfortran.5.dylib`: `gcc` was removed after installing. Run `brew install gcc`.
- `"STEPSS" cannot be opened because the developer cannot be verified`: the Mac was offline at first launch. Connect and open it again.
- A checksum mismatch on install: the asset was re-uploaded after the cask was written. Run the update workflow.

## Related

- [stepss-java-ui](https://github.com/SPS-L/stepss-java-ui) builds the artifact this serves
- [stepss-scoop](https://github.com/SPS-L/stepss-scoop) is the same idea for Windows
- [apt.sps-lab.org](https://apt.sps-lab.org/) is the same idea for Debian and Ubuntu
- [stepss.sps-lab.org](https://stepss.sps-lab.org/) is the documentation
