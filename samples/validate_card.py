# -*- coding: utf-8 -*-
"""校验 .llmcard 是否符合引擎硬约束。"""
import json, zipfile, sys, collections, os

ATOM_TYPES={'surface','text','image','line','progress','indicator','input',
            'select','slider','switch','button','linker','math_node','timer','page_router','message_flow'}
BACKEND={'linker','math_node','timer','page_router'}

_HERE = os.path.dirname(os.path.abspath(__file__))
try:
    SCHEMES = json.load(open(os.path.join(_HERE, '_schemes.json'), encoding='utf-8'))
except Exception:
    SCHEMES = {}

def scheme_ok(scheme, src_type, tgt_type):
    """方案名是否存在，且源/目标类型是否匹配。

    引擎在 isSchemeSelectable 里校验方案名；名字对不上时**运行端静默跳过**，
    编辑器却仍显示「已配置通路」——作者完全看不出问题
    （用户实测：7 个 linker 只有 3 个真正生效）。
    """
    d = SCHEMES.get(scheme)
    if d is None:
        return f"方案 '{scheme}' 不存在"
    def match(actual, declared, allow):
        if allow:
            return actual in allow
        return declared == 'any' or declared == actual
    if not match(src_type, d['src'], d['asrc']):
        return (f"方案 '{scheme}' 的源要求 "
                f"{d['asrc'] or d['src']}，实际是 {src_type}")
    if not match(tgt_type, d['tgt'], d['atgt']):
        return (f"方案 '{scheme}' 的目标要求 "
                f"{d['atgt'] or d['tgt']}，实际是 {tgt_type}")
    return None

# 固定条目的规定结构。权威来源：
#   character_edit_page._createDefaultEntries（id / title / 子字段）
#   card_entry_target.fieldLabelOf（子字段中文名）
# 只填一个纯字符串会让编辑页显示不出子项目标题（用户反馈）。
FIXED_ENTRIES = {
 'character': [
  ('name_entry',   '名称',      ['last_name', 'first_name', 'other']),
  ('relationship', '与用户关系', None),   # None = 纯文本
  ('body',         '身体数据',   ['race', 'gender', 'age', 'height',
                                  'weight', 'measurements', 'other']),
  ('psychology',   '心理数据',   ['personality', 'thoughts', 'interests']),
  ('background',   '背景数据',   ['origin', 'experiences', 'current']),
 ],
 'system': [
  ('system_name',    '系统名称', None),
  ('system_summary', '系统概要', None),
  ('system_details', '系统详情', ['world_setting', 'worldview',
                                  'system_mechanism']),
  ('protagonist',    '主角设定', ['name', 'detail']),
  ('plot',           '剧情',     ['cause', 'events', 'goal',
                                  'possible_endings']),
 ],
}

def check_entries(card_type, entries_json, err, warn):
    """固定条目的 id / 标题 / 子字段结构。"""
    try:
        entries = json.loads(entries_json)
    except Exception:
        err.append('entries_json 解析失败')
        return
    spec = FIXED_ENTRIES.get(card_type)
    if not spec:
        return
    by_id = {e.get('id'): e for e in entries}
    for eid, title, fields in spec:
        e = by_id.get(eid)
        if e is None:
            err.append(f"缺少固定条目 '{eid}'（{title}）")
            continue
        if e.get('title') != title:
            warn.append(f"条目 '{eid}' 标题是「{e.get('title')}」，"
                        f"模板为「{title}」")
        if fields is None:
            continue
        raw = e.get('content', '')
        try:
            obj = json.loads(raw) if isinstance(raw, str) else raw
        except Exception:
            obj = None
        if not isinstance(obj, dict):
            err.append(f"条目 '{eid}'（{title}）应是含子字段的 JSON 对象 "
                       f"{fields}，实际是纯文本——编辑页显示不出子项目标题")
            continue
        missing = [k for k in fields if k not in obj]
        extra = [k for k in obj if k not in fields]
        if missing:
            err.append(f"条目 '{eid}' 缺子字段 {missing}")
        if extra:
            err.append(f"条目 '{eid}' 有模板外的子字段 {extra}")

def load(p):
    with zipfile.ZipFile(p) as z:
        return json.loads(z.read('data/character.json'))

def _lum(c):
    r, g, b = ((c >> 16) & 255) / 255, ((c >> 8) & 255) / 255, (c & 255) / 255
    f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

def contrast(a, b):
    la, lb = _lum(a), _lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def _rect(e):
    o, sz = e['offset'], e['size']
    return (o['x'], o['y'], o['x'] + sz['width'], o['y'] + sz['height'])

def _covers(bg, fg):
    """bg 是否完整盖住 fg（用来判断文字落在哪块底色上）。"""
    bx1, by1, bx2, by2 = _rect(bg)
    fx1, fy1, fx2, fy2 = _rect(fg)
    return (bx1 <= fx1 + 0.5 and by1 <= fy1 + 0.5
            and bx2 >= fx2 - 0.5 and by2 >= fy2 - 0.5)

def check_contrast(page_elements, warn):
    """文字与其背后底色的对比度。

    小字（<14px）按 AAA 7:1 要求——WCAG 的 4.5:1 门槛是给正文字号定的，
    9~12px 的注释文字用 4.5:1 实际很难看清（用户反馈：开场白看不清）。
    """
    surfaces = [e for e in page_elements
                if not e.get('isComposite') and e.get('module')
                and e['module']['type'] in ('surface', 'base_box')]
    for e in page_elements:
        if e.get('isComposite') or not e.get('module'):
            continue
        m = e['module']
        if m['type'] != 'text':
            continue
        size = float(m['properties'].get('fontSize', 13))
        fg = m['color']
        best = None
        for sf in surfaces:
            if sf['layerIndex'] > e['layerIndex']:
                continue
            if not _covers(sf, e):
                continue
            if best is None or sf['layerIndex'] > best['layerIndex']:
                best = sf
        if best is None:
            continue
        r = contrast(fg, best['module']['color'])
        need = 7.0 if size < 14 else 4.5
        if r < need:
            txt = str(m['properties'].get('text', ''))[:12]
            warn.append(
                f"对比度不足: 「{txt}」{size:.0f}px "
                f"{r:.2f}:1 < {need}:1 "
                f"(字 0x{fg:08X} 底 0x{best['module']['color']:08X})")

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
    check_entries(ch['card_type'], ch.get('entries_json', '[]'), err, warn)

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
        allids=set(); btn_ids=set(); router={}; key_actions=[]; sends=[]; 
        print(f"  [{a['mode']}] {pw:.0f}x{phh:.0f}  {len(pages)} 页")
        for p in pages:
            if p['type']=='overlay' and not p.get('parentPageId'):
                err.append(f"叠加页 {p['name']} 没有父页")
            if p.get('parentPageId') and p['parentPageId'] not in pids:
                err.append(f"页 {p['name']} 的父页不存在")
            for g in p['gestures']:
                if g['targetPageId'] not in pids:
                    err.append(f"页 {p['name']} 手势 {g['direction']} 指向不存在的页")
            n_el=0; page_keys=[]
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
                # indicator 靠 statusRules 决定颜色；isOn/onColor/offColor
                # 这些键引擎完全不读（resolveIndicatorActiveState）。
                if t=='indicator':
                    ip=m['properties']
                    ghost=[k for k in ('isOn','onColor','offColor') if k in ip]
                    if ghost:
                        err.append(f"indicator「{m['name']}」用了引擎不读的键 "
                                   f"{ghost}，应改用 statusRules + defaultColor")
                    elif 'defaultColor' not in ip:
                        warn.append(f"indicator「{m['name']}」没设 defaultColor，"
                                    f"未命中规则时会是灰色")
                if m['properties'].get('keyAction') is True:
                    key_actions.append(m['name'])
                    page_keys.append(m['name'])
                if m['properties'].get('sendsMessage') is True:
                    sends.append((m['name'], t))
                if t=='page_router': router[e['id']]=m['properties'].get('route',{})
                # PCB 内包含性（后台件可在外）
                if t not in BACKEND:
                    x,y=e['offset']['x'],e['offset']['y']
                    w,h=e['size']['width'],e['size']['height']
                    if x<-0.5 or y<-0.5 or x+w>pw+0.5 or y+h>phh+0.5:
                        err.append(f"元素 {m['name']} 超出PCB: ({x},{y},{w},{h})")
            if len(page_keys) > 1:
                warn.append(f"页「{p['name']}」有 {len(page_keys)} 个 keyAction "
                            f"标记 {page_keys}，同一页只该有一个")
            check_contrast(p['elements'], warn)
            print(f"     · {p['name']:10s} {p['type']:7s} {n_el:3d}个元素 {len(p['gestures'])}个手势")
        # linker 校验
        types = {}
        for p in pages:
            for e in walk(p['elements']):
                if e.get('module'):
                    types[e['id']] = e['module']['type']
        for p in pages:
            for e in walk(p['elements']):
                m=e.get('module')
                if not m or m['type']!='linker': continue
                lk=m['properties']['linker']
                bad_ref=False
                for k in ('sourceModuleId','targetModuleId'):
                    if lk[k] not in allids:
                        err.append(f"linker {m['name']} 的 {k} 指向不存在的元素")
                        bad_ref=True
                if not bad_ref:
                    msg = scheme_ok(lk.get('scheme',''),
                                    types.get(lk['sourceModuleId'],'?'),
                                    types.get(lk['targetModuleId'],'?'))
                    if msg:
                        err.append(f"linker「{m['name']}」: {msg}")
                # 方案参数的键名是 schemeParams，不是 params。
                # 写错的话引擎读不到，静默回落默认值
                # （用户实测：两条连线的 targetParam 都变成 paramA）。
                if 'params' in lk:
                    err.append(f"linker「{m['name']}」: 参数键名应为 "
                               f"'schemeParams'，写成了 'params'——引擎读不到")
                # button 的触发手势键名是 sourceGesture，且只有三种取值。
                g = lk.get('sourceGesture')
                if g is not None:
                    if g not in ('tap', 'double_tap', 'long_press'):
                        err.append(f"linker「{m['name']}」: sourceGesture "
                                   f"'{g}' 非法（tap/double_tap/long_press）")
                    elif lk.get('sourcePort') != g:
                        # LinkerService 按 srcPort == event.eventType 匹配，
                        # 两者不一致时双击/长按接不通。
                        err.append(
                            f"linker「{m['name']}」: sourceGesture='{g}' 但 "
                            f"sourcePort='{lk.get('sourcePort')}'，两者必须一致")
                if lk['scheme']=='button_to_page_route':
                    if lk['sourceModuleId'] not in btn_ids:
                        err.append(f"{m['name']}: 换页方案的源不是 button")
                    r=router.get(lk['targetModuleId'])
                    if r is None: err.append(f"{m['name']}: 目标不是 page_router")
                    elif r.get('targetPageId') not in pids:
                        err.append(f"{m['name']}: 路由目标页不存在")
        # ── 关键职责标记（UISemanticRole）──
        # opening / scene 缺标记会**整层不渲染**（canRun 返回 false），
        # 表现为「UI 根本没出来」；extra_sticky 只是少个折叠按钮。
        need = {'opening': '确认并关闭', 'scene': '打开聊天设置',
                'extra_sticky': '折叠界面'}
        if a['mode'] in need:
            if not key_actions:
                lvl = err if a['mode'] in ('opening', 'scene') else warn
                lvl.append(f"{a['mode']}: 没有任何 keyAction 标记"
                           f"（需要「{need[a['mode']]}」）"
                           + ("——**整层不会渲染**" if lvl is err else ""))
            # 多个 keyAction 不算错：多页面 scene 通常每页都要有出口。
            # 但同一页里出现两个就是重复了。
        # scene 若无发送消息的入口，玩家没法说话（原生输入栏被接管了）
        if a['mode'] == 'scene' and not sends:
            warn.append("scene: 没有 sendsMessage 标记，玩家无法发消息")
        for nm, t in sends:
            if t not in ('button', 'input'):
                err.append(f"sendsMessage 标在 {t} 上（只有 button/input 有效）")

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
