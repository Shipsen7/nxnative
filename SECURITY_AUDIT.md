# NXNative security and privacy audit

Date: **2026-10-26**. Scope: local fork preparation, .NET supply chain, build scripts/workflows, iOS privacy, and static review of host/app networking and process launch sites. This is a source and controlled-test assessment, not a complete malware certification or independent binary analysis of dependencies.

## Repository state

- Cloned `Shipsen7/nxnative`, default branch `main`, base **40b643bbe68861d171cb1a2733a953aa739f9ac1**.
- Upstream HEAD observed during this run: **cc626e7fa14320c1fce431ef9d9b6fa902a78282**. It differs from the audited base; no automatic update or merge was performed.
- The owner approved keeping `Shipsen7/nxnative` as a **public fork** and publishing the reviewed changes. Public source visibility does not publish local game files or keys; those must stay outside Git.
- The push guard checks the explicitly approved owner repository and visibility. `upstream` points at `seedds/nxnative` with a disabled push URL. Commits use the owner's public GitHub handle and noreply identity; no upstream impersonation remains in `AGENTS.md`.
- GitHub Actions was enabled on the public fork. It was explicitly disabled through the API and rechecked. The retained test workflow now has only a manual trigger and read-only repository permissions; it builds the translator from source. No automatic upstream sync was introduced.

## Findings and changes

| Severity | Finding and evidence | Treatment / limit |
|---|---|---|
| High | The normal shader path executed shipped artifacts in `dm/gfx/tools/dmsh_xlate_bin`, including 60 PE/.NET files and a native apphost, without independently established provenance. | Entire directory removed from the current tree. Static inventory retained. Source-built tools, locked restore, package hook rejection, signature/audit checks and file manifests replace it. Historical binaries remain in history but have no fallback execution path. |
| Privacy boundary | Public pushes expose committed source, documentation and commit metadata. Public visibility alone is not a runtime vulnerability. | Owner-approved public fork; publication review covers the outgoing history as well as the final tree. Local paths and private metadata removed; keys, dumps, builds and logs excluded. |
| Medium | `dm/ios/Sources/main.m` printed every `env.txt` variable value and an absolute RomFS path; logs were backed up by default. The Mac launcher's `env_file` also printed values. | Removed environment-value/name logging on both platforms and the iOS RomFS path log. iOS persistent diagnostics now require explicit `DM_DIAGNOSTICS=1`. Otherwise output is discarded and the two prior logs are removed. Logs and local environment settings excluded from backups. |
| Medium | `dm/host/crash.c` interpolated `DM_WATCH_SAMPLE` into a single-quoted shell command. An apostrophe could change the command. This was an opt-in local diagnostic, not an automatic remote entry point. | Replaced `system()` with a fixed `/usr/bin/sample` process and separate arguments. stdout/stderr redirected using spawn file actions. No diagnostic output path is printed. |
| Medium | Root `.gitignore` did not protect keys, dumps, signing material or extraction outputs. | Added case-insensitive key/dump patterns, private settings/signing rules, build ignores, staged/history scanner and commit/push hooks. NSP script rejects input folders/key files resolving inside the checkout. Hooks require local installation and can be bypassed. |
| Medium | `own_compilers.py` deliberately filtered Metal/SPIRV-Cross lock mismatches while keeping the same chain version. Old cached libraries could survive a compiler change. | Removed this exception. Full strict check retained through that entry point; every .NET source/resource/project/lock and wrapper change enters the chain digest. No fingerprint was refreshed merely to silence a failed translation test. |
| Medium, residual | LibHac source URL is unavailable; extractor uses official NuGet LibHac 0.19.0. Package signatures establish distribution integrity, not absence of malicious code. | Fixed package graph, canonical SHA-512 lock, successful NuGet signature verification, no executable build hooks/analyzers, all-dependency vulnerability audit. Parser output/errors are suppressed during key loading. Full source rebuild remains unresolved. |
| Low / expected | `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` expose the app's Documents through user-controlled Files access. | Retained deliberately for local saves/import/export; not a network service. Device backup of saves remains enabled and can participate in user-configured iCloud/device backups. |

## Static networking / execution review

Searches covered runtime host/app sources, .NET projects and source, build scripts, workflow definitions, and third-party source manifests for HTTP clients, socket connections, upload/analytics APIs, identifiers, dynamic loads, encoded commands, process starts and build hooks. Matches were inspected at the relevant call sites. Keyword searching is not an exhaustive manual proof of all source behavior.

- `dm/host/hle_net.c`: networking availability is false; socket creation/connection/send/name resolution entry points return offline errors. Poll/select preserve the expected offline timing. No outbound host socket implementation was identified in these hooks.
- `dm/host/hle_offline.c`: Nintendo telemetry/reporting, BCAT and related online services are unavailable/no-op. `dm/host/hle_account.c` uses local account data and fails online account/token operations. These are compatibility implementations, not proof that arbitrary guest machine code cannot misbehave.
- No HTTP client, analytics SDK, automatic log/game-information uploader or device identifier upload was identified in the reviewed iOS app/host sources. No App Transport Security exception, cloud-container entitlement or broad network entitlement was added. iOS generally permits network access without a special entitlement; this app is **not** a network sandbox for arbitrary guest code.
- The old full Common project contained URL constants and OS process helpers (`OpenHelper`, file association helpers). These are not a demonstrated exfiltration mechanism; they are now excluded from the actual shader assembly along with unrelated serializers and packages.
- `dm/mac/launcher.c` legitimately starts the bundled local host via `posix_spawn`; its alert helper uses `osascript` with separate arguments. `nvn_mtl.m` resolves existing process/framework symbols with `dlsym`. Host module loading executes rewritten local game code; it is not an internet plugin downloader. Vendored codec/graphics sources are compiled locally; not all algorithms received a line-by-line security audit.
- Python `exec` matches in tests isolate local AST functions; game-profile Python files are local executable source and must be trusted. The build scripts use local developer tools; no unreviewed curl-to-shell installer was used. Official dependency installation is a separate networked phase.
- Implicit Git/SourceLink metadata is disabled for reproducibility and to avoid embedding owner remote URLs or untracked local sources in PDB files. All published .NET artifacts matched in a second source path on the same Mac/SDK.
- `.NET` projects/imports were inspected before compilation. The active graph has no third-party MSBuild hooks or analyzer packages. The eliminated Humanizer package did contain analyzer DLLs and a transitive target; those were detected before compilation and eliminated with the unused dependency.
- `prod.keys` is read in `nx_extract` only for local content processing. No key copying into the iOS app was identified. NSZ conversion uses a local temporary `keys.txt` symlink for the converter. No private keys or game files were supplied to this audit or used in tests.

## iOS data and backups

Saves remain under `Documents/save`; they stay available through Files and eligible for normal user-configured backups. `Documents/romfs`, `temp`, `env.txt`, `log.txt` and `log.prev.txt` are marked excluded from backup when present. Log exclusion is applied after rotation/creation too. These Foundation calls compiled successfully; their on-device behavior was not tested here. Files created later by the user may acquire backup attributes only on the next launch.

To collect diagnostics locally, put `DM_DIAGNOSTICS=1` into `Documents/env.txt`, reproduce once, then remove that line/disable it. The next ordinary launch removes prior log files. Diagnostic logs can still contain host paths, game information and crash registers; review/redact before sharing. No automatic upload exists in the reviewed source. macOS game logs remain local and opt-out behavior was changed only on iOS; the Mac launcher's environment-value leak was fixed.

The prepared Xcode path requests only the existing Increased Memory Limit entitlement by default, with optional user-selected entitlements. Unsigned IPA packing does not sign/install anything. No provisioning identity, signing behavior, device setup or unrelated app capability was modified.

## Validation and remaining limits

See [test results](docs/security/test-results.md). Local logs live in ignored `.tools/logs` and must not be published. Early permission/toolchain-cache failures were distinguished from final successful reruns. Source rebuild validation used synthetic shaders/modules, never downloaded commercial games or keys.

The successful .NET build and synthetic shader checks were run with outgoing IP connections denied by `sandbox-exec`. This proves those exercised paths can complete without successful outgoing IP connections under that profile; it is **not** a packet capture of the iOS app, all operating-system activity, or real-game execution. No physical iPhone/iPad, signing, installation, full game rendering, malformed game archive fuzzing or on-device backup validation occurred. Guest native code, codecs, opaque LibHac and developer tools remain trust boundaries.

The secret/history guard inspected reachable Git objects for selected secret contents and forbidden data filenames without outputting matches. A clean result is not a guarantee about every arbitrary byte or future upload. The unpublished local commit was replaced with a sanitized commit before its first public push, so earlier private-path documentation is absent from the published ancestry. Existing upstream history and attribution are preserved.
