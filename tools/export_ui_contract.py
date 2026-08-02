#!/usr/bin/env python3
"""从引擎源码导出 UI 契约（`samples/ui_contract.json`）。

## 为什么需要

转译工具要生成合法的 assembly JSON，就得知道：
有哪些组件类型、枚举下标怎么排、PCB 尺寸上下限是多少、
哪些属性键是引擎真正会读的。

这些信息**只有引擎源码是权威的**。手抄一份到工具里，
引擎一改就漂移——而漂移导致的是「静默失效」：
工具按旧规则生成，引擎按新规则读，不报错、只是不生效
（见 `ASSEMBLY_HANDOFF.md` 3.5j）。

所以：**机器导出，不手抄。** 引擎改了就重跑本脚本。

## 用法

    python3 tools/export_ui_contract.py

在主项目根目录执行，输出 `samples/ui_contract.json`。

## 导出什么

| 键 | 内容 | 来源 |
|---|---|---|
| `atomTypes` | 14 种原子组件类型 | `ui_asset_service.dart` |
| `materials` / `shapes` | 枚举**下标顺序**（引擎存下标不存名字） | `ui_models.dart` |
| `pcb` | 宽高上下限、伴生特例 | `ui_assembly_info.dart` |
| `modes` | 四种 UI 模式 | `ui_assembly_info.dart` |
| `semanticKeys` | `keyAction` / `sendsMessage` 的真实键名 | `ui_semantic_role.dart` |
| `overrideKeys` | 复合件覆写的 `__ovr_` 前缀键 | `ui_assembly_info.dart` |
| `animation` | 动画类型与曲线 | `element_animation.dart` |

联动器方案（68 条）另由 `samples/_schemes.json` 提供，
那份是从 `linker_matrix_engine.dart` 导出的。
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = os.path.join(ROOT, 'packages', 'llm_ui_engine', 'lib', 'src')
ENGINE = os.path.join(PKG, 'engine')
MODELS = os.path.join(PKG, 'models')
# ui_asset_service 留在主项目（编辑器资产库，不在渲染闭包内）
ASSET_SERVICE = os.path.join(ROOT, 'lib', 'services', 'ui_engine',
                             'ui_asset_service.dart')


def read(path):
    if not os.path.isfile(path):
        sys.exit(f'找不到源文件：{path}')
    return open(path, encoding='utf-8').read()


def enum_values(src, name):
    """抽出 enum 的成员**顺序**——引擎存的是下标，顺序即契约。"""
    m = re.search(r'enum\s+' + name + r'\s*\{(.*?)\}', src, re.S)
    if not m:
        sys.exit(f'未找到 enum {name}')
    out = []
    for line in m.group(1).split(','):
        line = re.sub(r'//.*', '', line).strip()
        if line:
            out.append(line.split()[0])
    return out


def const_num(src, name):
    m = re.search(r'static const double\s+' + name + r'\s*=\s*([\d.]+)', src)
    return float(m.group(1)) if m else None


def const_str(src, name):
    m = re.search(r"static const String\s+" + name + r"\s*=\s*'([^']*)'", src)
    return m.group(1) if m else None


models_src = read(os.path.join(ENGINE, 'ui_models.dart'))
info_src = read(os.path.join(MODELS, 'ui_assembly_info.dart'))
role_src = read(os.path.join(ENGINE, 'ui_semantic_role.dart'))
anim_src = read(os.path.join(ENGINE, 'element_animation.dart'))
asset_src = read(ASSET_SERVICE)

# ── 原子类型 ──
m = re.search(r'atomModuleTypes\s*=\s*\{(.*?)\}', asset_src, re.S)
atom_types = sorted(re.findall(r"'([a-z_]+)'", m.group(1))) if m else []

# ── 枚举下标 ──
materials = enum_values(models_src, 'UIModuleMaterial')
shapes = enum_values(models_src, 'UIModuleShape')

# ── PCB 约束 ──
pcb = {
    'minWidth': const_num(info_src, 'minPcbWidth'),
    'maxWidth': const_num(info_src, 'maxPcbWidth'),
    'minHeight': const_num(info_src, 'minPcbHeight'),
    'maxHeight': const_num(info_src, 'maxPcbHeight'),
    'defaultWidth': const_num(info_src, 'defaultPcbWidth'),
}
# 伴生特例：maxPcbWidthFor 引用的是常量名而非字面量，
# 先取出常量名再回查它的值——直接抓数字会漏掉。
m = re.search(r'maxPcbWidthFor\(String mode\)\s*=>\s*(.*?);', info_src, re.S)
if m:
    ref = re.search(r"'extra_companion'\s*\?\s*(\w+)", m.group(1))
    if ref:
        pcb['maxWidthCompanion'] = const_num(info_src, ref.group(1))
    else:
        n = re.search(r'([\d.]+)\s*:', m.group(1))
        if n:
            pcb['maxWidthCompanion'] = float(n.group(1))

# ── 语义标记键名 ──
semantic = {
    'keyAction': const_str(role_src, 'propKey'),
    'sendsMessage': const_str(role_src, 'sendKey'),
}
m = re.search(r'blocksWithoutKeyAction\s*=\s*\{(.*?)\}', role_src, re.S)
semantic['blocksWithoutKeyAction'] = (
    sorted(re.findall(r"'([a-z_]+)'", m.group(1))) if m else [])

# ── 复合件覆写键 ──
override_keys = {}
for name in ('color', 'material', 'shape', 'borderRadius', 'opacity'):
    m = re.search(r"static const String " + name + r"\s*=\s*'([^']+)'",
                  info_src)
    if m:
        override_keys[name] = m.group(1)
m = re.search(r"kCompositeChildNameOverrideKey\s*=\s*'([^']+)'", info_src)
if m:
    override_keys['name'] = m.group(1)

# ── 动画 ──
animation = {
    'types': enum_values(anim_src, 'ElementAnimationType'),
    'curves': enum_values(anim_src, 'ElementAnimationCurve'),
    'propsKey': const_str(anim_src, 'propsKey'),
}

contract = {
    '_generated_by': 'tools/export_ui_contract.py',
    '_note': '机器生成，请勿手改。引擎改动后重跑本脚本。',
    'atomTypes': atom_types,
    'materials': materials,
    'shapes': shapes,
    'pcb': pcb,
    'modes': ['opening', 'scene', 'extra_sticky', 'extra_companion'],
    'semanticKeys': semantic,
    'overrideKeys': override_keys,
    'animation': animation,
}

out = os.path.join(ROOT, 'samples', 'ui_contract.json')
with open(out, 'w', encoding='utf-8') as f:
    json.dump(contract, f, ensure_ascii=False, indent=2)
    f.write('\n')

print(f'已导出 {os.path.relpath(out, ROOT)}')
print(f'  原子类型 {len(atom_types)} 种')
print(f'  material {materials}')
print(f'  shape    {shapes}')
print(f'  PCB      宽 {pcb["minWidth"]}~{pcb["maxWidth"]}'
      f'（伴生 {pcb.get("maxWidthCompanion")}）'
      f' 高 {pcb["minHeight"]}~{pcb["maxHeight"]}')
print(f'  语义键   {semantic["keyAction"]} / {semantic["sendsMessage"]}')
print(f'  覆写键   {len(override_keys)} 个')
print(f'  动画     {len(animation["types"])} 类型 / '
      f'{len(animation["curves"])} 曲线')
