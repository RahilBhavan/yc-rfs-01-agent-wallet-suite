#!/usr/bin/env python3
"""Stop hook. Blocks once when the final message claims tests pass or work is
verified but the turn ran no test or check command. Any error allows the stop."""
import json
import re
import sys

CLAIM = re.compile(
    r'\b(?:all\s+(?:the\s+)?tests?\s+(?:pass(?:ed|es|ing)?|are\s+green)|'
    r'tests?\s+(?:all\s+)?(?:pass(?:ed|es|ing)?|are\s+(?:passing|green))|'
    r'(?:checks?|suite|ci|build)\s+(?:is\s+|are\s+|all\s+)?(?:pass(?:ed|es|ing)?|green)|'
    r'all\s+(?:\w+\s+)?passing|verified|(?:now|still|is|are)\s+passing|all\s+green|tests?\s+green)\b', re.I)
LABEL = re.compile(
    r"\b(?:not|un-?verified|never|n't|cannot|can't|couldn't|could\s+not|unable|unverified|"
    r"haven't|hasn't|didn't|did\s+not|yet\s+to|without)\b", re.I)
CHECK_CMD = re.compile(
    r'\b(?:forge\s+(?:test|coverage)|unittest|pytest|py\.test|tox|nox|npm\s+(?:run\s+)?(?:test|check|lint|typecheck)|'
    r'(?:pnpm|yarn|bun)\s+(?:run\s+)?(?:test|check|lint|typecheck)|cargo\s+(?:test|check|clippy)|'
    r'go\s+(?:test|vet)|make\s+(?:test|check|reproduce)|node\s+--test|tsc|ruff|mypy|jest|vitest)\b|'
    r'\b(?:verify|check)[\w.-]*\.(?:py|sh|mjs|js)\b|\bcheck_\w+|\bverify[\w-]*\b|doctor\b', re.I)


def blocks(path):
    out = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            try:
                out.append(json.loads(line))
            except ValueError:
                continue
    return out


def is_real_user(e):
    if e.get('type') != 'user' or e.get('isMeta') or e.get('isSidechain'):
        return False
    c = (e.get('message') or {}).get('content')
    if isinstance(c, str):
        return True
    return isinstance(c, list) and any(b.get('type') == 'text' for b in c) and \
        not any(b.get('type') == 'tool_result' for b in c)


def final_turn(entries):
    start = max((i for i, e in enumerate(entries) if is_real_user(e)), default=-1)
    return [e for e in entries[start + 1:] if e.get('type') == 'assistant' and not e.get('isSidechain')]


def last_text(turn):
    for e in reversed(turn):
        c = (e.get('message') or {}).get('content')
        if isinstance(c, list):
            t = '\n'.join(b.get('text', '') for b in c if b.get('type') == 'text').strip()
            if t:
                return t
    return ''


def ran_check(turn):
    for e in turn:
        c = (e.get('message') or {}).get('content')
        for b in c if isinstance(c, list) else []:
            if b.get('type') == 'tool_use' and b.get('name') == 'Bash' and \
                    CHECK_CMD.search((b.get('input') or {}).get('command') or ''):
                return True
    return False


def unlabelled_claim(text):
    for sentence in re.split(r'(?<=[.!?])\s+|\n+', text):
        if CLAIM.search(sentence) and not LABEL.search(sentence):
            return True
    return False


def main():
    try:
        data = json.load(sys.stdin)
        if data.get('stop_hook_active'):
            return 0
        turn = final_turn(blocks(data['transcript_path']))
        if unlabelled_claim(last_text(turn)) and not ran_check(turn):
            json.dump({'decision': 'block', 'reason': (
                'Your final message claims tests pass or work is verified, but this turn ran no test or '
                'check command. Run the relevant check now (for example python -m unittest, pytest, or the '
                'project verify script) and report the result, or relabel the claim as "not verified" '
                'and say what was not run.')}, sys.stdout)
    except Exception:
        return 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
