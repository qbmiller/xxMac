"""Render README artwork locally with Pillow and macOS system fonts.
Run: python3 docs/artwork/render_feature_overview.py
The mini interfaces are illustrations, not application screenshots.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser()
parser.add_argument('--lang', choices=['zh', 'en'], default='zh')
LANG = parser.parse_args().lang

ROOT = Path(__file__).resolve().parents[2]
W, H = 1920, 2240
im = Image.new('RGB', (W, H), '#f3f5fb')
d = ImageDraw.Draw(im)
CN = '/System/Library/Fonts/Hiragino Sans GB.ttc'
EN = '/System/Library/Fonts/SFNS.ttf'
TRANSLATIONS = {'让 Mac 高频操作，一处完成': 'Your everyday Mac tools, together.', '从快速启动到任务管理，把日常工作串起来。': 'Launch faster. Stay organized. Keep work moving.', '12 项核心能力': '12 CORE FEATURES', '全局启动器': 'Global Launcher', '应用、命令、最近操作，一搜即达': 'Find apps, commands and recent actions.', '输入算式即时计算，回车复制结果': 'Calculate as you type. Return to copy.', '剪贴板历史': 'Clipboard History', '找回复制过的文本和图片': 'Find text and images you copied before.', '支持收藏、回贴与本地 OCR 检索': 'Save favorites, paste back, search local OCR.', '待办与桌面组件': 'Todo & Widgets', '四象限、今日清单、状态看板': 'Prioritize with quadrants, Today and boards.', '在桌面查看任务，直接勾选完成': 'View and complete tasks on your desktop.', '应用快捷启动': 'App Hotkeys', '给常用 App 绑定专属快捷键': 'Give favorite apps their own hotkeys.', '快速启动、激活与隐藏切换': 'Launch, activate or toggle visibility.', '窗口管理': 'Window Management', '半屏、四角、居中与缩放': 'Halves, corners, centering and resizing.', '跨显示器移动，整理桌面布局': 'Move across displays. Arrange your space.', '文本片段': 'Text Snippets', '分类保存常用回复与代码片段': 'Organize reusable replies and code.', '关键词搜索，回车快速输入': 'Search by keyword. Press Return to insert.', '快捷指令': 'Quick Shortcuts', '关键词触发网页搜索或本地脚本': 'Run web searches or local scripts by keyword.', '支持 URL 模板与脚本参数': 'Use URL templates and script arguments.', '浏览器搜索': 'Browser Search', '搜索 Chrome / Edge 书签与历史': 'Search Chrome / Edge bookmarks and history.', '输入关键词，快速找回访问入口': 'Find the page you need with a few words.', '中国日历': 'Chinese Calendar', '农历、节气、节假日与补班': 'Lunar dates, solar terms and public holidays.', '菜单栏随时查看，快速切换年月': 'Browse months right from your menu bar.', 'Finder 粘贴增强': 'Finder Paste Tools', '复制文件路径，粘贴到常用应用': 'Paste copied file paths into other apps.', '剪贴板图片、文本可直接存为文件': 'Save clipboard images and text as files.', '快捷键助手': 'Shortcut Assistant', '捕捉快捷键被哪个 App 接收': 'Discover which app receives a shortcut.', '双击 Command 查看菜单快捷键': 'Double-tap Command for menu shortcuts.', 'LockJob / 推荐工具': 'LockJob / Discover', '屏幕遮罩保持唤醒，后台任务继续': 'Cover screens. Stay awake. Keep jobs running.', '分类发现精选工具与网站': 'Explore curated tools and useful websites.', '搜索应用或输入算式…': 'Search apps or type an expression…', '项目笔记：今天的灵感': 'Project notes: a new idea', '图片中的文字，也能搜到': 'Text in images is searchable too', '重要 · 紧急': 'Important / Urgent', '重要 · 不紧急': 'Important / Later', '紧急 · 不重要': 'Urgent / Delegate', '其他任务': 'Other tasks', '常用应用': 'Your app', '按一下，即刻切换': 'One hotkey. Instant access.', '回复 / 工作 / 代码': 'Replies / Work / Code', '关键词  →  常用文本  →  输入': 'Keyword  →  Saved text  →  Insert', 'g  macOS 效率工具': 'g  macOS productivity tools', 'bm  书签': 'bm  Bookmarks', 'bh  历史': 'bh  History', '从记得的关键词，找回网页': 'A keyword is all you need to find a page.', '农历 · 节气 · 节日': 'Lunar dates / Solar terms', '假期 / 补班 一眼可见': 'Holidays / Make-up workdays', '路径 / 文件': 'Paths / Files', '图片 → PNG     文本 → TXT': 'Image → PNG     Text → TXT', '菜单快捷键': 'Menu shortcuts', '快捷键归属捕捉 · 菜单速查': 'Shortcut capture / Menu reference', '遮住屏幕，工作继续': 'Cover. Keep working.', '推荐工具  /  实用网站  /  分类浏览': 'Curated tools / Websites / Categories', '原生 macOS  ·  全局快捷键  ·  简体中文 / 繁體中文 / English': 'Native macOS  ·  Global hotkeys  ·  English / Simplified & Traditional Chinese', '剪贴板历史需手动开启；桌面小组件需 macOS 14+。图中界面为功能示意。': 'Enable clipboard history in Settings. Widgets require macOS 14+. Interfaces shown are illustrations.'}

def localize(s):
    return TRANSLATIONS.get(s, s) if LANG == 'en' else s

INK, MUTED = '#202b46', '#64718b'

def font(size, bold=False):
    if LANG == 'en':
        return ImageFont.truetype('/System/Library/Fonts/HelveticaNeue.ttc', size, index=1 if bold else 0)
    return ImageFont.truetype(CN, size, index=1 if bold else 0)

def text(x, y, s, size=28, color=INK, bold=False):
    s = localize(s)
    if LANG == 'en' and size == 26:
        size = 24
    if LANG == 'en' and s == 'Your everyday Mac tools, together.':
        size = 72
    # CJK system fonts omit several macOS keycap symbols; draw those with SF.
    cursor = x
    for ch in s:
        f = ImageFont.truetype(EN, size) if ch in '⌘⌥⇧→↗' else font(size, bold)
        d.text((cursor, y), ch, font=f, fill=color)
        cursor += d.textlength(ch, font=f)

def rr(box, fill, radius=18, outline=None, width=2):
    d.rounded_rectangle(box, radius, fill=fill, outline=outline, width=width)

def line(points, color='#cbd3e5', width=3):
    d.line(points, fill=color, width=width, joint='curve')

def chip(x, y, label, fill='#edf0fb', color='#525cc4', size=23):
    label = localize(label)
    width = d.textlength(label, font=font(size)) + 30
    rr((x, y, x+width, y+42), fill, 12)
    text(x+15, y+5, label, size, color)
    return width

def check(x, y, color):
    line([(x,y+9),(x+8,y+17),(x+23,y)], color, 4)

def icon(x, y, kind, color):
    rr((x,y,x+58,y+58), '#f0f2fa', 15)
    x+=12; y+=12
    if kind == 'search':
        d.ellipse((x+1,y+1,x+24,y+24),outline=color,width=3)
        line([(x+22,y+22),(x+34,y+34)],color,4)
    elif kind == 'window':
        rr((x,y+2,x+35,y+31),None,5,color,3)
        line([(x+17,y+3),(x+17,y+30)],color,3)
    elif kind == 'clip':
        rr((x+5,y+4,x+30,y+34),None,4,color,3)
        rr((x+11,y,x+24,y+8),'#f0f2fa',3,color,3)
    elif kind == 'todo':
        for off in (1,15,29):
            check(x,y+off-4,color); line([(x+28,y+off+5),(x+35,y+off+5)],color,3)
    elif kind == 'calendar':
        rr((x,y+4,x+35,y+34),None,5,color,3)
        line([(x,y+13),(x+35,y+13)],color,3)
        line([(x+9,y),(x+9,y+8)],color,3); line([(x+27,y),(x+27,y+8)],color,3)
    elif kind == 'lock':
        d.arc((x+7,y-1,x+28,y+23),180,360,fill=color,width=3)
        rr((x+2,y+14,x+33,y+35),None,5,color,3)
    else:
        symbols={'app':'↗','snippet':'T','quick':'>_','browser':'@','finder':'/','key':'⌘','star':'✦'}
        d.text((x,y-7),symbols[kind],font=ImageFont.truetype(EN,36),fill=color)

# A quiet indigo header with one unified, high contrast reading surface.
for y in range(438):
    t=y/438
    d.line((0,y,W,y),fill=(int(32+15*t),int(42+9*t),int(87+18*t)))
d.ellipse((1510,-270,2240,460),fill='#384775')
d.ellipse((1660,-160,2170,350),outline='#53618c',width=2)
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp)/'icon.png'
    subprocess.run(['sips','-s','format','png',str(ROOT/'Resources/AppIcon.icns'),'--out',str(p)],check=True,capture_output=True)
    app=Image.open(p).convert('RGBA'); app.thumbnail((126,126))
    rr((73,57,195,179), '#ffffff', 28)
    im.paste(app,(72,55),app)
text(216,62,'xxMac',68,'#ffffff',True)
text(219,151,'MACOS PRODUCTIVITY TOOLKIT',21,'#bfc8e8')
text(82,237,'让 Mac 高频操作，一处完成',67,'#ffffff',True)
text(85,341,'从快速启动到任务管理，把日常工作串起来。',30,'#ccd4ef')
chip(1470,338,'12 项核心能力','#475582','#ffffff',25)

features=[
('全局启动器','应用、命令、最近操作，一搜即达','输入算式即时计算，回车复制结果','search','#5d62db','launch'),
('剪贴板历史','找回复制过的文本和图片','支持收藏、回贴与本地 OCR 检索','clip','#5d62db','clipboard'),
('待办与桌面组件','四象限、今日清单、状态看板','在桌面查看任务，直接勾选完成','todo','#5d62db','todo'),
('应用快捷启动','给常用 App 绑定专属快捷键','快速启动、激活与隐藏切换','app','#397eac','apps'),
('窗口管理','半屏、四角、居中与缩放','跨显示器移动，整理桌面布局','window','#397eac','windows'),
('文本片段','分类保存常用回复与代码片段','关键词搜索，回车快速输入','snippet','#397eac','snippets'),
('快捷指令','关键词触发网页搜索或本地脚本','支持 URL 模板与脚本参数','quick','#8b64b7','quick'),
('浏览器搜索','搜索 Chrome / Edge 书签与历史','输入关键词，快速找回访问入口','browser','#8b64b7','browser'),
('中国日历','农历、节气、节假日与补班','菜单栏随时查看，快速切换年月','calendar','#8b64b7','calendar'),
('Finder 粘贴增强','复制文件路径，粘贴到常用应用','剪贴板图片、文本可直接存为文件','finder','#348b88','finder'),
('快捷键助手','捕捉快捷键被哪个 App 接收','双击 Command 查看菜单快捷键','key','#348b88','key'),
('LockJob 与推荐工具','多屏遮罩、保持唤醒，后台继续工作','另有精选工具与网站分类目录','lock','#348b88','lock'),
]
# Keep LockJob and recommendations distinct in one card: two named mini modules.
features[-1]=('LockJob / 推荐工具','屏幕遮罩保持唤醒，后台任务继续','分类发现精选工具与网站','lock','#348b88','lock')

def mini(x,y,w,kind,c):
    rr((x,y,x+w,y+137),'#f5f7fc',16)
    if kind=='launch':
        rr((x+18,y+16,x+w-18,y+64),'#ffffff',10,'#d9def0')
        text(x+33,y+23,'搜索应用或输入算式…',23,MUTED)
        chip(x+20,y+79,'Safari',size=21); chip(x+130,y+79,'4 + 8 = 12',size=21)
    elif kind=='clipboard':
        for i,s in enumerate(['项目笔记：今天的灵感','图片中的文字，也能搜到']):
            rr((x+18,y+16+55*i,x+w-18,y+62+55*i),'#ffffff',9)
            text(x+32,y+23+55*i,s,23,MUTED)
    elif kind=='todo':
        for i,col in enumerate(['#f1dce4','#f5e8d1','#dce8f9','#ddede7']):
            xx=x+19+(i%2)*(w/2-10); yy=y+17+(i//2)*55
            rr((xx,yy,xx+w/2-23,yy+45),col,8)
            text(xx+12,yy+7,['重要 · 紧急','重要 · 不紧急','紧急 · 不重要','其他任务'][i],20,MUTED)
    elif kind=='apps':
        chip(x+22,y+24,'⌥  A',size=29)
        text(x+160,y+30,'→',34,c)
        rr((x+225,y+21,x+w-22,y+84),'#ffffff',12)
        text(x+242,y+36,'常用应用',26,MUTED)
        text(x+25,y+96,'按一下，即刻切换',20,MUTED)
    elif kind=='windows':
        for i in range(3):
            xx=x+23+i*148
            rr((xx,y+23,xx+127,y+113),'#ffffff',9,'#cbd6e9')
            if i==0: rr((xx+6,y+29,xx+61,y+107),'#b5d6ee',4)
            elif i==1: rr((xx+6,y+29,xx+61,y+65),'#b5d6ee',4)
            else: rr((xx+24,y+41,xx+103,y+95),'#b5d6ee',4)
    elif kind=='snippets':
        chip(x+20,y+23,'回复 / 工作 / 代码',size=22)
        text(x+25,y+83,'关键词  →  常用文本  →  输入',24,MUTED)
    elif kind=='quick':
        text(x+23,y+20,'g  macOS 效率工具',26,c)
        line([(x+23,y+65),(x+w-23,y+65)],'#e2e5ee',2)
        text(x+23,y+84,'>_  script  {query}',25,MUTED)
    elif kind=='browser':
        chip(x+20,y+21,'bm  书签',size=25)
        chip(x+235,y+21,'bh  历史',size=25)
        text(x+25,y+84,'从记得的关键词，找回网页',24,MUTED)
    elif kind=='calendar':
        rr((x+20,y+18,x+110,y+117),'#ffffff',10)
        rr((x+20,y+18,x+110,y+44),'#ded9f3',7)
        text(x+43,y+48,'23',43,c,True)
        text(x+138,y+26,'农历 · 节气 · 节日',25,MUTED)
        text(x+138,y+79,'假期 / 补班 一眼可见',23,MUTED)
    elif kind=='finder':
        chip(x+20,y+20,'⌘ ⇧ V',size=28)
        text(x+220,y+27,'路径 / 文件',27,c)
        text(x+25,y+86,'图片 → PNG     文本 → TXT',24,MUTED)
    elif kind=='key':
        chip(x+20,y+23,'⌘  ⌘',size=29)
        text(x+210,y+30,'菜单快捷键',27,c)
        text(x+25,y+89,'快捷键归属捕捉 · 菜单速查',23,MUTED)
    elif kind=='lock':
        chip(x+20,y+20,'LockJob',size=25)
        text(x+205,y+26,'遮住屏幕，工作继续',23,c)
        text(x+25,y+86,'推荐工具  /  实用网站  /  分类浏览',22,MUTED)

for i,(title,a,b,ic,c,kind) in enumerate(features):
    x=72+(i%3)*600; y=484+(i//3)*386
    rr((x,y+5,x+576,y+365),'#e8ecf6',25)
    rr((x,y,x+576,y+360),'#ffffff',25,'#e3e7f1')
    icon(x+26,y+25,ic,c)
    text(x+100,y+33,title,33,INK,True)
    text(x+29,y+107,a,26,MUTED)
    text(x+29,y+150,b,26,MUTED)
    mini(x+26,y+207,524,kind,c)
    # Text must fit inside every card, including at README display size.
    for s,sz,available in [(title,33,450),(a,26,518),(b,26,518)]:
        assert d.textlength(localize(s),font=font(24 if LANG == 'en' and sz == 26 else sz,s==title)) <= available, localize(s)

line([(78,2067),(1842,2067)],'#dce2ef',2)
text(80,2100,'原生 macOS  ·  全局快捷键  ·  简体中文 / 繁體中文 / English',27,INK)
text(80,2160,'剪贴板历史需手动开启；桌面小组件需 macOS 14+。图中界面为功能示意。',23,MUTED)
out=ROOT/('docs/images/feature-overview-en.png' if LANG == 'en' else 'docs/images/feature-overview.png')
im.save(out,optimize=True)
preview=im.copy(); preview.thumbnail((960,1120)); preview.save(f'/tmp/xxmac-feature-preview-{LANG}.png')
print(f'{out}: {W} × {H}, {out.stat().st_size:,} bytes')
