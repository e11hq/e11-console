# Expands the scope letters in a theme source file: G = both themes, D = dark, L = light (desktop only).
import re, sys
S = {'G': ':root:not(.phone)', 'D': ':root[data-theme="dark"]:not(.phone)', 'L': ':root[data-theme="light"]:not(.phone)'}
src = open(sys.argv[1]).read()
out = re.sub(r'(^|[\s,{(])([GDL])(?=[ {])', lambda m: m.group(1) + S[m.group(2)], src, flags=re.M)
out = re.sub(r'(:not\(\.phone\))\{', r'\1 {', out)
open(sys.argv[2], 'w').write(out)
