# Validation results — 2026-10-26

All inputs were synthetic. No commercial game files, Nintendo keys or signing identity were used. Logs are retained locally under ignored `.tools/logs`.

| Check | Result | Evidence / limitation |
|---|---|---|
| Source .NET build | PASS | dmsh_xlate + three vendored projects and nx_extract compiled/published; no original binaries executed |
| Locked restore, NuGet signatures and vulnerability audit | PASS | LibHac 0.19.0 only; no reported known vulnerabilities; [audit output](nuget-audit.json), [provenance](libhac-provenance.json). No source/binary malware certification implied |
| Rebuild in another source path | PASS | All **8 translator** and **6 extractor** published artifact hashes identical, including apphosts/DLLs/PDBs, on the same Mac and SDK after disabling implicit Git/SourceLink metadata. [Comparison](reproducibility.json). Cross-SDK/OS/architecture identity not claimed |
| Full Python collection | PASS after correction | **41 files, 328 tests, 9 skipped** (optional Unicorn ARM64 execution dependency). [Per-file results](python-test-results.json). One chain symlink/header-path regression was fixed and its 12 tests rerun successfully |
| Synthetic shader integration | PASS | 22 tests, initially one optional native geometry test skipped. SPIR-V validation, SPIRV-Cross, Metal compile/link for both macOS and iPhone SDKs; **three returning-atomic GPU result/sentinel checks** passed |
| Native geometry integration | PASS | Built `t_geometry`; subsequent full collection ran all 10 geometry tests with `DM_TEST_GEOMETRY` set, including native bounds/compaction and passthrough kernels; none skipped |
| Final translator artifact retest | PASS | All 12 image-atomic tests rerun against final metadata-stable artifacts, including synthetic translation and SPIR-V validation |
| Security regressions | PASS | 3 tests for changed/missing/extra/outside tool artifacts, source digest changes and staged private-path/secret rejection without exposing values; included in collection count |
| Key parser error privacy | PASS | Synthetic nonexistent private key path omitted from output; fixed message and exit 2. [Result](key-privacy-test.json) |
| Host unit suite | PASS | `make -C dm/host/tests GAME=010015100B514000 -j3 run`; after the watchdog spawn fix the affected `t_altstack` test was rebuilt and passed again |
| iOS source check | PASS | All **178** iOS host/app translation units compiled, zero failures; Swift is instead covered by the linked app build |
| Production Xcode synthetic smoke | PASS | Generated project, compiled Objective-C/Swift/C/assembly, linked unsigned iPhone app, checked staged synthetic resources; no device launch/sign/install |
| Synthetic IPA packing | PASS | Production packer used on the unsigned synthetic app; ZIP CRC/structure, linked executable and absence of signing/provisioning material checked |
| Repository secret/history guard | PASS | Reachable history and staged tree scanned without outputting contents; selected key/token/path patterns absent. Scanner limitations described in [audit](../../SECURITY_AUDIT.md) |
| Fingerprint/cache check | PASS | Updated only after synthetic translator validation; all .NET inputs and strict compiler wrapper enter chain version; missing/mismatched tools rejected |

The successful isolated .NET builds, synthetic shader integration and full Python collection denied outgoing IP connections. That is a test constraint, not a full network capture or proof about all possible runtime activity. Package acquisition/auditing and official tool installation were separate networked steps.

Early attempts without access to macOS build/audio services failed, then passed with the required services accessible. Apple's Metal toolchain was installed through Xcode, and `xcrun --kill-cache` resolved its stale tool lookup. No source security exception or signature/audit bypass was added for those environment failures. The first reproducibility comparison found Git-dependent PDB/assembly metadata; the final comparison passes after removing that metadata.

Not tested: a playable game, physical iPhone/iPad, device backup exclusion at runtime, signing/installation, exhaustive fuzzing of untrusted game formats, or full LibHac source reconstruction. The unsigned fixture is not a playable NXNative game.

## Public publication review

The owner approved publication to the existing public fork. The outgoing commit was sanitized before its first push, including documentation and Git author/committer metadata. The prior local commit containing a workstation path is excluded from the published ancestry. Only the public GitHub handle and noreply identity are used; upstream authors and license notices are preserved.

The updated destination guard accepts an explicitly approved public fork and rejects a changed repository URL, visibility mismatch or missing approval. All **7 security-guard tests and 4 documentation tests** passed in this review. These are additional targeted reruns; the earlier full-collection counts above remain the recorded build-validation baseline. The .NET artifact manifests and strict shader fingerprint check still passed without a rebuild.

Publication checks cover the indexed files and reachable history for secret/key/game-file patterns, and the outgoing source/metadata for workstation paths and personal identifiers. Ignored local logs, dependency caches, builds, game data and signing material are not part of the push. Scan results are defense in depth, not a guarantee against arbitrary undetectable secrets.

An additional Gitleaks 8.30.1 scan found **zero secrets in the outgoing commit**. The full tracked source snapshot produced five generic-key matches: four shader/cache identifiers in graphics code/tests and one prose comment about the decoder API. Each was inspected and confirmed unchanged from the public upstream baseline; no credential was identified. No blanket exclusion rule was added. See the [publication review](publication-review.json) for the classifications.
