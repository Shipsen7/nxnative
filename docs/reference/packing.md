# Packing

## Build tools

### GUI stage rows repeat after the pipeline starts a new plan

- **Symptom:** decompression or a provisional survey is followed by duplicate stage identities or a footer counter larger than the current plan's total.
- **Cause:** `PROG.plan` restarts the script's stage counter, while the GUI previously appended every plan to one list keyed by that counter and displayed the history length.
- **Fix:** `BuildProgress` replaces the displayed plan when the counter restarts and stores the current pipeline index separately. The footer uses that index; the row identities remain unique. Regression tests exercise repeated plan restarts and a skipped stage event.
- **Found on:** synthetic decompression/survey event sequences during the local GUI PR review; no game files required.

### Direct GUI iOS builds cannot start the SwiftUI State macro

- **Symptom:** the iOS compiler reports `SwiftUIMacros.StateMacro` unavailable or a malformed plugin response, preceded by `sandbox_apply: Operation not permitted`.
- **Cause:** the current SDK resolves `@State` to an external macro. Its compiler plugin tries to enter a second process sandbox inside the GUI's outbound-IP restriction; macOS rejects that nesting.
- **Fix:** the launcher's memory display uses the public `State<Int>` DynamicProperty storage and its nonmutating wrapped-value accessor directly. State updates and the existing memory refresh are preserved without launching that macro. Neither the outbound-IP restriction nor the compiler's plugin sandbox is disabled. A regression typechecks the production launcher under the same network policy, and the complete synthetic iOS app build checks Swift compilation/linking and resource staging.
- **Found on:** the synthetic production iOS build under the GUI's network policy, Xcode 27.2, during the local GUI PR review. The Xcode project preparation route itself had already passed user testing.

### Homebrew .NET is on PATH but apphosts cannot find the runtime

- **Symptom:** the first extraction stops with `nx_extract exit code 131` and `.NET location: Not found`, even though `dotnet` is on `PATH`. The shader translator can fail the same way.
- **Cause:** standalone .NET apphosts search runtime roots and registered installations, not `PATH` ([.NET runtime discovery](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables#dotnet_root-dotnet_rootx86-dotnet_root_x86-dotnet_root_x64)). Homebrew's formula installs the runtime under `libexec` and its `bin/dotnet` can be a wrapper that sets `DOTNET_ROOT` only for its own child ([Homebrew caveat](https://formulae.brew.sh/formula/dotnet)). Resolving that wrapper's symlink gives `bin`, not the runtime root.
- **Fix:** `scripts/build_ipa_from_nsp.py` `configure_dotnet` derives the root from the `Microsoft.NETCore.App` entry in `dotnet --list-runtimes`, using the build's environment, before any extraction or survey. It exports `DOTNET_ROOT` both to that environment and to `os.environ`, for tools launched with an explicit environment and those that inherit it. Caller-supplied roots, including architecture-specific overrides, retain precedence. A failed or malformed probe leaves the environment unchanged rather than guessing the wrapper's directory.
- **Found on:** [Balatro](../../dm/games/0100CD801CE5E000/README.md), first extraction with Homebrew .NET ([PR #284](https://github.com/seedds/nxnative/pull/284)). Applies to every game's build on that installation setup.

## IPA archives

### Unsigned exports contain local build paths in debug metadata

- **Symptom:** an unsigned IPA's Mach-O executable contains the builder's absolute source and object-file paths, including the local home directory.
- **Cause:** Release builds using `DEBUG_INFORMATION_FORMAT = dwarf` retain N_OSO debug-map entries in the linked executable; packaging the app also packages those entries.
- **Fix:** after the unsigned app build, `build_ipa.sh` runs `xcrun strip -S` before packing. This removes debugging symbols while preserving runtime symbols and populated code/data sections. The `--prepare-xcode` route exits before this step, preserving Xcode development/debugging products. On a copy of the affected executable, all 60 populated Mach-O sections remained byte-identical and the home path disappeared. The original IPA was preserved.
- **Found on:** [Pokemon Shield](../../dm/games/01008DB008C2C000/README.md), local GUI/export privacy validation. Applies to unsigned exports generally; device runtime validation remains separate.

### A streamed file changes size and the IPA fails its CRC check

- **Symptom:** packing succeeds, but `unzip -t` or Python's `ZipFile.testzip()` reports a bad CRC for a large deflated file.
- **Cause:** `pack_ipa.py` wrote the uncompressed size collected before reading. Its streaming check compared the output size only for stored files, so a compressible file that grew or shrank still published an archive with the old size.
- **Fix:** count uncompressed bytes as they are read and compare them with the listed size before completing either streamed method. A mismatch stops the pack and removes the partial archive, preserving the previous IPA and its reuse index. Regression tests cover growth and shrinkage with both deflate and store.
- **Found on:** synthetic IPA inputs while reviewing [PR #279](https://github.com/seedds/nxnative/pull/279); no game files required.

## Compressed inputs

### NSZ decompression rejects `--keys`

- **Symptom:** `decompress NSZ` stops immediately with `nsz: error: unrecognized arguments: --keys …`.
- **Cause:** `nsz` 4.6.1 has no `--keys` argument. It loads `keys.txt` beside `sys.argv[0]`, or falls back to `~/.switch/prod.keys`, while importing its modules, before parsing arguments ([4.6.1 key loader](https://github.com/nicoboss/nsz/blob/4.6.1/nsz/nut/Keys.py)). Newer upstream code supports `--keys`; staging `keys.txt` also supports 4.6.1.
- **Fix:** `scripts/build_ipa_from_nsp.py` `decompress_nsz` links the file selected by `-k` as `keys.txt` in the conversion's temporary folder and runs `nsz -D` there, with `sys.argv[0]` set to `nsz` before import. Input and output paths are absolute. The temporary folder and link are removed on success or failure; the user's default keys are untouched.
- **Found on:** [Super Mario Odyssey](../../dm/games/0100000000010000/README.md), converting its v0 NSZ. Applies to NSZ and XCZ inputs for every game.
