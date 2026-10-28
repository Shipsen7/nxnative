# GUI validation record

Initial checks: 2026-10-27. User acceptance recorded: 2026-10-28, for a test
performed on 2026-10-27. Scope: the local GUI branch, based on the existing
hardened checkout at `9e42473`, with a tested Metal compiler fingerprint update
and unsigned-export debug-metadata cleanup. Game runtime code, profiles and
signing entitlements were not changed by this GUI work.

## Imported source

Selected GUI mechanisms from [PR #280](https://github.com/seedds/nxnative/pull/280),
head `05715be61396b8a8b1368212cbeac8b21c1812e5`, adapted as described in
[the GUI guide](../../macOS/NXPortStudio/README.md#source-and-scope).
The PR's engine changes, installers, device/signing services, pasted-key store
and engine packaging were excluded.

## Checked on the current Mac

Apple silicon, macOS 27.0.1, Xcode 27.2 (27B48), Swift 6.4.2.

- Swift debug and release ARM64 GUI builds succeeded.
- 23 Swift tests passed, including argument handling, output preservation,
  symlink boundaries for nonexistent paths, credential-environment filtering,
  display redaction, structured progress with unknown ETA/counts, nonzero
  process failures, process-group cancellation and timeout.
- A child Python process attempted a connection to loopback port 9, without
  contacting the Internet. macOS denied it with EPERM/EACCES under the same
  outbound-IP restriction used for GUI builds.
- The local integration test independently checked the shader lock and
  confirmed the GUI reports the same result as the underlying tool.
  This test checks accurate gating, not that the host toolchain is ready.
- 33 existing Python tests passed: security guards, JSON progress, shader-chain
  inputs, local .NET selection and Xcode preparation workflow.
- The GUI was opened as a packaged local Mac app. Native accessibility and
  screenshots confirmed the source/destination controls, disabled build action
  before setup, local dependency results and readable Xcode guide.
  No actual game or key file was selected during this initial UI inspection;
  subsequent game builds are recorded below.
- Ad-hoc package-signature verification succeeded. The app bundle contains
  only the GUI executable, icon, MIT license and ordinary application metadata.

## Initial build blocker (resolved after compiler validation)

The local .NET artifact manifests, pinned Python packages, exact .NET SDK
10.0.201, XcodeGen and iOS SDK checks passed. Initially, both shader compiler
checks rejected the newer Metal compiler:

| Target | Reviewed lock | Installed compiler |
| --- | --- | --- |
| macOS | 32023.921 (metalfe-32023.921.6) | 32023.922 (metalfe-32023.922.4) |
| iPhoneOS | 32023.921 (metalfe-32023.921.6) | 32023.922 (metalfe-32023.922.4) |

The running GUI initially displayed the mismatch as a required repair. At that
stage no lock/header was updated and no bypass was added. The user subsequently
authorized validation of the newer compiler and a conditional lock update,
following
[the existing build guide](../dotnet-build.md#validate-and-update-the-shader-chain).

The actual source-built translator passed the image-atomic and geometry suites
with Metal compilation/linking enabled for macOS and iPhoneOS, including 114
synthetic Metal compile/link checks and three Mac GPU atomic result/sentinel
runs. The first 22-method run skipped the optional native geometry executable;
that executable was then built and all 10 geometry methods passed with native
canary, compaction and passthrough-kernel GPU checks enabled. Together, every
method in both suites was exercised successfully before the lock was changed.

Only the two Metal version rows in `dm/gfx/tools/dmsh_chain.lock` changed. The
generated header now selects chain `c6d54bedbf04` instead of `ee93a40c81af`.
Translator, source-input and SPIRV-Cross fingerprints are unchanged. The new
lock check passes; 29 security/progress/Xcode/chain regressions and the GUI's
local toolchain gate test pass. The running GUI now reports Tools ready.
There is no mismatch bypass.

The optional nsz module is absent from the selected local Python environment.
NSP/XCI do not need it. Selecting NSZ/XCZ makes this dependency required.

## Game build validation

### User-confirmed GUI workflow: Pokemon Shining Pearl

The user reported on 2026-10-28 that, on 2026-10-27, they independently used the
instructions in the GUI to port Pokemon Shining Pearl and transfer it to their
iPhone, and explicitly considered the test complete. This is user-confirmed
acceptance of the preparation/guide/device-transfer workflow. The agent did
not perform signing or device installation.

On 2026-10-28 the user also explicitly confirmed that the game runs on their
iPhone. Device startup/running is therefore user-confirmed, in addition to the
porting and transfer workflow.

Local build evidence identifies title `010018E011D92000`, version 1.3.0
(`v393216`), using an external provisional profile. The shader build reports
`shaders 14441: ok 14441`; all 14,441 base iOS libraries and their input stamp
are present under chain `c6d54bedbf04`. This confirms that the tested newer
compiler was used successfully for this game's shader build.

No separate gameplay duration, controls, audio, rotation, saving/loading or
device diagnostic log was supplied with this running-game confirmation. Those details are
not inferred. The report does not establish compatibility for other games,
full-game completion or the standalone unsigned-IPA export's CRC/privacy audit.
No game profile or gallery entry is promoted on the basis of this workflow test.

### Earlier agent-started Pokemon Shield export

After the compiler tests and lock update, an unsigned iOS build of Pokemon
Shield 1.3.2 with two DLCs was started from the running GUI, using a new output
directory. Extraction, DLC and rewritten modules were reused. Before the
session was interrupted, shader compilation was still in progress. No finished
IPA was present in that export directory when checked on 2026-10-28. This
attempt is not recorded as a successful export; it is separate from the user's
completed Shining Pearl acceptance test. Existing Shield device results remain
in that game's note.

The subprocess restriction is not a whole-system traffic audit or a filesystem
sandbox. There is no claim that arbitrary source checkouts or engine-generated
diagnostics are safe to share. Selected files and raw engine logs remain local.

## Reproduce

Run from the repository root:

```sh
PORT_STUDIO_TEST_REPOSITORY="$PWD" swift test --package-path macOS/NXPortStudio
.tools/venv/bin/python -B -m unittest dm.tools.tests.test_security_guards \
  dm.tools.tests.test_nsp_progress dm.tools.tests.test_nsp_chain \
  dm.tools.tests.test_nsp_dotnet dm.ios.tests.test_xcode_workflow
.tools/venv/bin/python -B -m unittest dm.tools.tests.test_docs
bash macOS/NXPortStudio/scripts/package_app.sh ".tools/gui/NX Port Studio Local.app"
```

Choose a new package output path if it already exists. No test needs real game
files, console keys, signing identities or a connected device.
