# Build the local .NET tools

Run commands at the repository root on an Apple silicon Mac. Use Python 3.14 and the **official .NET SDK 10.0.201** selected by `global.json`. Install Xcode and its command line tools; the synthetic iOS build also needs XcodeGen. Khronos SPIRV-Cross and SPIRV-Tools validate the translation output.

```sh
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 brew install python@3.14 xcodegen spirv-cross spirv-tools
xcodebuild -downloadComponent MetalToolchain
xcrun --kill-cache
python3.14 -m venv .tools/venv
. .tools/venv/bin/activate
python -m pip install --index-url https://pypi.org/simple --only-binary=:all: lz4==4.4.5 capstone==5.0.6 fonttools==4.60.1
# If the Microsoft SDK was installed in ~/.dotnet:
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$PATH"
python scripts/build_dotnet_tools.py --restore
python scripts/build_dotnet_tools.py
python scripts/build_dotnet_tools.py --verify
```

Download the SDK from [Microsoft's .NET download page](https://dotnet.microsoft.com/en-us/download/dotnet/10.0). Review its published installer/checksum. Do not pipe a downloaded installer script into a shell. The existing SDK on the audited Mac was used; this work does not independently attest the SDK binary. SDK upgrades require a deliberate `global.json` change and renewed validation.

The first command restores **locked** packages from **nuget.org only**, runs NuGet vulnerability auditing for all dependencies, rejects package build hooks/analyzers/executables, verifies package signatures, and records archive and extracted-file hashes. A failed audit/signature check stops the build. A network connection is needed for this step. Source or lock changes require repeating it.

The second command publishes with `--no-restore`, disabled build servers and deterministic compilation. It disables implicit Git/SourceLink metadata and maps source paths to `/src`, so owner remote URLs and changing Git state do not enter the artifacts. It performs no dependency download. Outputs live in ignored `.tools/dotnet/{dmsh_xlate,nx_extract}`. Each tool gets a local manifest covering the complete .NET input tree and every output file, including the apphost. The shader chain and NSP build check this manifest **before executing the tools**. This is a local integrity receipt, not a third-party attestation or defense against someone who can rewrite the checkout and receipt together.

The shader tool and its three Ryujinx projects are compiled from the checked-in sources and need **zero NuGet packages**. The extractor's own code is compiled locally but **LibHac remains a signed, locked NuGet binary**, not a source rebuild. Its official source URL was unavailable during this audit; see [dependencies](../DEPENDENCIES.md).

## Validate and update the shader chain

```sh
export DMSH_TEST_XLATE="$PWD/.tools/dotnet/dmsh_xlate/dmsh_xlate"
DMSH_TEST_METAL=1 DMSH_TEST_METAL_SDKS=macosx,iphoneos DMSH_TEST_GPU=1 \
  python -m unittest -v dm/tools/tests/test_image_atomic_bounds.py dm/gfx/tests/test_dmsh_geometry.py
# Only after the actual translation/Metal tests pass:
python dm/gfx/tools/dmsh_chain.py --update-lock
python dm/gfx/tools/dmsh_chain.py --header
python dm/gfx/tools/dmsh_chain.py --check-tools
```

The committed lock records the tested translator assemblies, complete .NET input hash, SPIRV-Cross binary and Metal versions. The chain version additionally includes all .NET sources, resources, project definitions, dependency locks and the strict compiler wrapper. Old shader caches therefore get a different `b-<version>` directory. A missing compiler stops the check. `own_compilers.py` no longer filters compiler mismatches. Repeat validation and update both the lock and header after changing compilers; rebuild the affected game libraries and host. No compatibility claim is made for old libraries or untested games.

For an isolated local build/test on macOS, the audit used the following profile after completing package restore:

```sh
sandbox-exec -p '(version 1) (allow default) (deny network-outbound (remote ip "*:*"))' \
  python scripts/build_dotnet_tools.py
```

This denies outgoing IP connections while allowing local build services. It is not a VM or a complete filesystem sandbox. Ordinary builds also work without this optional macOS-specific wrapper.

## Synthetic iOS build and game preparation

```sh
GAME=010015100B514000 python dm/ios/tools/compile_check.py
GAME=010015100B514000 python dm/ios/tools/build_smoke.py --output "$PWD/.tools/ios-smoke-new"
```

The output directory must be new. The smoke build creates an Xcode project and an unsigned app from synthetic modules/resources. It is a compile/link fixture, **not a playable game**, and must not be presented as a device runtime test.

Keep your own dumps and keys **outside this checkout**, preferably on an external drive with enough free space. The NSP script rejects a game directory or key path resolving inside the checkout. It does not need network access for package restore while processing your files.

```sh
python scripts/build_ipa_from_nsp.py "/Volumes/MyDrive/MyGame" \
  -k "/Volumes/MyDrive/Private/prod.keys" --prepare-xcode
```

Open the workspace printed by the script, select your own signing team and device in Xcode, and build there. The repository was not signed or installed on a device during this audit. Unregistered games/builds may still need a profile and graphics work. The original [development guide](development.md) describes those limitations.

## Local repository protection

```sh
git config core.hooksPath .githooks
python scripts/repository_guard.py --history
```

The commit hook scans staged contents; the push hook also scans reachable history and permits only the explicitly approved `origin`. For this owner-approved public fork, configure the destination and its expected visibility locally:

```sh
git config nxnative.approvedRepository Shipsen7/nxnative
git config nxnative.approvedVisibility public
```

The hook verifies both values against GitHub and checks the actual push URL. Repository visibility changes require renewed approval and configuration. Private destinations must also be independent repositories. Hooks can be bypassed, so keep keys/dumps outside Git even with these protections. The scanner detects selected filename patterns, Nintendo key assignments, private-key blocks and token patterns; it is not a guarantee that arbitrary private data cannot be committed.
