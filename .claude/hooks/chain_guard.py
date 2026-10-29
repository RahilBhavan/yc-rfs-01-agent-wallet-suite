#!/usr/bin/env python3
"""PreToolUse hook for Bash. Exit 2 with the fix on stderr to block.

Builds are testnet or local only. Blocks (a) a command that sends a transaction or deploys
without an explicit local or testnet RPC, and (b) a raw private key in the command.
Anvil's well-known first key is allowed. Any internal error allows the command.
The command parser follows the hub's guard_bash.py.
"""
import json
import os
import re
import shlex
import sys
from urllib.parse import urlparse

SEPARATORS = {';', '&&', '||', '|', '|&', '&', '(', ')', '{', '}'}
REDIRECTS = {'>', '>>', '<', '<<', '<<<', '>&', '&>', '&>>', '>|', '<&'}
WRAPPERS = {'env', 'nohup', 'setsid', 'time', 'sudo', 'nice', 'exec', 'command', 'stdbuf', 'timeout', 'xargs', 'watch'}
WRAPPER_VALUE_OPTS = {'-I', '-n', '-P', '-s', '-L', '-d', '-k', '-s', '-u'}
SHELLS = {'bash', 'sh', 'zsh', 'dash'}
LOCAL_HOSTS = {'localhost', '127.0.0.1', '0.0.0.0', '::1'}
TESTNET = re.compile(r'sepolia|holesky|hoodi|testnet', re.I)
KEYS = [re.compile(r"--private-keys?[=\s]+[\"']?(?:0x)?([0-9a-fA-F]{64})\b"),
        re.compile(r"\b\w*KEY\w*=[\"']?(?:0x)?([0-9a-fA-F]{64})\b", re.I)]
ANVIL_KEY = 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?[ \t]*(?:'([^'\n]+)'|\"([^\"\n]+)\"|\\?([^\s;&|<>()'\"]+))")

MSG_RPC = ('Blocked: builds are testnet or local only. Pass an explicit local or testnet RPC with --rpc-url '
           '(http://127.0.0.1:8545 for anvil, a Base Sepolia URL, or a foundry.toml alias such as base_sepolia).')
MSG_KEY = ('Blocked: no raw private keys in commands. Use anvil\'s default account locally, '
           'or a keystore (--account <name>) for testnet.')


def strip_heredocs(cmd):
    out, lines = [], iter(cmd.split('\n'))
    for line in lines:
        words = [next(w for w in m.groups() if w is not None) for m in HEREDOC.finditer(line)]
        out.append(HEREDOC.sub('<< heredoc', line))
        for word in words:
            for body in lines:
                if body.strip() == word:
                    break
    return ' ; '.join(out)


def segments(cmd):
    lex = shlex.shlex(strip_heredocs(re.sub(r'\\\r?\n', ' ', cmd)).replace('`', ' ; '), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ''
    segs, cur, skip = [], [], False
    for tok in lex:
        if skip:
            skip = False
            continue
        if tok in REDIRECTS or re.fullmatch(r'\d*[<>]+&?', tok):
            skip = not tok.endswith('&') or tok in ('>&', '<&')
            continue
        if tok in SEPARATORS or set(tok) <= set(';&|()'):
            if cur:
                segs.append(cur)
            cur = []
        else:
            cur.append(tok.lstrip('$'))
    if cur:
        segs.append(cur)
    return [s for s in segs if any(s)]


def split_head(seg):
    env, i = {}, 0
    while i < len(seg):
        t = seg[i]
        m = re.fullmatch(r'([A-Za-z_]\w*)=(.*)', t)
        prev = os.path.basename(seg[i - 1]) if i > 0 else ''
        if m:
            env[m.group(1)] = m.group(2)
        elif os.path.basename(t) in WRAPPERS or (i > 0 and re.fullmatch(r'[\d.]+[smhd]?', t)):
            pass
        elif i > 0 and t.startswith('-') and (prev in WRAPPERS or seg[i - 1].startswith('-')):
            pass
        elif i > 0 and seg[i - 1] in WRAPPER_VALUE_OPTS:
            pass
        else:
            break
        i += 1
    return env, seg[i:]


def opt_values(args, names):
    out = []
    for i, a in enumerate(args):
        for n in names:
            if a == n and i + 1 < len(args):
                out.append(args[i + 1])
            elif a.startswith(n + '=') and n.startswith('--'):
                out.append(a.split('=', 1)[1])
    return out


def is_send(args):
    head, rest = os.path.basename(args[0]), args[1:]
    if head == 'cast':
        return rest[:1] in (['send'], ['publish']) or (rest[:1] == ['rpc'] and rest[1:2] and rest[1].startswith('eth_send'))
    if head == 'forge':
        return rest[:1] == ['create'] or (rest[:1] == ['script'] and '--broadcast' in rest)
    return False


def allowed_rpc(url):
    if url.startswith('$') or not re.search(r'[:/]', url):
        return bool(TESTNET.search(url)) and 'MAINNET' not in url.upper()
    host = (urlparse(url if '://' in url else 'http://' + url).hostname or '').lower()
    return host in LOCAL_HOSTS or (bool(TESTNET.search(host)) and 'mainnet' not in host)


def check(cmd, depth=0):
    for pattern in KEYS:
        for m in pattern.finditer(cmd):
            if m.group(1).lower() != ANVIL_KEY:
                return MSG_KEY
    for seg in segments(cmd):
        env, args = split_head(seg)
        if not args:
            continue
        if os.path.basename(args[0]) in SHELLS and '-c' in args and depth < 3:
            i = args.index('-c')
            if i + 1 < len(args) and (r := check(args[i + 1], depth + 1)):
                return r
            continue
        if is_send(args):
            urls = opt_values(args, ['--rpc-url', '--fork-url', '-r']) or ([env['ETH_RPC_URL']] if 'ETH_RPC_URL' in env else [])
            if not urls or not all(allowed_rpc(u) for u in urls):
                return MSG_RPC
    return None


def main():
    try:
        cmd = json.load(sys.stdin).get('tool_input', {}).get('command', '')
        msg = check(cmd)
    except Exception:
        return 0
    if msg:
        print(msg, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
