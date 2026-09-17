import io, re, sys

# audit: flag functions INVOKED as bare commands before their definition line
# (PowerShell resolves functions at execution time, top-down - a helper defined
# after its first runtime call silently returns $null mid-script)
path = sys.argv[1]
lines = io.open(path, encoding='utf-8').read().split('\n')
defs = {}   # name -> first definition line
for i, ln in enumerate(lines, 1):
    m = re.match(r'\s*(?:function\s+)([A-Za-z_][A-Za-z0-9_-]*)', ln)
    if m:
        defs.setdefault(m.group(1).lower(), i)

# PS built-ins / cmdlets / .NET calls are ignored via heuristics:
# a bare call looks like ^name or | name at statement start
known = set(k.lower() for k in defs)
builtinish = re.compile(
    r'^(if|foreach|for|while|switch|try|catch|finally|param|function|return|throw|break|continue)\b', re.I)
callre = re.compile(r'(?:^|\||;|\$\(\s*)([A-Za-z][A-Za-z0-9_-]*)(\s|$|\()')

problems = []
for i, ln in enumerate(lines, 1):
    s = ln.strip()
    if not s or s.startswith('#'):
        continue
    if builtinish.match(s):
        continue
    # only statement-leading positions (approximation: start, after ; | { )
    for m in re.finditer(r'(?:^|[;{|])\s*([A-Za-z][A-Za-z0-9_-]*)\s', s + ' '):
        name = m.group(1).lower()
        if name in known and name not in ('function',):
            dline = defs[name]
            if dline > i:
                # definition comes later: OK only if this call is inside a
                # function/scriptblock that cannot run before the definition.
                # conservative flag for manual review:
                problems.append((name, i, dline, s[:80]))

print('=== bare calls that precede their definition (manual review) ===')
if not problems:
    print('  none')
for name, i, d, s in problems:
    print('  %-22s called@%d defined@%d | %s' % (name, i, d, s))
