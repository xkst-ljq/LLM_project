# -*- coding: utf-8 -*-
"""生成多页面 RPG 跑团卡：「灰港迷雾」。

页面结构（scene 一套 UI 内含 5 页）：
    主菜单(base) ⇄ 角色卡(base) ⇄ 背包(base) ⇄ 日志(base)
        └ 骰子面板(overlay，挂在主菜单下)

导航方式（**运行时只支持这两种**，已核实源码）：
  1. page.gestures：滑动方向 → 目标页
  2. 点叠加页外部 → 自动回父页
`button_to_page_route` 方案虽在方案表里登记，但运行时无消费方，
按钮点了不会切页——所以导航一律用手势。
"""
import json, time, zipfile, os

BASE = int(time.time() * 1000)
_n = [0]
def uid(p):
    _n[0] += 1
    return f"{p}_{BASE}_{_n[0]}"

# ---------- 状态字段 ----------
F_HP, F_MP, F_GOLD = "rpg_hp", "rpg_mp", "rpg_gold"
F_LV, F_XP = "rpg_lv", "rpg_xp"
F_LOC, F_STATE = "rpg_loc", "rpg_state"
F_CLUE = "rpg_clue"

status_fields = [
    {"id": F_HP,   "name": "生命值", "type": "number", "initial_value": "28",
     "min_value": 0.0, "max_value": 30.0, "pin_side": "left",  "order": 0, "owner": "player"},
    {"id": F_MP,   "name": "精神值", "type": "number", "initial_value": "12",
     "min_value": 0.0, "max_value": 20.0, "pin_side": "left",  "order": 1, "owner": "player"},
    {"id": F_GOLD, "name": "银币",   "type": "number", "initial_value": "45",
     "min_value": 0.0, "max_value": 9999.0, "pin_side": "right", "order": 2, "owner": "player"},
    {"id": F_LV,   "name": "等级",   "type": "number", "initial_value": "3",
     "min_value": 1.0, "max_value": 20.0, "pin_side": "none", "order": 3, "owner": "player"},
    {"id": F_XP,   "name": "经验",   "type": "number", "initial_value": "140",
     "min_value": 0.0, "max_value": 300.0, "pin_side": "none", "order": 4, "owner": "player"},
    {"id": F_LOC,  "name": "当前位置", "type": "text", "initial_value": "灰港·锚链街",
     "min_value": None, "max_value": None, "pin_side": "none", "order": 5, "owner": "neutral"},
    {"id": F_STATE,"name": "身体状态", "type": "text", "initial_value": "尚可",
     "min_value": None, "max_value": None, "pin_side": "none", "order": 6, "owner": "player"},
    {"id": F_CLUE, "name": "线索数",   "type": "number", "initial_value": "2",
     "min_value": 0.0, "max_value": 99.0, "pin_side": "none", "order": 7, "owner": "neutral"},
]

# ---------- 构造工具 ----------
def channel(label, kind, target_id="", *, read="prompt", write="none",
            notify="silent", template="", section="ui_data",
            source_id="", field_type="number", pending=""):
    c = {"semanticLabel": label, "semanticPath": label,
         "semanticSource": "manual", "labelElementId": "",
         "sourceComponentId": source_id, "sourcePort": "current",
         "targetKind": kind, "targetId": target_id,
         "pendingName": pending, "displayNameSnapshot": label,
         "visibility": "ui_only",
         "llmReadPolicy": read, "llmWritePolicy": write,
         "notifyStyle": notify, "promptSection": section,
         "fieldType": field_type}
    if template: c["notifyTemplate"] = template
    return c

def module(mid, name, mtype, props, *, color=0xFFB8860B, material=0,
           shape=1, radius=10.0, opacity=1.0):
    return {"id": mid, "name": name, "type": mtype, "material": material,
            "shape": shape, "color": color, "opacity": opacity,
            "borderRadius": radius, "properties": props,
            "boundVariable": "", "statusFieldMirrorKey": "",
            "displayExpression": "", "linkedSources": []}

def element(eid, mod, x, y, w, h, *, layer=0, parent=None):
    return {"id": eid, "isComposite": False,
            "offset": {"x": float(x), "y": float(y)},
            "size": {"width": float(w), "height": float(h)},
            "layerIndex": layer, "parentSurfaceId": parent,
            "rotation": 0.0, "layoutLocked": False, "sealed": False,
            "module": mod}

def gesture(direction, target_page_id, *, action="switch_base_page",
            transition="base_slide", duration=220):
    return {"direction": direction, "action": action,
            "targetPageId": target_page_id,
            "transition": transition, "durationMs": duration}

def page(pid, name, ptype, elements, *, parent=None, order=0, gestures=None):
    return {"id": pid, "name": name, "type": ptype, "parentPageId": parent,
            "sortOrder": order, "elements": elements,
            "gestures": gestures or [], "propertyOverrides": []}

# 机房区：PCB 左外侧，列宽 200、行高 64、每列 8 个
_logic = [0]
def reset_logic(): _logic[0] = 0
def logic_pos():
    i = _logic[0]; _logic[0] += 1
    col, row = divmod(i, 8)
    return -224 - col * 212, row * 64

def linker(name, scheme, src, dst, params=None, *, priority=5):
    d = {"scheme": scheme, "sourceModuleId": src, "targetModuleId": dst,
         "enabled": True, "priority": priority}
    if params: d["params"] = params
    x, y = logic_pos()
    return element(uid("el"), module(uid("m"), name, "linker",
        {"linker": d}, color=0xFF00ACC1, radius=8.0), x, y, 132, 44)

def math_node(name, op, *, a=0.0, b=0.0, c=0.0):
    x, y = logic_pos()
    return element(uid("el"), module(uid("m"), name, "math_node",
        {"operation": op, "paramA": a, "paramB": b, "paramC": c},
        color=0xFF7E57C2, radius=8.0), x, y, 180, 44)


def button_group(label, x, y, w, h, *, parent, layer, color=0xFF9B3B2E,
                 text_color=0xFFF2E8D5, radius=8.0, key_action=False,
                 sends_message=False, font=13.0):
    """一组「可见按钮」：surface 底 + text 文字 + button 热区。

    button 运行时是 `SizedBox.expand()`——**纯透明热区，自己不显形**
    （见 UIRenderer._buildButton）。所以「点击凹陷」必须作用在它下面
    垫的那块 surface 上，不能连到整页背景——否则点一下整个页面在凹，
    而不是这个按钮。

    返回 (元素列表, surface_id, button_id)，
    调用方用后两者建一条 click_to_surface_press。
    """
    face = element(uid("el"), module(uid("m"), label + "底", "surface",
        {}, color=color, material=0, radius=radius, opacity=1.0),
        x, y, w, h, layer=layer, parent=parent)
    cap = element(uid("el"), module(uid("m"), label + "字", "text",
        {"text": label, "fontSize": font, "textAlign": "center"},
        color=text_color),
        x, y + (h - font - 6) / 2, w, font + 6, layer=layer + 1, parent=parent)
    props = {"hitArea": True}
    if key_action: props["keyAction"] = True
    if sends_message: props["sendsMessage"] = True
    hot = element(uid("el"), module(uid("m"), label, "button",
        props, color=color, radius=radius),
        x, y, w, h, layer=layer + 2, parent=parent)
    return [face, cap, hot], face["id"], hot["id"]

# 羊皮纸色板：浅底深字，避开上一版深底黑字的可读性问题
INK    = 0xFF2E2419   # 主文字
INK2   = 0xFF6B5B45   # 次要文字
PARCH  = 0xFFF2E8D5   # 纸面
PARCH2 = 0xFFE6D8BE   # 纸面（深一档）
GOLD   = 0xFFB8860B
BLOOD  = 0xFF9B3B2E
GREEN  = 0xFF4A7C4E
BLUE   = 0xFF3E6B8C

W, H = 380, 660
PAGES = {}   # 先占 id，供手势互相引用
for k in ("home", "sheet", "bag", "log", "dice"):
    PAGES[k] = uid("pg")

def bg_panel(layer_name="羊皮纸"):
    return element(uid("el"), module(uid("m"), layer_name, "surface",
        {"is_overlay_container": True}, color=PARCH, material=0,
        radius=0.0, opacity=1.0), 0, 0, W, H)

def title(txt, parent, *, y=22, color=INK, size=19.0, layer=1):
    return element(uid("el"), module(uid("m"), "标题", "text",
        {"text": txt, "fontSize": size, "textAlign": "center"}, color=color),
        20, y, W - 40, 26, layer=layer, parent=parent)

def hint(txt, parent, *, y=H-34, layer=90):
    return element(uid("el"), module(uid("m"), "翻页提示", "text",
        {"text": txt, "fontSize": 10.0, "textAlign": "center"}, color=INK2),
        20, y, W - 40, 16, layer=layer, parent=parent)

def divider(parent, y, *, layer=2):
    return element(uid("el"), module(uid("m"), "分隔", "line",
        {"axis": "horizontal", "lineStyle": "solid", "thickness": 1.0},
        color=0x33000000), 24, y, W - 48, 2, layer=layer, parent=parent)

# ============================================================
# 页 1：主菜单 —— 冒险主界面
# ============================================================
reset_logic()
h_bg = bg_panel(); HB = h_bg["id"]
h_title = title("灰港迷雾", HB, size=22.0, color=BLOOD)
h_sub = element(uid("el"), module(uid("m"), "副标题", "text",
    {"text": "第三章 · 锚链街的雾", "fontSize": 11.0, "textAlign": "center"},
    color=INK2), 20, 50, W-40, 16, layer=2, parent=HB)
h_div = divider(HB, 74, layer=3)

# 位置
m_loc = module(uid("m"), "位置", "text",
    {"text": "灰港·锚链街", "fontSize": 13.0, "textAlign": "left",
     "dataChannel": channel("当前位置", "status_field", F_LOC,
        read="prompt", write="suggest_replace", notify="toast",
        field_type="text")}, color=BLUE)
h_loc = element(uid("el"), m_loc, 24, 86, 230, 20, layer=4, parent=HB)
m_loc["properties"]["dataChannel"]["sourceComponentId"] = h_loc["id"]

# HP / MP
m_hp = module(uid("m"), "生命条", "progress",
    {"current": 28.0, "min": 0.0, "max": 30.0, "progressShape": "bar",
     "strokeWidth": 12.0, "trackColor": 0x22000000,
     "dataChannel": channel("生命值", "status_field", F_HP,
        read="prompt", write="suggest_delta", notify="dialog",
        template="生命值 {old} → {new}")}, color=BLOOD)
h_hp = element(uid("el"), m_hp, 24, 118, 200, 16, layer=5, parent=HB)
m_hp["properties"]["dataChannel"]["sourceComponentId"] = h_hp["id"]
h_hp_lb = element(uid("el"), module(uid("m"), "HP标签", "text",
    {"text": "HP", "fontSize": 10.0}, color=INK2),
    232, 118, 30, 16, layer=6, parent=HB)

m_mp = module(uid("m"), "精神条", "progress",
    {"current": 12.0, "min": 0.0, "max": 20.0, "progressShape": "bar",
     "strokeWidth": 12.0, "trackColor": 0x22000000,
     "dataChannel": channel("精神值", "status_field", F_MP,
        read="prompt", write="suggest_delta", notify="toast",
        template="精神值 {old} → {new}")}, color=BLUE)
h_mp = element(uid("el"), m_mp, 24, 142, 200, 16, layer=7, parent=HB)
m_mp["properties"]["dataChannel"]["sourceComponentId"] = h_mp["id"]
h_mp_lb = element(uid("el"), module(uid("m"), "MP标签", "text",
    {"text": "SAN", "fontSize": 10.0}, color=INK2),
    232, 142, 34, 16, layer=8, parent=HB)

# 银币 / 线索
m_gold = module(uid("m"), "银币", "text",
    {"text": "45", "fontSize": 16.0, "textAlign": "right",
     "dataChannel": channel("银币", "status_field", F_GOLD,
        read="prompt", write="suggest_delta", notify="dialog",
        template="银币 {old} → {new}")}, color=GOLD)
h_gold = element(uid("el"), m_gold, 274, 116, 80, 22, layer=9, parent=HB)
m_gold["properties"]["dataChannel"]["sourceComponentId"] = h_gold["id"]
h_gold_lb = element(uid("el"), module(uid("m"), "银币标签", "text",
    {"text": "银币", "fontSize": 9.0, "textAlign": "right"}, color=INK2),
    274, 138, 80, 12, layer=10, parent=HB)

m_clue = module(uid("m"), "线索", "text",
    {"text": "2", "fontSize": 16.0, "textAlign": "right",
     "dataChannel": channel("线索数", "status_field", F_CLUE,
        read="prompt", write="suggest_delta", notify="toast",
        template="获得线索！共 {new} 条")}, color=GREEN)
h_clue = element(uid("el"), m_clue, 274, 152, 80, 22, layer=11, parent=HB)
m_clue["properties"]["dataChannel"]["sourceComponentId"] = h_clue["id"]
h_clue_lb = element(uid("el"), module(uid("m"), "线索标签", "text",
    {"text": "线索", "fontSize": 9.0, "textAlign": "right"}, color=INK2),
    274, 174, 80, 12, layer=12, parent=HB)

h_div2 = divider(HB, 196, layer=13)

# 消息流
h_flow = element(uid("el"), module(uid("m"), "叙事", "message_flow",
    {"historyLimit": 0, "fontSize": 12.5, "showUser": True,
     "showAssistant": True, "richText": True,
     "userBubbleColor": 0xFFDCD2BC, "assistantBubbleColor": 0xFFEDE3CE,
     "bubbleRadius": 10.0}, color=PARCH2, material=0, radius=10.0),
    20, 206, W-40, 300, layer=14, parent=HB)

# 行动输入
# input 自己标 sendsMessage：回车即发送框内文字。
#
# **不能靠按钮发送输入框内容**——引擎里所有指向 button 的方案
# 都是「启用/可见」控制，没有一条能把值传给 button；
# _resolveSendText 对 button 回落到按钮自身文字，
# 结果就是点「行动」只发出「行动」两个字。
h_input = element(uid("el"), module(uid("m"), "行动输入", "input",
    {"placeholder": "写下你的行动，回车发送", "text": "", "committedValue": "",
     "maxLength": 300, "sendsMessage": True},
    color=PARCH2, material=0, radius=8.0),
    20, 518, W-40, 44, layer=15, parent=HB)
# 退出（scene 必须有 keyAction）
h_exit_els, h_exit_face, h_exit_id = button_group("收起面板", 20, 572, W-40, 36,
    parent=HB, layer=19, color=INK2, key_action=True, font=12.0)

h_hint = hint("← 角色卡     下滑掷骰     行囊 →", HB, y=618)

# 按压动画作用在按钮**自己的** surface 底上，不是整页背景。
lk_h3 = linker("收起→按压", "click_to_surface_press", h_exit_id, h_exit_face)

home = page(PAGES["home"], "主菜单", "base",
    [h_bg, h_title, h_sub, h_div, h_loc, h_hp, h_hp_lb, h_mp, h_mp_lb,
     h_gold, h_gold_lb, h_clue, h_clue_lb, h_div2, h_flow, h_input]
    + h_exit_els + [h_hint, lk_h3],
    order=0,
    gestures=[
        gesture("swipe_right", PAGES["sheet"]),
        gesture("swipe_left",  PAGES["bag"]),
        # 不用 swipe_up：消息流占了页面中段，玩家上滑是想看历史记录，
        # 占用它必然误触（用户反馈）。改用下滑——没有别的用途。
        gesture("swipe_down",  PAGES["dice"],
                action="open_overlay", transition="overlay_fade", duration=180),
    ])

# ============================================================
# 页 2：角色卡 —— 属性与经验
# ============================================================
reset_logic()
s_bg = bg_panel("角色卡纸"); SB = s_bg["id"]
s_title = title("角色卡", SB, color=INK)
s_div = divider(SB, 56, layer=2)

s_name = element(uid("el"), module(uid("m"), "姓名", "text",
    {"text": "无名的调查员", "fontSize": 15.0, "textAlign": "left"}, color=INK),
    24, 70, 220, 22, layer=3, parent=SB)

m_lv = module(uid("m"), "等级", "text",
    {"text": "3", "fontSize": 26.0, "textAlign": "right",
     "dataChannel": channel("等级", "status_field", F_LV,
        read="prompt", write="suggest_delta", notify="dialog",
        template="🎉 升到 {new} 级！")}, color=GOLD)
s_lv = element(uid("el"), m_lv, 274, 66, 80, 32, layer=4, parent=SB)
m_lv["properties"]["dataChannel"]["sourceComponentId"] = s_lv["id"]
s_lv_lb = element(uid("el"), module(uid("m"), "等级标签", "text",
    {"text": "LV", "fontSize": 9.0, "textAlign": "right"}, color=INK2),
    274, 98, 80, 12, layer=5, parent=SB)

m_xp = module(uid("m"), "经验条", "progress",
    {"current": 140.0, "min": 0.0, "max": 300.0, "progressShape": "bar",
     "strokeWidth": 10.0, "trackColor": 0x22000000,
     "dataChannel": channel("经验", "status_field", F_XP,
        read="prompt", write="suggest_delta", notify="toast",
        template="经验 +{new}")}, color=GREEN)
s_xp = element(uid("el"), m_xp, 24, 120, W-48, 14, layer=6, parent=SB)
m_xp["properties"]["dataChannel"]["sourceComponentId"] = s_xp["id"]
s_xp_lb = element(uid("el"), module(uid("m"), "经验标签", "text",
    {"text": "EXP", "fontSize": 9.0}, color=INK2),
    24, 136, 60, 12, layer=7, parent=SB)

s_div2 = divider(SB, 158, layer=8)

# 三围属性：滑块 + 求和（演示 sum_to_display）
attrs = [("体质", 60.0, 190), ("感知", 75.0, 240), ("意志", 45.0, 290)]
attr_els = []
for nm, val, yy in attrs:
    lb = element(uid("el"), module(uid("m"), nm+"标签", "text",
        {"text": nm, "fontSize": 12.0}, color=INK),
        24, yy, 50, 18, layer=9, parent=SB)
    sl = element(uid("el"), module(uid("m"), nm, "slider",
        {"current": val, "min": 0.0, "max": 100.0, "step": 5.0,
         "committedValue": val}, color=BLUE),
        80, yy-6, 200, 32, layer=10, parent=SB)
    vt = element(uid("el"), module(uid("m"), nm+"值", "text",
        {"text": str(int(val)), "fontSize": 12.0, "textAlign": "right"},
        color=INK2), 288, yy, 60, 18, layer=11, parent=SB)
    attr_els += [lb, sl, vt]

s_total_lb = element(uid("el"), module(uid("m"), "总点数标签", "text",
    {"text": "已分配点数", "fontSize": 11.0}, color=INK2),
    24, 336, 100, 16, layer=12, parent=SB)
s_total = element(uid("el"), module(uid("m"), "总点数", "text",
    {"text": "180", "fontSize": 14.0, "textAlign": "right"}, color=GOLD),
    260, 334, 88, 20, layer=13, parent=SB)

s_div3 = divider(SB, 364, layer=14)

m_state = module(uid("m"), "状态", "text",
    {"text": "尚可", "fontSize": 13.0,
     "dataChannel": channel("身体状态", "status_field", F_STATE,
        read="prompt", write="suggest_replace", notify="toast",
        field_type="text")}, color=INK)
s_state = element(uid("el"), m_state, 24, 378, 150, 20, layer=15, parent=SB)
m_state["properties"]["dataChannel"]["sourceComponentId"] = s_state["id"]
s_state_lb = element(uid("el"), module(uid("m"), "状态标签", "text",
    {"text": "身体状态", "fontSize": 9.0}, color=INK2),
    24, 398, 100, 12, layer=16, parent=SB)

s_note = element(uid("el"), module(uid("m"), "备注", "text",
    {"text": "左臂旧伤在阴雨天会隐隐作痛。\n对海腥味异常敏感。",
     "fontSize": 11.5, "overflow": "wrap"}, color=INK2),
    24, 424, W-48, 60, layer=17, parent=SB)

s_exit_els, s_exit_face, s_exit_id = button_group("收起面板", 20, 566, W-40, 36,
    parent=SB, layer=18, color=INK2, key_action=True, font=12.0)
lk_s_exit = linker("收起→按压", "click_to_surface_press", s_exit_id, s_exit_face)
s_hint = hint("← 日志            主界面 →", SB, y=618)

# 三条滑块各连一条 sum_to_display 到同一个文本 = 点数汇总
lk_s = [linker(f"{nm}→总点数", "sum_to_display", attr_els[i*3+1]["id"], s_total["id"])
        for i, (nm, _, _) in enumerate(attrs)]
lk_s2 = [linker(f"{nm}→数值", "slider_to_text", attr_els[i*3+1]["id"], attr_els[i*3+2]["id"])
         for i, (nm, _, _) in enumerate(attrs)]

sheet = page(PAGES["sheet"], "角色卡", "base",
    [s_bg, s_title, s_div, s_name, s_lv, s_lv_lb, s_xp, s_xp_lb, s_div2]
    + attr_els +
    [s_total_lb, s_total, s_div3, s_state, s_state_lb, s_note]
    + s_exit_els + [s_hint, lk_s_exit] + lk_s + lk_s2,
    order=1,
    gestures=[
        gesture("swipe_left",  PAGES["home"]),
        gesture("swipe_right", PAGES["log"]),
    ])

# ============================================================
# 页 3：背包 —— 物品与购买
# ============================================================
reset_logic()
b_bg = bg_panel("背包纸"); BB = b_bg["id"]
b_title = title("行囊", BB, color=INK)
b_div = divider(BB, 56, layer=2)

items = [("防水火柴 ×12", "照明 / 引火", 78),
         ("黄铜怀表",     "已停在 3:47", 126),
         ("褪色海图",     "标着一处未名岛", 174),
         ("止血绷带 ×3",  "回复 5 点生命", 222)]
item_els = []
for nm, desc, yy in items:
    card = element(uid("el"), module(uid("m"), nm+"底", "surface",
        {}, color=PARCH2, material=0, radius=8.0, opacity=1.0),
        24, yy, W-48, 40, layer=3, parent=BB)
    t1 = element(uid("el"), module(uid("m"), nm, "text",
        {"text": nm, "fontSize": 12.5}, color=INK),
        36, yy+6, 220, 18, layer=4, parent=BB)
    t2 = element(uid("el"), module(uid("m"), nm+"说明", "text",
        {"text": desc, "fontSize": 10.0}, color=INK2),
        36, yy+22, 240, 14, layer=5, parent=BB)
    item_els += [card, t1, t2]

b_div2 = divider(BB, 278, layer=6)

# 购买：数量滑块 × 单价 → 总价（math_node）
b_shop_lb = element(uid("el"), module(uid("m"), "商店标题", "text",
    {"text": "锚链街杂货铺 · 灯油 8 银/瓶", "fontSize": 12.0}, color=INK),
    24, 292, W-48, 18, layer=7, parent=BB)

m_qty = module(uid("m"), "数量", "slider",
    {"current": 1.0, "min": 0.0, "max": 10.0, "step": 1.0,
     "committedValue": 1.0,
     # 数量必须进 Prompt，否则 KP 不知道玩家买了几瓶——
     # 按钮只能发固定文字，带不上数字。
     "dataChannel": channel("购买数量", "session_var",
        read="prompt", write="none", notify="silent")}, color=GOLD)
b_qty = element(uid("el"), m_qty, 24, 318, 210, 34, layer=8, parent=BB)
m_qty["properties"]["dataChannel"]["sourceComponentId"] = b_qty["id"]
b_qty_lb = element(uid("el"), module(uid("m"), "数量标签", "text",
    {"text": "数量", "fontSize": 10.0}, color=INK2),
    24, 352, 60, 14, layer=9, parent=BB)

b_math = math_node("总价 = 数量 x 8", "*", a=1.0, b=8.0)
b_cost = element(uid("el"), module(uid("m"), "总价", "text",
    {"text": "8", "fontSize": 16.0, "textAlign": "right"}, color=BLOOD),
    250, 320, 100, 24, layer=10, parent=BB)
b_cost_lb = element(uid("el"), module(uid("m"), "总价标签", "text",
    {"text": "共需（银）", "fontSize": 9.0, "textAlign": "right"}, color=INK2),
    250, 344, 100, 12, layer=11, parent=BB)

# 按钮只能发出固定文字（引擎限制，见上）。
# 数量本身通过数据通道进 Prompt，KP 读得到，所以文案写成半句话，
# 让「买 N 瓶」这个信息由通道补全，而不是指望按钮带上数字。
b_buy_els, b_buy_face, b_buy_id = button_group("按当前数量向店主买下灯油",
    24, 376, W-48, 40,
    parent=BB, layer=12, color=GREEN, sends_message=True, font=12.0)

# 开关：是否公开携带武器（演示 boolean_to_visible）
b_arm = element(uid("el"), module(uid("m"), "明面持械", "switch",
    {"value": False}, color=BLOOD),
    24, 432, 70, 34, layer=13, parent=BB)
b_arm_lb = element(uid("el"), module(uid("m"), "持械标签", "text",
    {"text": "明面持械", "fontSize": 11.0}, color=INK),
    100, 440, 90, 18, layer=14, parent=BB)
b_warn = element(uid("el"), module(uid("m"), "警告", "text",
    {"text": "⚠ 街上巡警会注意到你", "fontSize": 10.5}, color=BLOOD),
    100, 458, 240, 16, layer=15, parent=BB)

b_exit_els, b_exit_face, b_exit_id = button_group("收起面板", 20, 566, W-40, 36,
    parent=BB, layer=17, color=INK2, key_action=True, font=12.0)
b_hint = hint("← 主界面", BB, y=618)

lk_b1 = linker("数量→总价参数", "slider_commit_to_math_param",
               b_qty["id"], b_math["id"], {"targetParam": "paramA"})
lk_b2 = linker("总价→文本", "result_to_text", b_math["id"], b_cost["id"])
lk_b3 = linker("持械→显示警告", "boolean_to_visible",
               b_arm["id"], b_warn["id"])
lk_b4 = linker("购买→按压", "click_to_surface_press", b_buy_id, b_buy_face)
lk_b5 = linker("收起→按压", "click_to_surface_press", b_exit_id, b_exit_face)

bag = page(PAGES["bag"], "行囊", "base",
    [b_bg, b_title, b_div] + item_els +
    [b_div2, b_shop_lb, b_qty, b_qty_lb, b_cost, b_cost_lb]
    + b_buy_els +
    [b_arm, b_arm_lb, b_warn] + b_exit_els +
    [b_hint, b_math, lk_b1, lk_b2, lk_b3, lk_b4, lk_b5],
    order=2,
    gestures=[gesture("swipe_right", PAGES["home"])])

# ============================================================
# 页 4：日志 —— 线索记录
# ============================================================
reset_logic()
l_bg = bg_panel("日志纸"); LB = l_bg["id"]
l_title = title("调查日志", LB, color=INK)
l_div = divider(LB, 56, layer=2)

logs = [("十月三日 · 雨", "码头工头说，那晚看见货舱里有灯光。\n但记录上那天没有船靠港。", 74),
        ("十月五日 · 雾", "在废弃灯塔捡到半张海图，\n边角有咬痕，不像人牙。", 174),
        ("十月六日 · 阴", "老渔夫拒绝谈论「那件事」，\n提到时手一直在抖。", 274)]
log_els = []
for hd, body, yy in logs:
    card = element(uid("el"), module(uid("m"), "日志底", "surface",
        {}, color=PARCH2, material=0, radius=8.0, opacity=1.0),
        24, yy, W-48, 90, layer=3, parent=LB)
    t1 = element(uid("el"), module(uid("m"), "日期", "text",
        {"text": hd, "fontSize": 11.0}, color=BLOOD),
        36, yy+8, 260, 16, layer=4, parent=LB)
    t2 = element(uid("el"), module(uid("m"), "内容", "text",
        {"text": body, "fontSize": 11.5, "overflow": "wrap"}, color=INK),
        36, yy+28, W-72, 54, layer=5, parent=LB)
    log_els += [card, t1, t2]

l_filter = element(uid("el"), module(uid("m"), "筛选", "select",
    {"options": [{"label": "全部", "value": "all"},
                 {"label": "人物", "value": "npc"},
                 {"label": "地点", "value": "place"},
                 {"label": "物证", "value": "item"}],
     "current": "all", "defaultValue": "all"}, color=BLUE, radius=8.0),
    24, 386, 150, 34, layer=6, parent=LB)
l_filter_lb = element(uid("el"), module(uid("m"), "筛选标签", "text",
    {"text": "分类", "fontSize": 10.0}, color=INK2),
    24, 370, 60, 14, layer=7, parent=LB)

l_note = element(uid("el"), module(uid("m"), "新线索", "input",
    {"placeholder": "记下新发现，回车提交", "text": "", "committedValue": "",
     "maxLength": 200, "sendsMessage": True},
    color=PARCH2, material=0, radius=8.0),
    24, 432, W-48, 40, layer=8, parent=LB)

l_exit_els, l_exit_face, l_exit_id = button_group("收起面板", 20, 566, W-40, 36,
    parent=LB, layer=12, color=INK2, key_action=True, font=12.0)
l_hint = hint("角色卡 →", LB, y=618)

lk_l3 = linker("收起→按压", "click_to_surface_press", l_exit_id, l_exit_face)

log = page(PAGES["log"], "日志", "base",
    [l_bg, l_title, l_div] + log_els +
    [l_filter_lb, l_filter, l_note] + l_exit_els + [l_hint, lk_l3],
    order=3,
    gestures=[gesture("swipe_left", PAGES["sheet"])])

# ============================================================
# 页 5：骰子面板（叠加页，点外部返回）
# ============================================================
reset_logic()
# 叠加页的容器面：点它以外的区域会自动回父页
d_card = element(uid("el"), module(uid("m"), "骰子面板", "surface",
    {"is_overlay_container": True}, color=PARCH, material=0,
    radius=16.0, opacity=0.98), 40, 150, 300, 340)
DC = d_card["id"]

d_title = element(uid("el"), module(uid("m"), "标题", "text",
    {"text": "检定", "fontSize": 18.0, "textAlign": "center"}, color=BLOOD),
    56, 170, 268, 24, layer=1, parent=DC)
d_sub = element(uid("el"), module(uid("m"), "说明", "text",
    {"text": "选择难度后掷 1d20", "fontSize": 11.0, "textAlign": "center"},
    color=INK2), 56, 196, 268, 16, layer=2, parent=DC)

m_diff = module(uid("m"), "难度", "select",
    {"options": [{"label": "简单 (DC 8)",  "value": "8"},
                 {"label": "普通 (DC 12)", "value": "12"},
                 {"label": "困难 (DC 16)", "value": "16"},
                 {"label": "极难 (DC 20)", "value": "20"}],
     "current": "12", "defaultValue": "12",
     "dataChannel": channel("检定难度", "session_var",
        read="prompt", write="none", notify="silent", field_type="text")},
    color=BLUE, radius=8.0)
d_diff = element(uid("el"), m_diff, 64, 224, 252, 36, layer=3, parent=DC)
m_diff["properties"]["dataChannel"]["sourceComponentId"] = d_diff["id"]

d_mod_lb = element(uid("el"), module(uid("m"), "调整值标签", "text",
    {"text": "属性调整值", "fontSize": 10.0}, color=INK2),
    64, 270, 100, 14, layer=4, parent=DC)
m_mod = module(uid("m"), "调整值", "slider",
    {"current": 2.0, "min": -5.0, "max": 10.0, "step": 1.0,
     "committedValue": 2.0,
     "dataChannel": channel("检定调整值", "session_var",
        read="prompt", write="none", notify="silent")}, color=GOLD)
d_mod = element(uid("el"), m_mod, 64, 286, 180, 32, layer=5, parent=DC)
m_mod["properties"]["dataChannel"]["sourceComponentId"] = d_mod["id"]
d_mod_v = element(uid("el"), module(uid("m"), "调整值数", "text",
    {"text": "2", "fontSize": 14.0, "textAlign": "right"}, color=INK),
    252, 292, 64, 20, layer=6, parent=DC)

d_hint2 = element(uid("el"), module(uid("m"), "结果提示", "text",
    {"text": "掷骰结果由主持人判定", "fontSize": 10.5, "textAlign": "center"},
    color=INK2), 64, 328, 252, 16, layer=7, parent=DC)

d_roll_els, d_roll_face, d_roll_id = button_group("按当前难度掷骰", 64, 352, 252, 46,
    parent=DC, layer=8, color=BLOOD, radius=10.0, sends_message=True, font=14.0)

d_tip = element(uid("el"), module(uid("m"), "关闭提示", "text",
    {"text": "点面板外任意处关闭", "fontSize": 9.5, "textAlign": "center"},
    color=INK2), 64, 408, 252, 14, layer=9, parent=DC)

lk_d1 = linker("调整值→数字", "slider_to_text", d_mod["id"], d_mod_v["id"])
lk_d2 = linker("掷骰→按压", "click_to_surface_press", d_roll_id, d_roll_face)

dice = page(PAGES["dice"], "骰子面板", "overlay",
    [d_card, d_title, d_sub, d_diff, d_mod_lb, d_mod, d_mod_v, d_hint2]
    + d_roll_els + [d_tip, lk_d1, lk_d2],
    parent=PAGES["home"], order=0)

# ============================================================
# 组装
# ============================================================
scene = json.dumps({
    "id": uid("ui"), "name": "跑团面板", "mode": "scene",
    "elements": "[]",
    "pages": json.dumps([home, sheet, bag, log, dice], ensure_ascii=False),
    "pcbWidth": float(W), "pcbHeight": float(H),
    "pcbColorValue": 0xFFDCCFB4, "pcbRadius": 0.0, "pcbRounded": False,
    "createdAt": BASE,
}, ensure_ascii=False)

# ---- 常驻挂件：随时可见的血条 ----
reset_logic()
k_bg = element(uid("el"), module(uid("m"), "挂件底", "surface",
    {"is_overlay_container": True}, color=0xF2F2E8D5, material=0,
    radius=12.0, opacity=0.95), 0, 0, 200, 96)
KB = k_bg["id"]
k_t = element(uid("el"), module(uid("m"), "标题", "text",
    {"text": "调查员", "fontSize": 10.0}, color=INK2),
    12, 8, 80, 14, layer=1, parent=KB)

m_khp = module(uid("m"), "血条", "progress",
    {"current": 28.0, "min": 0.0, "max": 30.0, "progressShape": "bar",
     "strokeWidth": 10.0, "trackColor": 0x22000000,
     "dataChannel": channel("生命值", "status_field", F_HP,
        read="prompt", write="suggest_delta", notify="dialog",
        template="生命值 {old} → {new}")}, color=BLOOD)
k_hp = element(uid("el"), m_khp, 12, 28, 176, 12, layer=2, parent=KB)
m_khp["properties"]["dataChannel"]["sourceComponentId"] = k_hp["id"]

m_kmp = module(uid("m"), "神智条", "progress",
    {"current": 12.0, "min": 0.0, "max": 20.0, "progressShape": "bar",
     "strokeWidth": 10.0, "trackColor": 0x22000000,
     "dataChannel": channel("精神值", "status_field", F_MP,
        read="prompt", write="suggest_delta", notify="toast",
        template="精神值 {old} → {new}")}, color=BLUE)
k_mp = element(uid("el"), m_kmp, 12, 46, 176, 12, layer=3, parent=KB)
m_kmp["properties"]["dataChannel"]["sourceComponentId"] = k_mp["id"]

m_kloc = module(uid("m"), "位置", "text",
    {"text": "灰港·锚链街", "fontSize": 10.5,
     "dataChannel": channel("当前位置", "status_field", F_LOC,
        read="prompt", write="suggest_replace", notify="toast",
        field_type="text")}, color=BLUE)
k_loc = element(uid("el"), m_kloc, 12, 64, 140, 16, layer=4, parent=KB)
m_kloc["properties"]["dataChannel"]["sourceComponentId"] = k_loc["id"]

k_close_els, k_close_face, k_close_id = button_group("×", 160, 62, 28, 20,
    parent=KB, layer=5, color=INK2, radius=6.0, key_action=True, font=11.0)
lk_k = linker("收起→按压", "click_to_surface_press", k_close_id, k_close_face)

sticky = json.dumps({
    "id": uid("ui"), "name": "调查员状态", "mode": "extra_sticky",
    "elements": "[]",
    "pages": json.dumps([page(uid("pg"), "主菜单", "base",
        [k_bg, k_t, k_hp, k_mp, k_loc] + k_close_els + [lk_k])],
        ensure_ascii=False),
    "pcbWidth": 200.0, "pcbHeight": 96.0,
    "pcbColorValue": 0x00000000, "pcbRadius": 12.0, "pcbRounded": True,
    "createdAt": BASE,
}, ensure_ascii=False)

# ---- 开场白 ----
reset_logic()
o_bg = element(uid("el"), module(uid("m"), "开场纸", "surface",
    {"is_overlay_container": True}, color=PARCH, material=0,
    radius=16.0, opacity=0.98), 0, 0, 320, 400)
OB = o_bg["id"]
o_t = element(uid("el"), module(uid("m"), "标题", "text",
    {"text": "灰港迷雾", "fontSize": 22.0, "textAlign": "center"}, color=BLOOD),
    20, 30, 280, 28, layer=1, parent=OB)
o_s = element(uid("el"), module(uid("m"), "副标题", "text",
    {"text": "一场三人份的调查，如今只剩你", "fontSize": 11.0,
     "textAlign": "center"}, color=INK2),
    20, 60, 280, 16, layer=2, parent=OB)
o_b = element(uid("el"), module(uid("m"), "正文", "text",
    {"text": "雾从海面爬上来，吞掉了灯塔的光。\n\n"
             "你握着那半张海图站在锚链街口。\n"
             "身后是唯一还亮着灯的旅店，\n身前是十月的灰港。",
     "fontSize": 12.5, "textAlign": "center", "overflow": "wrap"},
    color=INK), 24, 88, 272, 110, layer=3, parent=OB)

m_pname = module(uid("m"), "调查员名", "input",
    {"placeholder": "你的名字", "text": "", "committedValue": "", "maxLength": 20,
     "dataChannel": channel("调查员姓名", "session_var",
        read="prompt", write="none", notify="silent",
        section="core_setting", field_type="text")},
    color=PARCH2, material=0, radius=8.0)
o_name = element(uid("el"), m_pname, 30, 212, 260, 42, layer=4, parent=OB)
m_pname["properties"]["dataChannel"]["sourceComponentId"] = o_name["id"]

m_prof = module(uid("m"), "职业", "select",
    {"options": [{"label": "记者", "value": "reporter"},
                 {"label": "医师", "value": "doctor"},
                 {"label": "水手", "value": "sailor"},
                 {"label": "学者", "value": "scholar"}],
     "current": "reporter", "defaultValue": "reporter",
     "dataChannel": channel("调查员职业", "status_field", "",
        read="prompt", write="none", notify="silent",
        section="core_setting", field_type="text", pending="调查员职业")},
    color=BLUE, radius=8.0)
o_prof = element(uid("el"), m_prof, 30, 266, 260, 38, layer=5, parent=OB)
m_prof["properties"]["dataChannel"]["sourceComponentId"] = o_prof["id"]

o_go_els, o_go_face, o_go_id = button_group("走进雾里", 30, 322, 260, 46,
    parent=OB, layer=6, color=BLOOD, radius=10.0, key_action=True, font=14.0)

lk_o1 = linker("填名才能启程", "input_nonempty_to_button_enable",
               o_name["id"], o_go_id)
lk_o2 = linker("启程→按压", "click_to_surface_press", o_go_id, o_go_face)

opening = json.dumps({
    "id": uid("ui"), "name": "开场白", "mode": "opening",
    "elements": "[]",
    "pages": json.dumps([page(uid("pg"), "主菜单", "base",
        [o_bg, o_t, o_s, o_b, o_name, o_prof] + o_go_els + [lk_o1, lk_o2])],
        ensure_ascii=False),
    "pcbWidth": 320.0, "pcbHeight": 400.0,
    "pcbColorValue": 0x00000000, "pcbRadius": 16.0, "pcbRounded": True,
    "createdAt": BASE,
}, ensure_ascii=False)

# ============================================================
# 角色卡本体
# ============================================================
DESC = """【主持人设定】你是「灰港迷雾」这场调查跑团的 KP（主持人），不是某个角色。

世界：架空的二十世纪初港口城市灰港。终年多雾，靠捕鲸与走私维生。
教会势力衰退，海上传闻不断。这里没有明确的超自然，只有解释不清的事。

基调：克苏鲁式的悬疑，但克制。恐怖来自「信息不对称」而非怪物本身。
不要写出明确的怪物形态，让玩家自己拼凑。

当前进度：第三章。玩家的两名同伴已在第二章失踪，
线索指向十月三日夜里那艘没有记录的船。"""

SYSTEM = """你是 KP，主持「灰港迷雾」。严格遵守：

【叙事】
1. 每次回复 150~250 字。先描写场景变化，再给出可行动的方向暗示。
2. 用五感描写，尤其是气味与声音——灰港的核心意象是雾、海腥、汽笛。
3. 不替玩家做决定，不描写玩家的心理活动。

【检定】
4. 玩家做有风险的事时，要求他掷骰：说明难度 DC 与用哪项属性。
5. 玩家在骰子面板报出结果后，按成败叙述，不要重掷。
6. 大失败（1）必须有实质代价，不能只是「你失败了」。

【状态】
7. 受伤扣生命值；目睹异常扣精神值；两者都要在状态变化块里写明。
8. 精神值低于 5 时，在叙述里加入不可靠的感知细节（听见没有的声音等）。
9. 消费或获得报酬时改银币；发现新线索时线索数 +1。
10. 玩家移动到新地点时更新当前位置。
11. 经验在完成阶段目标时给 20~50；满 300 时提示升级。

【读取界面数据】
15. 每轮 Prompt 会带上界面数据段，其中：
    - 购买数量 / 检定难度 / 检定调整值 由玩家在面板上选定，
      玩家点「按当前数量买下」「按当前难度掷骰」时按这些值处理。
    - 按钮只能发出固定文字，具体数值一律从界面数据段读，不要反问玩家。

【禁止】
12. 不要主动推进剧情到玩家没参与的地方。
13. 不要一次抛出多条线索，一次一条。
14. NPC 不会主动说出关键信息，必须玩家问对问题。"""

GREETING = """<p>雾是从午后开始起的。</p>
<p>到你走出旅店时，锚链街已经只剩下十步之内看得清。街灯在雾里化成一团团发黄的光晕，远处传来汽笛，听不出方向。</p>
<p>你摸了摸口袋里那半张海图——纸角的咬痕还在。</p>
<p>街的尽头是码头，左手边是还亮着灯的杂货铺，右手边通向教堂。</p>
<p><em>（左右滑动可以查看角色卡与行囊，上滑打开检定面板）</em></p>"""

entries = [
    {"id": "e1", "group": "intro", "title": "身份",
     "content": "本卡为跑团主持（KP），玩家扮演调查员。", "enabled": True, "order": 0},
    {"id": "e2", "group": "detail", "title": "世界观",
     "content": "二十世纪初架空港城灰港，多雾，捕鲸与走私为生，教会衰退，海上传闻不断。",
     "enabled": True, "order": 1},
    {"id": "e3", "group": "detail", "title": "当前章节",
     "content": "第三章：两名同伴已失踪，线索指向十月三日夜里那艘无记录的船。",
     "enabled": True, "order": 2},
    {"id": "e4", "group": "detail", "title": "检定规则",
     "content": "1d20 + 属性调整值 ≥ DC 为成功。1 为大失败必有代价，20 为大成功。",
     "enabled": True, "order": 3},
    {"id": "e5", "group": "detail", "title": "主要 NPC",
     "content": "码头工头老凯（知情但要钱）；灯塔看守玛尔（疯癫，说真话）；教堂执事（隐瞒教会记录）。",
     "enabled": True, "order": 4},
]

meta = {
    "tags": ["跑团", "TRPG", "克苏鲁", "多页面UI", "UI测试"],
    "creator": "LLM Project",
    "creator_notes": "多页面 RPG 跑团测试卡。scene 内含 5 页："
                     "主菜单/角色卡/行囊/日志四个平级页用滑动手势互相跳转，"
                     "骰子面板为叠加页（主菜单上滑打开，点外部关闭）。"
                     "含 8 个状态字段、19 条 linker 连线、2 个 math_node。",
    "character_version": "1.0",
    "source_format": "llm_project",
    "post_history_instructions": "保持 KP 视角。每次回复给出可行动方向。检定必须玩家掷骰后再叙述结果。",
    "mes_example": "",
    "status_bar_fields": status_fields,
    "ui_elements": [],
    "ui_assemblies": [scene, sticky, opening],
    "text_highlight_rules": [],
}

character = {
    "id": f"char_rpg_{BASE}",
    "name": "灰港迷雾 · KP",
    "avatar": "", "card_image_path": "",
    "description": DESC,
    "system_prompt": SYSTEM,
    "world_book_id": "", "background_id": "",
    "card_type": "character",
    "entries_json": json.dumps(entries, ensure_ascii=False),
    "opening_greetings": json.dumps([GREETING], ensure_ascii=False),
    "meta_json": json.dumps(meta, ensure_ascii=False),
    "user_name": "", "user_avatar": "", "user_detail_setting": "",
}

manifest = {
    "magic": "LLM_PROJECT_ASSET_V1", "asset_type": "character_card",
    "format_version": 1,
    "exported_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
    "app": "LLM Project",
    "contains": {"user_override": False, "world_book": False},
}

out = "samples/灰港迷雾_跑团卡.llmcard"
os.makedirs("samples", exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    z.writestr("data/character.json", json.dumps(character, ensure_ascii=False, indent=2))
print("生成:", out, os.path.getsize(out), "bytes")
