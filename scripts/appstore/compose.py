from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os; SP=os.environ.get('OUT', 'appstore-out')
W,H=1320,2868
B='/usr/share/fonts/opentype/inter/'
fb=ImageFont.truetype(B+'Inter-Bold.otf',104); fr=ImageFont.truetype(B+'Inter-Regular.otf',48)
SETS=[('home','Your whole day\nat a glance','Due today, overdue and in review, in one look.',('#5b48d9','#8f7dff')),
 ('review','Approve work\nin a tap','The Creative Director sees every file and approves or asks for changes.',('#0f766e','#2dd4bf')),
 ('comments','Talk it through\non the task','Mentions, pictures and reactions, right where the work is.',('#1d4ed8','#60a5fa')),
 ('task','Every job,\nall in one place','Status, team, dates and CD review on every task.',('#7c2d92','#c084fc')),
 ('clients','Every client’s files,\nalways to hand','Logos, brand guidelines, fonts and final files.',('#c2410c','#fb923c')),
 ('inbox','Never miss\nan update','Comments, mentions and approvals, with notifications.',('#be123c','#fb7185'))]
def grad(a,b):
    ca=[int(a[i:i+2],16) for i in (1,3,5)]; cb=[int(b[i:i+2],16) for i in (1,3,5)]
    g=Image.new('RGB',(1,H))
    for y in range(H):
        t=y/H; g.putpixel((0,y),tuple(int(ca[i]+(cb[i]-ca[i])*t) for i in range(3)))
    return g.resize((W,H))
def rounded(im,r):
    m=Image.new('L',im.size,0); ImageDraw.Draw(m).rounded_rectangle([0,0,im.size[0]-1,im.size[1]-1],r,fill=255); return m
for n,(key,head,sub,(a,b)) in enumerate(SETS,1):
    bg=grad(a,b); d=ImageDraw.Draw(bg)
    y=150
    for line in head.split('\n'):
        w=d.textlength(line,font=fb); d.text(((W-w)/2,y),line,font=fb,fill='white'); y+=122
    y+=24
    words=sub.split(); lines=[]; cur=''
    for wd in words:
        t=(cur+' '+wd).strip()
        if d.textlength(t,font=fr)>1180: lines.append(cur); cur=wd
        else: cur=t
    lines.append(cur)
    for line in lines:
        w=d.textlength(line,font=fr); d.text(((W-w)/2,y),line,font=fr,fill=(255,255,255,235)); y+=66
    scr=Image.open(f'{SP}/shots/{key}.png').convert('RGB')
    sw=980; sh=int(scr.height*sw/scr.width); scr=scr.resize((sw,sh),Image.LANCZOS)
    top=H-(sh+52)-60; bez=26; R=110
    fw,fh=sw+bez*2,sh+bez*2; fx=(W-fw)//2
    sh_=Image.new('RGBA',(W,H),(0,0,0,0)); ImageDraw.Draw(sh_).rounded_rectangle([fx+10,top+30,fx+fw+10,top+fh+30],R,fill=(0,0,0,90))
    bg=Image.alpha_composite(bg.convert('RGBA'),sh_.filter(ImageFilter.GaussianBlur(30)))
    frame=Image.new('RGBA',(fw,fh),(0,0,0,0)); ImageDraw.Draw(frame).rounded_rectangle([0,0,fw-1,fh-1],R,fill='#111114')
    bg.alpha_composite(frame,(fx,top))
    bg.paste(scr,(fx+bez,top+bez),rounded(scr,R-bez))
    bg=bg.convert('RGB').crop((0,0,W,H))
    bg.save(f'{SP}/appstore/{n}-{key}.png')
print('ok')
