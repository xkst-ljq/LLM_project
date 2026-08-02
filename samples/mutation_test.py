"""变异测试：对一张合法卡注入单点错误，验证 validate_card.py 能否抓到。

## 为什么需要

校验器最危险的失败方式不是「报错太多」，而是**该报的没报**——
写错的卡被判定合法，问题留到运行时才暴露成「UI 没反应」。

光看代码判断不出覆盖面（我曾因此误判校验器「只有两个检查函数」，
实际它相当完整）。**唯一可信的办法是造错卡实测。**

## 用法

    python3 samples/mutation_test.py

它会依次注入 9 种真实踩过的错误，逐条报告校验器是否抓到。
新增检查项时，请同步在这里加一个变异用例。

## 用例来源

每一条都是实际发生过的：
`createdAt` 类型、枚举下标写成字符串、`keyAction` 键名、
三层嵌套漏 encode、`parentSurfaceId` 悬空引用等。
"""
import json,zipfile,copy,os,subprocess,sys,tempfile

SRC='samples/织房夜话_伴生常驻卡.llmcard'
z=zipfile.ZipFile(SRC)
BASE=json.loads(z.read('data/character.json').decode('utf-8'))
OTHERS={n:z.read(n) for n in z.namelist() if n!='data/character.json'}

def build(card, path):
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as w:
        for n,b in OTHERS.items(): w.writestr(n,b)
        w.writestr('data/character.json', json.dumps(card,ensure_ascii=False))

def mutate(fn):
    c=copy.deepcopy(BASE)
    meta=json.loads(c['meta_json'])
    asms=[json.loads(a) for a in meta['ui_assemblies']]
    fn(c,meta,asms)
    meta['ui_assemblies']=[json.dumps(a,ensure_ascii=False) for a in asms]
    c['meta_json']=json.dumps(meta,ensure_ascii=False)
    return c

def first_el(a, pred=lambda m: True):
    pages=json.loads(a['pages'])
    for p in pages:
        for e in p['elements']:
            if e.get('module') and pred(e['module']):
                return pages,p,e
    return pages,None,None

CASES={}
def case(name):
    def deco(f): CASES[name]=f; return f
    return deco

@case('createdAt 写成 ISO 字符串')
def _(c,meta,asms): asms[0]['createdAt']='2026-01-01T00:00:00.000'

@case('material 写成字符串')
def _(c,meta,asms):
    pages,p,e=first_el(asms[0]); e['module']['material']='solid'
    asms[0]['pages']=json.dumps(pages,ensure_ascii=False)

@case('shape 写成字符串')
def _(c,meta,asms):
    pages,p,e=first_el(asms[0]); e['module']['shape']='rounded'
    asms[0]['pages']=json.dumps(pages,ensure_ascii=False)

@case('color 写成 #RRGGBB')
def _(c,meta,asms):
    pages,p,e=first_el(asms[0]); e['module']['color']='#FF0000'
    asms[0]['pages']=json.dumps(pages,ensure_ascii=False)

@case('keyAction 键名写成 is_key_action')
def _(c,meta,asms):
    for a in asms:
        pages=json.loads(a['pages']); hit=False
        for p in pages:
            for e in p['elements']:
                m=e.get('module')
                if m and m['properties'].get('keyAction') is True:
                    del m['properties']['keyAction']
                    m['properties']['is_key_action']=True; hit=True
        if hit: a['pages']=json.dumps(pages,ensure_ascii=False)

@case('pages 忘了 jsonEncode（写成数组）')
def _(c,meta,asms): asms[0]['pages']=json.loads(asms[0]['pages'])

@case('parentSurfaceId 指向不存在的元素')
def _(c,meta,asms):
    pages,p,e=first_el(asms[0]); e['parentSurfaceId']='el_不存在'
    asms[0]['pages']=json.dumps(pages,ensure_ascii=False)

@case('mode 拼错')
def _(c,meta,asms): asms[0]['mode']='extra_stiky'

@case('offset 缺 y')
def _(c,meta,asms):
    pages,p,e=first_el(asms[0]); e['offset'].pop('y',None)
    asms[0]['pages']=json.dumps(pages,ensure_ascii=False)

tmp=tempfile.mkdtemp()
print(f"{'注入的错误':38s} {'校验器':8s}")
print('-'*54)
miss=[]
for name,fn in CASES.items():
    path=os.path.join(tmp,'t.llmcard')
    try: build(mutate(fn), path)
    except Exception as ex:
        print(f'{name:38s} 构造失败 {ex}'); continue
    r=subprocess.run([sys.executable,'samples/validate_card.py',path],
                     capture_output=True,text=True)
    caught = r.returncode!=0 or '✗' in r.stdout
    print(f"{name:38s} {'✅ 抓到' if caught else '❌ 漏掉'}")
    if not caught: miss.append(name)
print()
print('漏掉',len(miss),'项:')
for m in miss: print('  -',m)
