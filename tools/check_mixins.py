#!/usr/bin/env python3
"""Assembly 编辑器 part/mixin 结构检查器。

## 为什么需要它

`character_assembly_page.dart` 被拆成十来个 `part` 文件，每个 part
自成一个 mixin，靠 `on` 子句声明依赖。这套结构有三类错误
**括号平衡检查看不出来、只有 `flutter analyze` 才会报**：

1. **循环依赖** —— 两个 mixin 互相 `on` 对方，Dart 直接拒绝；
2. **调用够不着** —— 用了别的 mixin 的方法，但 `on` 链里没声明；
3. **重复定义** —— 同一个成员被搬到了两个文件。

沙箱里没有 Dart SDK，这个脚本用来在提交前兜住这三类问题。
本项目已经因为 2 号问题连栽两轮，因此专门补了这个检查。

## 用法

    python3 tools/check_mixins.py     # 退出码非 0 表示有问题

## 已知限制

这是**文本级**分析，不是真正的编译。它能抓上面三类结构问题，
但抓不到类型错误、缺参数等——提交前仍须本地跑 `flutter analyze`。
"""
import re,glob,sys
files=sorted(glob.glob('lib/pages/character_assembly_page/*.dart'))
mixins={}
for f in files:
    src=open(f).read()
    m=re.search(r'^mixin\s+(\w+)\s*\n?\s*on\s+([^{]+)\{', src, re.M)
    if not m: continue
    name=m.group(1); deps=[d.strip() for d in m.group(2).split(',')]
    body=src[m.end():]
    defs=set()
    for l in body.split('\n'):
        st=l.strip()
        # 关键修复：跳过注释行。上一版把文档注释里提到的方法名
        # 也算成「定义」，于是循环依赖被判成可达，漏掉了真错误。
        if st.startswith('//') or st.startswith('///') or st.startswith('*'):
            continue
        # 只认「恰好两格缩进」的顶层成员声明；
        # 缩进更深的是方法体内的调用/局部变量，不是定义。
        if not re.match(r'^  [A-Za-z_@]', l): continue
        mm=re.match(r'^  (?:static\s+)?(?:final\s+|const\s+|late\s+)?[\w<>?,\s\[\]]*?\s(_\w+)\s*[({=]', l)
        if mm: defs.add(mm.group(1))
    # 去掉注释后的正文，供引用扫描
    nocmt='\n'.join(l for l in body.split('\n')
                    if not l.strip().startswith(('//','///','*')))
    mixins[name]={'deps':[d for d in deps if d.startswith('_')],
                  'defs':defs,'src':nocmt,'file':f}

print('=== mixin 依赖图 ===')
for n,v in mixins.items():
    print(f'  {n:26s} on {v["deps"] or ["(仅 State)"]}   [{v["file"].split("/")[-1]}]')

def reach(n,seen=frozenset()):
    if n in seen: return True
    return any(reach(d,seen|{n}) for d in mixins.get(n,{}).get('deps',[]))
cyc=[n for n in mixins if reach(n)]
print('\n循环依赖:', cyc if cyc else '无 ✅')

# 重复定义检测（同一名字定义在多个 mixin = 冲突）
from collections import Counter
c=Counter(d for v in mixins.values() for d in v['defs'])
dup=[k for k,n in c.items() if n>1]
print('重复定义:', dup if dup else '无 ✅')

def visible(n,seen=frozenset()):
    if n in seen or n not in mixins: return set()
    out=set(mixins[n]['defs'])
    for d in mixins[n]['deps']:
        out|=visible(d,seen|{n})
    return out

allnames=set().union(*[v['defs'] for v in mixins.values()]) if mixins else set()
bad=False
print('\n=== 跨 mixin 调用可达性 ===')
for n,v in mixins.items():
    vis=visible(n)
    used=set(re.findall(r'\b(_\w+)\s*\(', v['src']))
    missing=(used & allnames) - vis
    if missing:
        bad=True
        print(f'  ❌ {n} 够不着: {sorted(missing)}')
if not bad: print('  全部可达 ✅')
sys.exit(1 if (bad or cyc or dup) else 0)
