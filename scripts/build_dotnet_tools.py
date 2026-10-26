#!/usr/bin/env python3
"""Build and verify local .NET tools; never execute binaries supplied by Git.

Run with --restore for the networked, locked NuGet restore/signature audit.
The default build uses only that cache. --verify checks outputs without running them.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

REPO = Path(__file__).resolve().parents[1]
ROOT = REPO / '.tools'
OUTPUT = ROOT / 'dotnet'
PROJECTS = {
    'dmsh_xlate': REPO / 'dm/gfx/tools/dmsh_xlate/dmsh_xlate.csproj',
    'nx_extract': REPO / 'dm/tools/nx_extract/nx_extract.csproj',
}


def source_files():
    files = [REPO / p for p in ('NuGet.Config', 'global.json', 'Directory.Build.props',
                               'scripts/build_dotnet_tools.py')]
    for folder in ('dm/gfx/tools/dmsh_xlate', 'dm/tools/nx_extract', 'dm/third_party/ryujinx'):
        for p in (REPO / folder).rglob('*'):
            if not p.is_file() or {'bin', 'obj'} & set(p.relative_to(REPO).parts):
                continue
            if p.suffix in ('.cs', '.csproj', '.props', '.targets', '.glsl') or p.name == 'packages.lock.json':
                files.append(p)
    return sorted(set(files))


def source_digest():
    h = hashlib.sha256()
    for p in source_files():
        h.update(p.relative_to(REPO).as_posix().encode() + b'\0' + p.read_bytes() + b'\0')
    return h.hexdigest()


def sha256(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def artifact_hashes(folder):
    # Refuse symlinks: a manifest must describe actual local artifacts.
    if any(p.is_symlink() for p in folder.rglob('*')):
        raise RuntimeError('Symlink in tool output')
    return {p.relative_to(folder).as_posix(): sha256(p)
            for p in sorted(folder.rglob('*')) if p.is_file() and p.name != 'build-manifest.json'}


def verify_tool(name, executable=None):
    folder = OUTPUT / name
    if executable is not None and Path(executable).resolve() != (folder / name).resolve():
        raise RuntimeError('Only the locally built .NET tool is accepted; run scripts/build_dotnet_tools.py')
    try:
        manifest = json.loads((folder / 'build-manifest.json').read_text())
        if manifest['source_sha256'] != source_digest():
            raise RuntimeError('Local .NET tool sources/locks changed; rebuild with scripts/build_dotnet_tools.py')
        if not (folder / name).is_file() or manifest['files'] != artifact_hashes(folder):
            raise RuntimeError('Local .NET artifacts changed or are incomplete; rebuild before use')
    except (OSError, ValueError, KeyError) as e:
        raise RuntimeError('No verified local .NET build; run scripts/build_dotnet_tools.py --restore, then scripts/build_dotnet_tools.py') from e
    return folder / name


def environment():
    env = dict(os.environ, DOTNET_CLI_TELEMETRY_OPTOUT='1', DOTNET_NOLOGO='1',
               DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1', DOTNET_GENERATE_ASPNET_CERTIFICATE='false',
               DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE='true',
               DOTNET_CLI_USE_MSBUILD_SERVER='0', MSBUILDDISABLENODEREUSE='1',
               DOTNET_CLI_HOME=str(ROOT / 'dotnet-home'), NUGET_PACKAGES=str(ROOT / 'nuget'),
               NUGET_HTTP_CACHE_PATH=str(ROOT / 'nuget-http'))
    return env


def package_archives():
    packages = {}
    for p in source_files():
        if p.name != 'packages.lock.json':
            continue
        for framework in json.loads(p.read_text())['dependencies'].values():
            for name, info in framework.items():
                if info['type'].lower() != 'project':
                    packages[(name.lower(), info['resolved'])] = info['contentHash']
    result = []
    for (name, version), expected in sorted(packages.items()):
        p = ROOT / 'nuget' / name / version / f'{name}.{version}.nupkg'
        # NuGet's content hash is recorded during restore; its signed archive's
        # raw bytes may differ from the canonical package hash. NuGet performs
        # the locked content-hash check, and we independently check signatures.
        recorded = json.loads((p.parent / '.nupkg.metadata').read_text())['contentHash']
        if recorded != expected:
            raise RuntimeError(f'NuGet content hash changed: {name} {version}')
        with zipfile.ZipFile(p) as z:
            dangerous = [n for n in z.namelist() if n.lower().endswith(('.props', '.targets', '.ps1', '.exe'))
                         or n.lower().startswith(('analyzers/', 'build/', 'buildtransitive/'))]
            if dangerous:
                raise RuntimeError(f'Package contains unreviewed build hooks/code: {name} {version}: {dangerous}')
        result.append(p)
    return result


def package_cache_hashes(archives):
    """Protect the extracted files MSBuild actually uses, as well as the archive."""
    return {p.relative_to(ROOT).as_posix(): sha256(p)
            for archive in archives for p in sorted(archive.parent.rglob('*')) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--restore', action='store_true', help='locked restore, package hook check and NuGet signature verification (network)')
    parser.add_argument('--verify', action='store_true', help='check all artifact hashes without executing tools')
    args = parser.parse_args()
    ROOT.mkdir(exist_ok=True)
    if args.verify:
        for name in PROJECTS:
            print(f'Verified: {verify_tool(name).relative_to(REPO)}')
        return
    dotnet = shutil.which('dotnet')
    if not dotnet:
        candidate = Path.home() / '.dotnet/dotnet'
        dotnet = str(candidate) if candidate.is_file() else None
    if not dotnet:
        raise RuntimeError('Install the official .NET SDK version in global.json first')
    env = environment()

    def run(*command):
        subprocess.run([str(c) for c in command], cwd=REPO, env=env, check=True, timeout=600)

    sdk = subprocess.check_output([dotnet, '--version'], cwd=REPO, env=env, text=True).strip()
    if args.restore:
        for project in PROJECTS.values():
            run(dotnet, 'restore', project, '--locked-mode', '--configfile', REPO / 'NuGet.Config')
        archives = package_archives()
        for p in archives:
            run(dotnet, 'nuget', 'verify', p, '--all')
        receipt = {'source_sha256': source_digest(), 'sdk': sdk,
                   'packages': package_cache_hashes(archives)}
        (ROOT / 'restore-verified.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print('Locked restore, audit, signatures and package hook checks passed. Run again without --restore to build.')
        return
    receipt = json.loads((ROOT / 'restore-verified.json').read_text())
    if receipt['source_sha256'] != source_digest() or receipt['sdk'] != sdk:
        raise RuntimeError('Sources, locks or SDK changed since the verified restore; run --restore')
    if receipt['packages'] != package_cache_hashes(package_archives()):
        raise RuntimeError('Extracted package cache changed since verification; run --restore')
    OUTPUT.mkdir(exist_ok=True)
    for name, project in PROJECTS.items():
        with tempfile.TemporaryDirectory(prefix=f'{name}-', dir=OUTPUT) as tmp:
            out = Path(tmp) / 'publish'
            run(dotnet, 'publish', project, '--no-restore', '--disable-build-servers', '-c', 'Release', '-o', out,
                '-p:GeneratePackageOnBuild=false', '-p:UseSharedCompilation=false',
                '-p:ContinuousIntegrationBuild=true', f'-p:PathMap={REPO}=/src')
            manifest = {'source_sha256': source_digest(), 'sdk': sdk, 'files': artifact_hashes(out)}
            (out / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
            destination = OUTPUT / name
            if destination.exists():
                shutil.rmtree(destination)
            out.rename(destination)
        print(f'Built and verified: {verify_tool(name).relative_to(REPO)}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as e:
        sys.exit(f'[RED] .NET tool build stopped: {e}')
