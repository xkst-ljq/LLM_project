# -*- coding: utf-8 -*-
"""校验 .llmcard 是否符合引擎硬约束。"""
import json, zipfile, sys, collections

ATOM_TYPES={'surface','text','image','line','progress','indicator','input',
            'select','slider','switch','button','linker','math_node','timer','page_router','message_flow'}
BACKEND={'linker','math_node','timer','page_router'}

def load(p):
    with zipfile.ZipFile(p) as z:
        return json.loads(z.read('data/character.json'))

def walk(els):
    for e in els:
        yield e
        if e.get('isComposite') and e.get('composite'):
            yield from walk(e['composite']['children'])

def check(path):
    err=[];warn=[]
    ch=load(path)
    meta=json.loads(ch['meta_json'])
    print(f"=== {path.split('/')[-1]} ===")
    print(f"  卡类型 {ch['card_type']}  UI方案 {len(meta['ui_assemblies'])} 套")

    modes=collections.Counter()
    for raw in meta['ui_assemblies']:
        a=json.loads(raw)
        modes[a['mode']]+=1
        pw,phh=a['pcbWidth'],a['pcbHeight']
        maxw = 212.0 if a['mode']=='extra_companion' else 600.0
        if not (120<=pw<=maxw): err.append(f"{a['mode']}: PCB宽 {pw} 越界(120~{maxw})")
        if not (64<=phh<=2000): err.append(f"{a['mode']}: PCB高 {phh} 越界")
        pages=json.loads(a['pages'])
        pids={p['id'] for p in pages}
        allids=set(); btn_ids=set(); router={}; 
        print(f"  [{a['mode']}] {pw:.0f}x{phh:.0f}  {len(pages)} 页")
        for p in pages:
            if p['type']=='overlay' and not p.get('parentPageId'):
                err.append(f"叠加页 {p['name']} 没有父页")
            if p.get('parentPageId') and p['parentPageId'] not in pids:
                err.append(f"页 {p['name']} 的父页不存在")
            for g in p['gestures']:
                if g['targetPageId'] not in pids:
                    err.append(f"页 {p['name']} 手势 {g['direction']} 指向不存在的页")
            n_el=0
            for e in walk(p['elements']):
                n_el+=1
                allids.add(e['id'])
                m=e.get('module')
                if e.get('isComposite'):
                    kids=e['composite']['children']
                    mx=max((k['offset']['x']+k['size']['width'] for k in kids),default=0)
                    my=max((k['offset']['y']+k['size']['height'] for k in kids),default=0)
                    if abs(mx-e['size']['width'])>1 or abs(my-e['size']['height'])>1:
                        warn.append(f"复合件 {e['composite']['name']} 外框 "
                                    f"{e['size']['width']:.0f}x{e['size']['height']:.0f} "
                                    f"≠ 内容 {mx:.0f}x{my:.0f}（会被缩放）")
                    continue
                if not m: err.append(f"元素 {e['id']} 既非复合件也无 module"); continue
                t=m['type']
                if t not in ATOM_TYPES: err.append(f"未知组件类型 {t}")
                if t=='button': btn_ids.add(e['id'])
                if t=='page_router': router[e['id']]=m['properties'].get('route',{})
                # PCB 内包含性（后台件可在外）
                if t not in BACKEND:
                    x,y=e['offset']['x'],e['offset']['y']
                    w,h=e['size']['width'],e['size']['height']
                    if x<-0.5 or y<-0.5 or x+w>pw+0.5 or y+h>phh+0.5:
                        err.append(f"元素 {m['name']} 超出PCB: ({x},{y},{w},{h})")
            print(f"     · {p['name']:10s} {p['type']:7s} {n_el:3d}个元素 {len(p['gestures'])}个手势")
        # linker 校验
        for p in pages:
            for e in walk(p['elements']):
                m=e.get('module')
                if not m or m['type']!='linker': continue
                lk=m['properties']['linker']
                for k in ('sourceModuleId','targetModuleId'):
                    if lk[k] not in allids:
                        err.append(f"linker {m['name']} 的 {k} 指向不存在的元素")
                if lk['scheme']=='button_to_page_route':
                    if lk['sourceModuleId'] not in btn_ids:
                        err.append(f"{m['name']}: 换页方案的源不是 button")
                    r=router.get(lk['targetModuleId'])
                    if r is None: err.append(f"{m['name']}: 目标不是 page_router")
                    elif r.get('targetPageId') not in pids:
                        err.append(f"{m['name']}: 路由目标页不存在")
    for m,c in modes.items():
        if c>1: err.append(f"mode {m} 出现 {c} 次（引擎只取第一个）")
    if warn:
        print("  ⚠ 警告:")
        for w in warn: print("    -",w)
    if err:
        print("  ✗ 错误:")
        for e in err: print("    -",e)
    else:
        print("  ✓ 全部校验通过")
    return len(err)

sys.exit(sum(check(p) for p in sys.argv[1:]))
