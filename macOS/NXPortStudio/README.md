# NX Port Studio Local

A local macOS GUI over this checkout's existing game-preparation pipeline.
Choose your trusted NXNativ source folder, your own game folder and an existing
`prod.keys` file. Build a Mac app, export an unsigned IPA, or prepare an Xcode
workspace with a step-by-step device guide.

The interface uses English, following the repository's language convention.
The game language can use the engine default, German or English.

## Build and open

Requires an Apple silicon Mac, macOS 14+ and Xcode with Swift 6.
The engine has separate platform and compiler requirements, documented in the
[local build guide](../../docs/dotnet-build.md).

From the repository root:

```sh
swift test --package-path macOS/NXPortStudio
bash macOS/NXPortStudio/scripts/package_app.sh ".tools/gui/NX Port Studio Local.app"
open ".tools/gui/NX Port Studio Local.app"
```

The package contains the GUI, its original source-drawn icon and the MIT license.
It does not contain an engine snapshot, tools, keys, game files or user settings.
It uses a local ad-hoc signature, without selecting a personal signing identity.
Existing app outputs, including dangling symlinks, are rejected.

For development, `swift run --package-path macOS/NXPortStudio NXPortStudio`
starts the same UI. An optional `--repository "/path/to/NXNativ"` selects a
checkout for the current session; it does not check or execute it automatically.

## Workflow

1. **Choose engine** selects your existing trusted checkout. **Check tools**
   verifies the existing Python environment, pinned SDK, local .NET artifact
   manifests, shader compiler fingerprints and iOS tools when needed. Nothing
   is installed, restored or updated.
2. **Choose game folder** selects one game's base NSP/XCI with optional matching
   updates/DLC. NSZ/XCZ inputs require a separately reviewed `nsz` installation;
   that check becomes required when compressed files are selected.
3. **Choose existing prod.keys** selects a file by path. The GUI does not read
   its contents, copy it, paste it into another file or remember the selection.
   The existing extractor reads it during an explicitly started build.
4. Choose **This Mac**, or **iPhone / iPad → Xcode workspace / Unsigned IPA**.
   Output defaults to the selected game folder. Existing exports are not
   overwritten. Extraction and cache files remain beside the game.
5. Start the build. The script's JSON events drive stage names, completion,
   percentage, elapsed time and estimated remaining time. Unknown estimates
   remain unknown. Cancel stops the owned process group, including children
   that ignore normal termination. Successfully cached stages can be reused.

Verification is repeated immediately before the pipeline runs. A changed
manifest or shader compiler stops preparation; there is no override.
Keep games, keys and exported packages outside the engine checkout. Both the
GUI and existing script enforce this boundary; GUI checks resolve symlinks,
including parent directories of new output paths.

**Xcode guide** explains opening the generated workspace, selecting your Apple
account/team, preserving bundle identity, selecting a game scheme and device,
and running through Xcode. The GUI neither signs nor installs iOS apps.
Mac exports explicitly request an ad-hoc signature. Preparing a workspace
preserves the engine's existing signing-settings behavior; the GUI does not
query the Keychain or discover devices.

## Privacy boundaries

- No GUI telemetry, engine downloads, self-updates, package installation,
  account lookup, device discovery, artwork requests or uploads.
- Tool processes run through macOS `sandbox-exec` with outbound IP connections
  denied, including loopback. Descendants inherit the policy. Unix sockets
  and local build services remain available. If the policy cannot be applied,
  the command fails; there is no unrestricted fallback.
- This is an outbound-IP restriction, not a complete filesystem sandbox.
  Select a trusted checkout: the build tools can read files permitted to your
  user. macOS build services and later Xcode actions are separate processes;
  the restriction is not a whole-system traffic guarantee.
- Child environments use a small allowlist rather than forwarding shell
  credentials, SSH agents, Python injection variables or arbitrary PATH
  entries. .NET telemetry and Homebrew analytics are disabled.
- Selected paths and activity stay in memory for the session. The GUI does not
  save preferences or logs. Its activity view redacts selected paths, the home
  directory, recognized key assignments, email addresses and device IDs.
  Redaction is defense in depth, not a promise to detect arbitrary secrets.
- The engine still writes detailed local logs and extracted data under the
  game's `*_build` directory, as before. Review those files before sharing.
  Manual Xcode signing/provisioning can contact Apple.

## Source and scope

Adapted selectively from [seedds/nxnative PR #280](https://github.com/seedds/nxnative/pull/280)
by RobiiAragon, reviewed at head
`05715be61396b8a8b1368212cbeac8b21c1812e5`
(`feature/mac-port-studio`). The upstream project's [MIT license](../../LICENSE)
applies.

Reused and adapted: build argument construction, POSIX process-group handling,
JSON progress decoding, UI layout/style primitives, synthetic core tests and
the source-drawn icon. The local model, toolchain checks, privacy restrictions,
Xcode guide and GUI-only packaging were adapted for this hardened checkout.

Not imported: host/scheduler or shader-reader changes, device/signing services,
automatic installers, pasted-key storage, bundled historical translator
binaries, engine snapshots, Spanish-only localization and unrelated game fixes.

## Validation

See [GUI validation record](../../docs/security/gui-validation.md) for the actual
host checks and limitations. Synthetic tests do not prove full game conversion,
gameplay or physical iPhone behavior.
