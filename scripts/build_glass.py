import re,sys
P=':root[data-theme="dark"]:not(.phone)'
src=open(sys.argv[1]).read()
out=re.sub(r'(^|[\s,{(])G(?=[ {])', lambda m: m.group(1)+P, src, flags=re.M)
out=out.replace(P+'{', P+' {',1)
open(sys.argv[2],'w').write(out)
