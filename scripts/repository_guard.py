#!/usr/bin/env python3
"""Reject private data in Git, without ever displaying matching contents.

Default: inspect the index. --history additionally scans every reachable object.
--approved-remote verifies the explicitly configured GitHub destination and
visibility. This guard is defense in depth, not a complete secret detector.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
FORBIDDEN = re.compile(r'(^|/)(prod\.keys|title\.keys|keys\.txt|\.env(?:\..*)?|env\.txt|credentials\.json|secrets\.json)$|\.(?:nsp|nsz|xci|xcz|nca|tik|p12|pfx|pem|mobileprovision)$|(^|/)(romfs|exefs|extracted|extract|save)/', re.I)
SECRETS = [
    re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'),
    re.compile(rb'(?im)^\s*(?:master_key_[0-9a-f]+|key_area_key_\w+|header_key|titlekek_[0-9a-f]+|device_key)\s*=\s*[0-9a-f]{32,}'),
    re.compile(rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[0-9A-Z]{16})\b'),
]


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)


def scan(history=False):
    objects = {}
    bad = []
    for entry in git('ls-files', '--stage', '-z').split(b'\0'):
        if not entry:
            continue
        meta, path = entry.split(b'\t', 1)
        oid = meta.split()[1].decode()
        name = path.decode(errors='replace')
        if FORBIDDEN.search(name):
            bad.append('Forbidden private-data path in index: ' + name)
        objects[oid] = name
    if history:
        for entry in git('rev-list', '--objects', '--all').splitlines():
            oid, _, path = entry.partition(b' ')
            name = path.decode(errors='replace')
            if name and FORBIDDEN.search(name):
                bad.append('Forbidden private-data path in history: ' + name)
            objects.setdefault(oid.decode(), name or oid.decode())
    proc = subprocess.Popen(['git', 'cat-file', '--batch'], cwd=REPO,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        for oid, name in objects.items():
            proc.stdin.write((oid + '\n').encode()); proc.stdin.flush()
            header = proc.stdout.readline().split()
            if len(header) != 3:
                raise RuntimeError('Cannot inspect Git object')
            size = int(header[2]); content = proc.stdout.read(size)
            if len(content) != size or proc.stdout.read(1) != b'\n':
                raise RuntimeError('Incomplete Git object inspection')
            if header[1] == b'blob' and any(pattern.search(content) for pattern in SECRETS):
                bad.append('Potential secret in Git object (contents redacted): ' + name)
    finally:
        proc.stdin.close(); proc.stdout.close(); proc.wait()
    return sorted(set(bad)), len(objects)


def approved_remote(push_url=None, require_private=False):
    expected = git('config', '--get', 'nxnative.approvedRepository').decode().strip()
    visibility = git('config', '--get', 'nxnative.approvedVisibility').decode().strip()
    if not re.fullmatch(r'Shipsen7/[A-Za-z0-9_.-]+', expected):
        raise RuntimeError('No approved owner repository configured')
    if visibility not in ('public', 'private') or (require_private and visibility != 'private'):
        raise RuntimeError('No matching repository visibility approval configured')
    push = git('remote', 'get-url', '--push', 'origin').decode().strip()
    if push not in (f'https://github.com/{expected}.git', f'git@github.com:{expected}.git'):
        raise RuntimeError('Push destination is not the approved owner repository')
    if push_url is not None and push_url != push:
        raise RuntimeError('Actual push URL differs from the approved origin')
    result = subprocess.check_output(['gh', 'repo', 'view', expected, '--json', 'nameWithOwner,isPrivate,isFork'], cwd=REPO)
    info = json.loads(result)
    if info['nameWithOwner'] != expected or info['isPrivate'] != (visibility == 'private'):
        raise RuntimeError('GitHub destination or visibility differs from the approval')
    if visibility == 'private' and info['isFork']:
        raise RuntimeError('A private destination must be independent of a fork network')


def private_remote():
    # Retain the old stricter CLI mode; it never authorizes a public push.
    approved_remote(require_private=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--history', action='store_true')
    parser.add_argument('--private-remote', action='store_true')
    parser.add_argument('--approved-remote', action='store_true')
    parser.add_argument('--push-url', help='actual URL supplied by the pre-push hook')
    args = parser.parse_args()
    if args.push_url is not None and not args.approved_remote:
        parser.error('--push-url requires --approved-remote')
    if args.approved_remote:
        approved_remote(args.push_url)
    if args.private_remote:
        private_remote()
    bad, count = scan(args.history)
    if bad:
        for message in bad:
            print('[RED] ' + message, file=sys.stderr)
        return 1
    print(f'Repository guard passed: {count} objects inspected; no matching private data.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as e:
        sys.exit(f'[RED] Repository guard could not complete: {type(e).__name__}')
