# .NET dependency provenance

Audit date: 2026-10-26. Base: `40b643bbe68861d171cb1a2733a953aa739f9ac1`.

## Current build

| Component | Origin and version | License | Treatment |
|---|---|---|---|
| dmsh_xlate | `dm/gfx/tools/dmsh_xlate`, base commit plus local changes | Repository license; incorporated work retains its notices | Built locally |
| Ryujinx.Graphics.Shader | Vendored Ryujinx 1.3.2 subset plus documented NXNative patches | MIT, `dm/third_party/ryujinx/LICENSE.txt` | Built locally; translation algorithms retained |
| Ryujinx.Common | Same vendored subset | MIT | Compile only `IArray.cs`, `StructArrayHelpers.cs`, `BitUtils.cs`, `BitfieldExtensions.cs`, `ObjectPool.cs` |
| Spv.Generator | Same vendored subset | MIT | Built locally |
| nx_extract | `dm/tools/nx_extract` | Repository license | Built locally; key-parser diagnostics suppressed |
| LibHac | NuGet.org `LibHac` **0.19.0**, by Alex Barney | MIT, package metadata | Remaining binary dependency; locked hash and NuGet repository signature verified |
| .NET SDK/runtime | Installed Microsoft SDK **10.0.201**, selected by `global.json` | Microsoft distribution includes licenses/notices | Trusted development tool, not rebuilt in this audit |

The upstream vendored README identifies Ryujinx 1.3.2 but does not supply an independently verifiable import commit. Its source tree is reviewable and covered by the local manifest. Preserve its MIT notice. The only local shader-source adaptation for dependency reduction reads the existing embedded GLSL helpers directly with .NET streams; it avoids the unrelated Common stream/package stack.

LibHac's official package metadata names source commit `cd4004af194a51712812c680f0a028ba9152c0f8` at `https://github.com/Thealexbarney/LibHac.git`. `git ls-remote` returned **Repository not found** on the audit date. No unverified mirror was substituted. Obtain an authenticated official source release at that revision before claiming a full source rebuild. Until then the auditable alternative is the signed original NuGet package or avoiding extraction with this tool. No LibHac source audit or binary malware certification is claimed.

The sole active NuGet package has no transitive dependencies on net10.0. Its canonical content hash is recorded in `dm/tools/nx_extract/packages.lock.json`. NuGet verified its repository signature from NuGet.org/Microsoft, certificate SHA-256 `5A2901D6ADA3D18260B9C6DFE2133C95D74B9EEF6AE0E5DC334C8454D1477DF4` (timestamped signature; certificate validity dates alone are not the verification result). Its archive contains no MSBuild targets/props, PowerShell installation scripts, executable tools or analyzers. NuGet audit warnings are treated as errors, including failures to obtain audit data.

`Directory.Packages.props` under the vendored tree retains upstream version declarations for many emulator modules. They are **not active dependencies** of these projects. The committed lockfiles and actual published `.deps.json` define the current graph, not that unused declaration list.

## Removed original artifacts

The full file-by-file static inventory (61 files, paths, sizes, SHA-256 values and the shipped `.deps.json` library records) is [original-binaries.json](docs/security/original-binaries.json). It covers every PE/.NET and native executable detected by magic bytes in the original tracked tree. The old artifacts were never executed. Compiler origin, exact source correspondence and integrity of their embedded code remain unverified; metadata claims are distinguished from proof.

| Original binary/group | Claimed version/source | License evidence | Outcome |
|---|---|---|---|
| `dmsh_xlate` native universal apphost and `dmsh_xlate.dll` | Local .NET application 1.0.0, shipped deps metadata | Project / Microsoft apphost notices | Removed; locally published apphost and assembly |
| `Ryujinx.Common.dll`, `Ryujinx.Graphics.Shader.dll`, `Spv.Generator.dll` | Assembly/project 1.0.0; vendored source identified as Ryujinx 1.3.2 | Vendored MIT notice | Removed; source-built replacements |
| `Gommon.dll` | Gommon 2.8.1.2, package repository `GreemDev/Gommon`, commit `222084874ac473e02f27faeb10e540f926702976` | MIT in official package `contentFiles/any/net9.0/LICENSE` | Dependency eliminated |
| `Humanizer.dll` and **51** localized `Humanizer.resources.dll` files | Humanizer/Core 3.0.10, `Humanizr/Humanizer` | MIT in official package metadata | Dependency eliminated, including analyzer/targets |
| `Microsoft.IO.RecyclableMemoryStream.dll` | 3.0.1, Microsoft package | MIT in official package metadata | Dependency eliminated |
| `MsgPack.dll` | MsgPack.Cli 1.0.1, `msgpack/msgpack-cli` | Apache-2.0 in package metadata | Dependency eliminated |
| `System.CodeDom.dll` | 4.4.0, Microsoft/.NET package, formerly transitive via MsgPack | Package license reference / .NET notices | Dependency eliminated |

Versions here come from the original dependency manifest, not execution or decompilation of the old assemblies. Package metadata was retrieved from nuget.org without executing package code. Source was not present for these eliminated NuGet libraries; rebuilding unused libraries provides no runtime benefit. None of them appears in the current shader output. Historical binaries remain in upstream Git history; history was not rewritten. Normal builds cannot reach them through a fallback path.

## Other build components

Vendored libvpx, stb_vorbis, Vulkan headers, FLIP, and the remaining third-party sources keep their existing licenses under `dm/third_party`. Static magic-byte inventory found no additional tracked native programs outside the removed apphost. This does not prove the absence of obfuscated content or audit every codec algorithm. Official Homebrew bottles installed for validation: XcodeGen 2.46.0, SPIRV-Cross 1.4.363.0, SPIRV-Tools 1.4.363.0, Python 3.14.9. Python test packages: lz4 4.4.5, capstone 5.0.6, fonttools 4.60.1 from PyPI wheels. Xcode 27.1 and Apple's Metal Toolchain 27A266a were used. These external development tools are outside the source-rebuild claim.
