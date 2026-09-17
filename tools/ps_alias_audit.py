# ps_alias_audit.py - audit pet.ps1 for the PowerShell variable-aliasing traps
#
#   "C:\...\python_embeded\python.exe" -X utf8 tools\ps_alias_audit.py pet.ps1
#
# Why: PowerShell variable names are CASE-INSENSITIVE, so $el and $script:El are
# the SAME variable.  Three separate bugs in this project came from a local
# colliding with a script-level collection:
#   $el = $script:El[$k]      -> replaced the hashtable with an element
#   $l  = ... $L = ...        -> the accumulator became the per-item value
#   $win = $script:Win[$k]    -> destroyed the window map
# Any hit in section (a) or (b) below must be renamed before shipping.
import io, re, collections, sys

path = sys.argv[1] if len(sys.argv) > 1 else 'pet.ps1'
lines = io.open(path, encoding='utf-8').read().split('\n')
pat = re.compile(r'\$(script:)?([A-Za-z_][A-Za-z0-9_]*)')
sites = collections.defaultdict(list)      # lower name -> [(line, prefixed, text)]
spellings = collections.defaultdict(set)   # lower name -> {spellings}

for i, ln in enumerate(lines, 1):
    s = ln.strip()
    if s.startswith('#'):
        continue
    for m in pat.finditer(ln):
        nm = m.group(2)
        low = nm.lower()
        spellings[low].add(('script:' if m.group(1) else '') + nm)
        if re.match(r'\s*(\+?=)(?!=)', ln[m.end():]):
            sites[low].append((i, bool(m.group(1)), s[:100]))

print('=== (a) assigned BOTH as $script:x and bare $x (aliasing) ===')
cross = [n for n, v in sites.items() if any(p for _, p, _ in v) and any(not p for _, p, _ in v)]
if not cross:
    print('  none')
for n in sorted(cross):
    print('  %s' % n)
    for l, p, t in sites[n][:8]:
        print('     %5d %-8s %s' % (l, 'script:' if p else '', t))

print('')
print('=== (b) same variable written with different spelling (case trap) ===')
bad = {n: v for n, v in spellings.items() if len(v) > 1}
if not bad:
    print('  none')
for n in sorted(bad):
    print('  %-12s spellings=%s' % (n, sorted(bad[n])))

print('')
print('=== (c) short names assigned 2+ times (manual review) ===')
found = False
for n in sorted(sites):
    v = sites[n]
    if len(n) <= 2 and len(v) >= 2:
        found = True
        print('  %-4s x%d lines=%s' % (n, len(v), ','.join(str(l) for l, _, _ in v[:12])))
if not found:
    print('  none')
