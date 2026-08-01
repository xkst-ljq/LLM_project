#!/usr/bin/env python3
"""检查 `llm_ui_engine` 本地包是否被正确挂载。

## 为什么需要它

把渲染引擎抽成 `packages/llm_ui_engine` 后，只要包没被 pub 解析到，
`flutter analyze` 就会报出**上千条**连锁错误
（包内 97 个公开类型全部未定义 → 整个 Assembly 模块逐行报错）。

这些错误看起来很吓人，但全是同一个根因。逐条读日志既慢又容易
被表象误导——真正该看的只有一件事：**package_config.json 里有没有它**。

本脚本直接检查那个文件，一秒给出结论。

## 用法

    python3 tools/check_pkg_wiring.py

在**主项目根目录**执行。它会同时检查主项目与 PC 转译工具两侧。

## 它能查出什么

1. 包目录与 pubspec 是否存在、name 是否匹配；
2. 两侧 pubspec 是否声明了 path 依赖，且路径可达；
3. `.dart_tool/package_config.json` 是否已收录该包（**决定性判据**）；
4. package_config 是否比 pubspec 旧（改了依赖但没重跑 pub get）。
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG_NAME = 'llm_ui_engine'
PKG_DIR = os.path.join(ROOT, 'packages', PKG_NAME)
TOOL_DIR = os.path.join(ROOT, 'ToolofPC', 'llm_card_converter')

ok = True


def fail(msg, fix=None):
    global ok
    ok = False
    print(f'  \u274c {msg}')
    if fix:
        print(f'     \u2192 {fix}')


def good(msg):
    print(f'  \u2705 {msg}')


print('=== 1. 包本身 ===')
pkg_pubspec = os.path.join(PKG_DIR, 'pubspec.yaml')
entry = os.path.join(PKG_DIR, 'lib', f'{PKG_NAME}.dart')
if not os.path.isdir(PKG_DIR):
    fail(f'包目录不存在：{PKG_DIR}', '确认已 git pull 到最新')
elif not os.path.isfile(pkg_pubspec):
    fail('包缺少 pubspec.yaml')
elif not os.path.isfile(entry):
    fail(f'包缺少入口文件 lib/{PKG_NAME}.dart')
else:
    name = ''
    for line in open(pkg_pubspec, encoding='utf-8'):
        if line.startswith('name:'):
            name = line.split(':', 1)[1].strip()
            break
    if name != PKG_NAME:
        fail(f'包名不匹配：pubspec 写的是 "{name}"，应为 "{PKG_NAME}"')
    else:
        n = sum(1 for _ in open(entry, encoding='utf-8')
                if _.startswith('export'))
        good(f'包完整（name={name}，导出 {n} 个源文件）')


def check_side(label, proj_dir, expect_path):
    """检查某一侧（主项目 / 工具）的挂载情况。"""
    print(f'\n=== {label} ===')
    pubspec = os.path.join(proj_dir, 'pubspec.yaml')
    if not os.path.isfile(pubspec):
        fail(f'找不到 {pubspec}')
        return

    # 2a. pubspec 是否声明了 path 依赖
    text = open(pubspec, encoding='utf-8').read()
    if f'{PKG_NAME}:' not in text:
        fail('pubspec.yaml 未声明 llm_ui_engine 依赖')
        return
    declared_path = None
    lines = text.replace('\r\n', '\n').split('\n')
    for i, l in enumerate(lines):
        if l.strip().startswith(f'{PKG_NAME}:'):
            for j in range(i + 1, min(i + 4, len(lines))):
                if 'path:' in lines[j]:
                    declared_path = lines[j].split('path:', 1)[1].strip()
                    break
            break
    if not declared_path:
        fail('声明了 llm_ui_engine 但没写 path:')
        return
    resolved = os.path.normpath(os.path.join(proj_dir, declared_path))
    if not os.path.isdir(resolved):
        fail(f'path 指向的目录不存在：{declared_path}',
             f'应为 {expect_path}')
        return
    good(f'pubspec 已声明 path: {declared_path}（可达）')

    # 2b. 决定性判据：package_config.json 是否收录
    cfg = os.path.join(proj_dir, '.dart_tool', 'package_config.json')
    if not os.path.isfile(cfg):
        fail('.dart_tool/package_config.json 不存在',
             f'在 {proj_dir} 执行 flutter pub get')
        return
    try:
        data = json.load(open(cfg, encoding='utf-8'))
    except Exception as e:  # noqa: BLE001
        fail(f'package_config.json 解析失败：{e}', '试 flutter clean 后重来')
        return
    names = {p.get('name') for p in data.get('packages', [])}
    if PKG_NAME not in names:
        fail('package_config.json 里【没有】 llm_ui_engine —— 这就是报错的根因',
             f'在 {proj_dir} 执行 flutter pub get')
        return

    # 2c. 时间戳：改了 pubspec 但没重跑 pub get
    if os.path.getmtime(cfg) < os.path.getmtime(pubspec):
        fail('package_config.json 比 pubspec.yaml 旧（依赖改过但没重新解析）',
             f'在 {proj_dir} 执行 flutter pub get')
        return
    good('package_config.json 已收录 llm_ui_engine，且是最新的')


check_side('2. 主项目', ROOT, 'packages/llm_ui_engine')
check_side('3. PC 转译工具', TOOL_DIR, '../../packages/llm_ui_engine')

print()
if ok:
    print('全部通过 \u2705  包已正确挂载。')
    print('若 analyze 仍报 Undefined class，请重启 IDE 的 Dart Analysis Server')
    print('（VS Code: Ctrl+Shift+P → "Dart: Restart Analysis Server"）。')
else:
    print('存在问题，请按上面的 → 提示处理。')
    print()
    print('标准修复顺序（三步都要跑）：')
    print('  cd packages/llm_ui_engine && flutter pub get')
    print('  cd ../..                  && flutter pub get')
    print('  cd ToolofPC/llm_card_converter && flutter pub get')
sys.exit(0 if ok else 1)
