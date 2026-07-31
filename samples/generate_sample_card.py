# -*- coding: utf-8 -*-
"""生成测试角色卡：赛博朋克酒保「织」。

覆盖目标：
- 状态栏字段 5 个（数值 3 / 文本 2，三种 owner）
- 常驻挂件 extra_sticky：进度条 + 状态点 + 文本，绑定状态字段
- 全屏场景 scene：面板 + 进度条 + 滑块 + 下拉 + 输入 + 按钮 + 消息流
- 开场白 opening：文本 + 输入 + 按钮
- 数据通道：status_field / session_var / card_entry 三类都有
- 通知方式：silent / toast / dialog 三档都有
- linker 连线：button → 发送消息、slider → 进度条
"""
import json, time, zipfile, os

BASE = int(time.time() * 1000)
_n = [0]
def uid(p):
    _n[0] += 1
    return f"{p}_{BASE}_{_n[0]}"

# ---------- 状态栏字段 ----------
F_TRUST   = "sbf_trust"
F_CREDIT  = "sbf_credit"
F_ALERT   = "sbf_alert"
F_MOOD    = "sbf_mood"
F_TIME    = "sbf_time"

status_fields = [
    {"id": F_TRUST,  "name": "信任度", "type": "number", "initial_value": "35",
     "min_value": 0.0, "max_value": 100.0, "pin_side": "left",  "order": 0, "owner": "char"},
    {"id": F_CREDIT, "name": "信用点", "type": "number", "initial_value": "250",
     "min_value": 0.0, "max_value": 9999.0, "pin_side": "right", "order": 1, "owner": "player"},
    {"id": F_ALERT,  "name": "警戒等级", "type": "number", "initial_value": "1",
     "min_value": 0.0, "max_value": 5.0,   "pin_side": "none",  "order": 2, "owner": "neutral"},
    {"id": F_MOOD,   "name": "织的心情", "type": "text",   "initial_value": "慵懒",
     "min_value": None, "max_value": None, "pin_side": "none",  "order": 3, "owner": "char"},
    {"id": F_TIME,   "name": "店内时段", "type": "text",   "initial_value": "深夜",
     "min_value": None, "max_value": None, "pin_side": "none",  "order": 4, "owner": "neutral"},
]

# ---------- 构造工具 ----------
def channel(label, kind, target_id="", *, read="prompt", write="none",
            notify="silent", template="", section="ui_data",
            source_id="", field_type="number", pending=""):
    c = {
        "semanticLabel": label, "semanticPath": label,
        "semanticSource": "manual", "labelElementId": "",
        "sourceComponentId": source_id, "sourcePort": "current",
        "targetKind": kind, "targetId": target_id,
        "pendingName": pending, "displayNameSnapshot": label,
        "visibility": "ui_only",
        "llmReadPolicy": read, "llmWritePolicy": write,
        "notifyStyle": notify,
        "promptSection": section, "fieldType": field_type,
    }
    if template:
        c["notifyTemplate"] = template
    return c

def module(mid, name, mtype, props, *, color=0xFF00E5FF, material=0,
           shape=1, radius=10.0, opacity=1.0):
    return {"id": mid, "name": name, "type": mtype, "material": material,
            "shape": shape, "color": color, "opacity": opacity,
            "borderRadius": radius, "properties": props,
            "boundVariable": "", "statusFieldMirrorKey": "",
            "displayExpression": "", "linkedSources": []}

def element(eid, mod, x, y, w, h, *, layer=0, parent=None, rot=0.0):
    return {"id": eid, "isComposite": False,
            "offset": {"x": float(x), "y": float(y)},
            "size": {"width": float(w), "height": float(h)},
            "layerIndex": layer, "parentSurfaceId": parent,
            "rotation": rot, "layoutLocked": False, "sealed": False,
            "module": mod}

def page(pid, name, ptype, elements, *, parent=None, order=0):
    return {"id": pid, "name": name, "type": ptype, "parentPageId": parent,
            "sortOrder": order, "elements": elements,
            "gestures": [], "propertyOverrides": []}

def assembly(name, mode, w, h, pages, *, color=0xF20A0A14, radius=18.0):
    return json.dumps({
        "id": uid("ui"), "name": name, "mode": mode,
        "elements": "[]", "pages": json.dumps(pages, ensure_ascii=False),
        "pcbWidth": float(w), "pcbHeight": float(h),
        "pcbColorValue": color, "pcbRadius": radius, "pcbRounded": radius > 0,
        "createdAt": BASE,
    }, ensure_ascii=False)


# ---------- 逻辑件（linker / math_node）----------
# 摆在 PCB **左外侧**的「机房区」。运行时它们隐形，
# 但编辑器里占位置——不给规则的话 AI 会把它们堆成一团，
# 作者打开看到一堆重叠方块，比不画连线更糟。
#
# 排布公式（机械可执行，不需要审美判断）：
#   列宽 200（取最宽逻辑件 math_node 180 + 余量）
#   行高 64（取最高 timer 54 + 间距 10）
#   每列 8 个，满了往左再起一列
LOGIC_COL_W, LOGIC_ROW_H, LOGIC_PER_COL = 200, 64, 8
LOGIC_START_X = -224   # -(列宽 + 24 留白)
_logic_seq = [0]

def logic_pos(size):
    i = _logic_seq[0]; _logic_seq[0] += 1
    col, row = divmod(i, LOGIC_PER_COL)
    return LOGIC_START_X - col * (LOGIC_COL_W + 12), row * LOGIC_ROW_H

def reset_logic_layout():
    """每套 UI 开始前重置：否则第二套会接着第一套的编号继续往左飘。"""
    _logic_seq[0] = 0

def linker(name, scheme, src_id, dst_id, params=None, *, priority=5):
    """一条连线。source/target 存的是**元素 id**。"""
    data = {"scheme": scheme, "sourceModuleId": src_id,
            "targetModuleId": dst_id, "enabled": True, "priority": priority}
    if params:
        data["params"] = params
    w, h = 132, 44
    x, y = logic_pos((w, h))
    return element(uid("el"), module(uid("m"), name, "linker",
        {"linker": data}, color=0xFF00ACC1, radius=8.0), x, y, w, h)

def math_node(name, operation, *, a=0.0, b=0.0, c=0.0):
    w, h = 180, 44
    x, y = logic_pos((w, h))
    return element(uid("el"), module(uid("m"), name, "math_node",
        {"operation": operation, "paramA": a, "paramB": b, "paramC": c},
        color=0xFF7E57C2, radius=8.0), x, y, w, h)

CYAN, PINK, AMBER, GREEN, GREY = 0xFF00E5FF, 0xFFFF4081, 0xFFFFB300, 0xFF66BB6A, 0xFF546E7A

reset_logic_layout()

# ==========================================================
# 1. 常驻挂件 extra_sticky —— 状态一览
# ==========================================================
e_panel = element(uid("el"), module(uid("m"), "背板", "surface",
    {"is_overlay_container": True}, color=0xFF101018, material=1, radius=14.0, opacity=0.92),
    0, 0, 212, 150)
PANEL_ID = e_panel["id"]

e_title = element(uid("el"), module(uid("m"), "标题", "text",
    {"text": "STATUS", "fontSize": 11.0, "textAlign": "left"}, color=CYAN),
    12, 10, 90, 16, layer=1, parent=PANEL_ID)

m_trust = module(uid("m"), "信任度条", "progress",
    {"current": 35.0, "min": 0.0, "max": 100.0, "progressShape": "bar",
     "strokeWidth": 8.0, "trackColor": 0x33FFFFFF,
     "dataChannel": channel("信任度", "status_field", F_TRUST,
        read="prompt", write="suggest_delta", notify="toast",
        template="织对你的信任 {old} → {new}")}, color=CYAN)
e_trust = element(uid("el"), m_trust, 12, 34, 188, 14, layer=2, parent=PANEL_ID)
m_trust["properties"]["dataChannel"]["sourceComponentId"] = e_trust["id"]

e_trust_lb = element(uid("el"), module(uid("m"), "信任标签", "text",
    {"text": "信任度", "fontSize": 9.0}, color=0xFF9E9E9E),
    12, 50, 60, 12, layer=3, parent=PANEL_ID)

m_credit = module(uid("m"), "信用点", "text",
    {"text": "250", "fontSize": 20.0, "textAlign": "left",
     "dataChannel": channel("信用点", "status_field", F_CREDIT,
        read="prompt", write="suggest_delta", notify="dialog",
        template="信用点变动：{old} → {new}")}, color=AMBER)
e_credit = element(uid("el"), m_credit, 12, 70, 100, 26, layer=4, parent=PANEL_ID)
m_credit["properties"]["dataChannel"]["sourceComponentId"] = e_credit["id"]

e_credit_lb = element(uid("el"), module(uid("m"), "信用标签", "text",
    {"text": "信用点 ¤", "fontSize": 9.0}, color=0xFF9E9E9E),
    12, 96, 70, 12, layer=5, parent=PANEL_ID)

m_alert = module(uid("m"), "警戒灯", "indicator",
    {"dotSize": 14.0, "defaultGlow": True, "state": "idle",
     "dataChannel": channel("警戒等级", "status_field", F_ALERT,
        read="prompt", write="suggest_replace", notify="dialog",
        template="⚠ 警戒等级升至 {new}")}, color=PINK)
e_alert = element(uid("el"), m_alert, 170, 96, 18, 18, layer=6, parent=PANEL_ID)
m_alert["properties"]["dataChannel"]["sourceComponentId"] = e_alert["id"]

m_mood = module(uid("m"), "心情", "text",
    {"text": "慵懒", "fontSize": 12.0,
     "dataChannel": channel("织的心情", "status_field", F_MOOD,
        read="prompt", write="suggest_replace", notify="toast",
        field_type="text")}, color=GREEN)
e_mood = element(uid("el"), m_mood, 12, 118, 120, 18, layer=7, parent=PANEL_ID)
m_mood["properties"]["dataChannel"]["sourceComponentId"] = e_mood["id"]

e_close = element(uid("el"), module(uid("m"), "收起", "button",
    {"keyAction": True, "hitArea": True}, color=GREY),
    172, 8, 30, 22, layer=8, parent=PANEL_ID)

lk_close_press = linker("收起→按压反馈", "click_to_surface_press",
                        e_close["id"], PANEL_ID)

sticky = assembly("状态挂件", "extra_sticky", 212, 150,
    [page(uid("pg"), "主菜单", "base",
          [e_panel, e_title, e_trust, e_trust_lb, e_credit,
           e_credit_lb, e_alert, e_mood, e_close, lk_close_press])])

# ==========================================================
# 2. 全屏场景 scene —— 吧台点单
# ==========================================================
reset_logic_layout()
s_bg = element(uid("el"), module(uid("m"), "吧台背板", "surface",
    {"is_overlay_container": True}, color=0xFF0D0D16, material=1, radius=0.0, opacity=1.0),
    0, 0, 360, 640)
BG = s_bg["id"]

s_title = element(uid("el"), module(uid("m"), "招牌", "text",
    {"text": "夜航 · NIGHTFLIGHT", "fontSize": 18.0, "textAlign": "center"},
    color=CYAN), 20, 24, 320, 26, layer=1, parent=BG)

s_sub = element(uid("el"), module(uid("m"), "副标题", "text",
    {"text": "深夜 · 只剩你一位客人", "fontSize": 11.0, "textAlign": "center"},
    color=0xFF7E7E8F), 20, 52, 320, 16, layer=2, parent=BG)

s_line = element(uid("el"), module(uid("m"), "分割线", "line",
    {"axis": "horizontal", "lineStyle": "solid", "thickness": 1.0},
    color=0x33FFFFFF), 20, 76, 320, 2, layer=3, parent=BG)

# 消息流
s_flow = element(uid("el"), module(uid("m"), "对话", "message_flow",
    {"historyLimit": 0, "fontSize": 12.5, "showUser": True,
     "showAssistant": True, "richText": True,
     "userBubbleColor": 0xFF1B3A4B, "assistantBubbleColor": 0xFF201828,
     "bubbleRadius": 12.0}, color=0xFF141420, material=1, radius=12.0),
    16, 88, 328, 250, layer=4, parent=BG)

# 调酒浓度滑块
m_slider = module(uid("m"), "浓度", "slider",
    {"current": 50.0, "min": 0.0, "max": 100.0, "step": 5.0,
     "committedValue": 50.0,
     "dataChannel": channel("酒精浓度", "session_var",
        read="prompt", write="none", notify="silent")}, color=AMBER)
s_slider = element(uid("el"), m_slider, 20, 356, 200, 34, layer=5, parent=BG)
m_slider["properties"]["dataChannel"]["sourceComponentId"] = s_slider["id"]

s_slider_lb = element(uid("el"), module(uid("m"), "浓度标签", "text",
    {"text": "浓度", "fontSize": 10.0}, color=0xFF9E9E9E),
    20, 340, 60, 14, layer=6, parent=BG)

s_preview = element(uid("el"), module(uid("m"), "浓度预览", "progress",
    {"current": 50.0, "min": 0.0, "max": 100.0, "progressShape": "bar",
     "strokeWidth": 6.0, "trackColor": 0x33FFFFFF}, color=AMBER),
    232, 366, 108, 12, layer=7, parent=BG)

# 基酒下拉
m_select = module(uid("m"), "基酒", "select",
    {"options": [{"label": "杜松子", "value": "gin"},
                 {"label": "威士忌", "value": "whisky"},
                 {"label": "朗姆", "value": "rum"},
                 {"label": "无酒精", "value": "none"}],
     "current": "gin", "defaultValue": "gin",
     "dataChannel": channel("基酒", "session_var",
        read="prompt", write="none", notify="silent", field_type="text")},
    color=CYAN, radius=8.0)
s_select = element(uid("el"), m_select, 20, 400, 150, 36, layer=8, parent=BG)
m_select["properties"]["dataChannel"]["sourceComponentId"] = s_select["id"]

# 加冰开关
m_switch = module(uid("m"), "加冰", "switch",
    {"value": True,
     "dataChannel": channel("加冰", "session_var",
        read="prompt", write="none", notify="silent", field_type="text")},
    color=GREEN)
s_switch = element(uid("el"), m_switch, 190, 402, 60, 32, layer=9, parent=BG)
m_switch["properties"]["dataChannel"]["sourceComponentId"] = s_switch["id"]

s_switch_lb = element(uid("el"), module(uid("m"), "加冰标签", "text",
    {"text": "加冰", "fontSize": 10.0}, color=0xFF9E9E9E),
    256, 410, 40, 14, layer=10, parent=BG)

# 输入框
m_input = module(uid("m"), "点单输入", "input",
    {"placeholder": "对织说点什么…", "text": "", "committedValue": "",
     "maxLength": 200}, color=0xFF1A1A28, material=1, radius=10.0)
s_input = element(uid("el"), m_input, 16, 452, 250, 44, layer=11, parent=BG)

# 发送按钮
s_send = element(uid("el"), module(uid("m"), "递上", "button",
    {"sendsMessage": True, "hitArea": True, "showTextOnRuntime": True,
     "text": "递上"}, color=PINK, radius=10.0),
    276, 452, 68, 44, layer=12, parent=BG)

# 退出按钮（scene 必须有 keyAction）
s_exit = element(uid("el"), module(uid("m"), "离开吧台", "button",
    {"keyAction": True, "hitArea": True, "showTextOnRuntime": True,
     "text": "离开吧台"}, color=GREY, radius=10.0),
    16, 512, 328, 40, layer=13, parent=BG)

# 时段文本（绑定状态字段）
m_time = module(uid("m"), "时段", "text",
    {"text": "深夜", "fontSize": 11.0, "textAlign": "right",
     "dataChannel": channel("店内时段", "status_field", F_TIME,
        read="prompt", write="suggest_replace", notify="toast",
        field_type="text")}, color=0xFF7E7E8F)
s_time = element(uid("el"), m_time, 240, 24, 100, 16, layer=14, parent=BG)
m_time["properties"]["dataChannel"]["sourceComponentId"] = s_time["id"]

# ---- 醉意计算：浓度 × 0.8 ----
# math_node 让「算出来的值」有出处，作者能看懂这个数是怎么来的。
s_math = math_node("醉意 = 浓度 x 0.8", "*", a=50.0, b=0.8)

s_drunk = element(uid("el"), module(uid("m"), "醉意", "text",
    {"text": "40", "fontSize": 12.0, "textAlign": "right"}, color=PINK),
    232, 340, 108, 16, layer=15, parent=BG)

# ---- 连线（linker）----
# 用 linker 而不是同名数据通道来做联动：连线在画布上**看得见**，
# 作者一眼就知道「这个值是从哪来的」。数据通道是隐式约定，
# 出错时静默不联动，很难查。
lk_slider_prog = linker("浓度→预览条", "slider_to_progress",
                        s_slider["id"], s_preview["id"],
                        {"mappingMode": "absolute"})
lk_slider_math = linker("浓度→醉意参数", "slider_commit_to_math_param",
                        s_slider["id"], s_math["id"], {"targetParam": "paramA"})
lk_math_text   = linker("醉意→文本", "result_to_text",
                        s_math["id"], s_drunk["id"])
lk_send_press  = linker("递上→按压反馈", "click_to_surface_press",
                        s_send["id"], s_bg["id"])
lk_input_send  = linker("有字才能递", "input_nonempty_to_button_enable",
                        s_input["id"], s_send["id"])

scene = assembly("吧台场景", "scene", 360, 640,
    [page(uid("pg"), "主菜单", "base",
          [s_bg, s_title, s_sub, s_line, s_flow, s_slider_lb, s_slider,
           s_preview, s_drunk, s_select, s_switch, s_switch_lb, s_input,
           s_send, s_exit, s_time,
           # 逻辑件排在最后：它们在 PCB 外，不参与容器组。
           s_math, lk_slider_prog, lk_slider_math, lk_math_text,
           lk_send_press, lk_input_send])])

# ==========================================================
# 3. 开场白 opening —— 报上名号
# ==========================================================
reset_logic_layout()
o_bg = element(uid("el"), module(uid("m"), "开场背板", "surface",
    {"is_overlay_container": True}, color=0xFF0D0D16, material=1, radius=18.0, opacity=0.97),
    0, 0, 320, 380)
OBG = o_bg["id"]

o_title = element(uid("el"), module(uid("m"), "标题", "text",
    {"text": "推门而入", "fontSize": 20.0, "textAlign": "center"},
    color=CYAN), 20, 28, 280, 28, layer=1, parent=OBG)

o_body = element(uid("el"), module(uid("m"), "正文", "text",
    {"text": "霓虹灯把雨水染成青色。\n吧台后的女人抬起眼：\n「第一次来？报个名字吧。」",
     "fontSize": 13.0, "textAlign": "center", "overflow": "wrap"},
    color=0xFFCFCFDA), 24, 70, 272, 90, layer=2, parent=OBG)

# 玩家名 → 写进角色卡设定
m_name = module(uid("m"), "玩家名", "input",
    {"placeholder": "你的名字", "text": "", "committedValue": "", "maxLength": 24,
     "dataChannel": channel("玩家称呼", "session_var",
        read="prompt", write="none", notify="silent",
        section="core_setting", field_type="text")},
    color=0xFF1A1A28, material=1, radius=10.0)
o_name = element(uid("el"), m_name, 30, 176, 260, 44, layer=3, parent=OBG)
m_name["properties"]["dataChannel"]["sourceComponentId"] = o_name["id"]

# 身份下拉 → 预绑定一个状态栏里没有的字段，演示预绑定提示
m_job = module(uid("m"), "身份", "select",
    {"options": [{"label": "赏金猎人", "value": "hunter"},
                 {"label": "义体医生", "value": "ripper"},
                 {"label": "走私贩", "value": "runner"}],
     "current": "hunter", "defaultValue": "hunter",
     "dataChannel": channel("玩家身份", "status_field", "",
        read="prompt", write="none", notify="silent",
        section="core_setting", field_type="text", pending="玩家身份")},
    color=CYAN, radius=8.0)
o_job = element(uid("el"), m_job, 30, 232, 260, 40, layer=4, parent=OBG)
m_job["properties"]["dataChannel"]["sourceComponentId"] = o_job["id"]

o_go = element(uid("el"), module(uid("m"), "坐下", "button",
    {"keyAction": True, "hitArea": True, "showTextOnRuntime": True,
     "text": "坐到吧台前"}, color=PINK, radius=12.0),
    30, 292, 260, 46, layer=5, parent=OBG)

lk_name_go = linker("填了名字才能坐下", "input_nonempty_to_button_enable",
                    o_name["id"], o_go["id"])
lk_go_press = linker("坐下→按压反馈", "click_to_surface_press",
                     o_go["id"], OBG)

opening = assembly("开场白", "opening", 320, 380,
    [page(uid("pg"), "主菜单", "base",
          [o_bg, o_title, o_body, o_name, o_job, o_go,
           lk_name_go, lk_go_press])])

# ==========================================================
# 角色卡本体
# ==========================================================
DESC = """织，34 岁，「夜航」酒吧唯一的调酒师，也是这条街消息最灵通的人。

外形：银灰色短发，左眼是旧式义体，虹膜会随情绪泛出淡青色的光。常年穿一件洗得发白的深蓝衬衫，袖子卷到手肘，小臂上有一道没修的旧疤。

性格：话不多，语速慢，习惯在回答前先擦一遍杯子。对熟客毒舌，对生客礼貌而疏远。讨厌被追问过去。信任需要一杯一杯地攒。

背景：十年前是企业安保，某次任务后独自退出，用遣散费盘下这家店。街面上都知道她认识些人，但没人知道具体是谁。

说话方式：短句。极少用感叹号。会用调酒动作代替情绪表达——擦杯子是回避，敲吧台是不耐烦，给你续一杯是认可。"""

SYSTEM = """你扮演织。严格遵守：

1. 说话短。单次回复通常不超过三句，除非玩家明确要求讲述往事。
2. 用动作代替情绪描写。不要写「她感到高兴」，写「她多擦了两下杯子」。
3. 信任度低于 40 时，对涉及她过去的问题一律回避或转移话题。
4. 玩家点单时，根据【基酒】【浓度】【加冰】三项给出对应的调酒描述。
5. 玩家做出讨好/冒犯的行为时，通过状态变化块调整信任度，幅度 ±1~5。
6. 信用点在玩家消费或获得报酬时变动。
7. 警戒等级：店里出现异常（有人跟踪、条子进门）时提升。
8. 心情字段用两个字概括，如「慵懒」「警惕」「松弛」。"""

GREETING = """<p>雨还在下。</p>
<p>你推开那扇挂着褪色霓虹的门，湿气跟着涌进来。店里没别人，只有吧台后一个女人在擦杯子。</p>
<p>她没抬头。</p>
<p>「随便坐。」</p>"""

entries = [
    {"id": "e_intro", "group": "intro", "title": "身份", "content": "「夜航」酒吧的调酒师，消息贩子。", "enabled": True, "order": 0},
    {"id": "e_appear", "group": "detail", "title": "外貌", "content": "银灰短发，左眼义体，深蓝衬衫，小臂旧疤。", "enabled": True, "order": 1},
    {"id": "e_rule", "group": "detail", "title": "行为准则", "content": "不主动提过去；信任靠时间累积；用调酒动作表达情绪。", "enabled": True, "order": 2},
]

meta = {
    "tags": ["赛博朋克", "酒吧", "慢热", "UI测试"],
    "creator": "LLM Project",
    "creator_notes": "UIengine 全功能测试卡：含常驻挂件 / 全屏场景 / 开场白三套 UI，覆盖 5 个状态字段、三类数据通道、三档通知方式。",
    "character_version": "1.0",
    "source_format": "llm_project",
    "post_history_instructions": "保持简短。用动作代替情绪形容词。",
    "mes_example": "",
    "status_bar_fields": status_fields,
    "ui_elements": [],
    "ui_assemblies": [sticky, scene, opening],
    "text_highlight_rules": [],
}

character = {
    "id": f"char_{BASE}",
    "name": "织 · 夜航酒保",
    "avatar": "",
    "card_image_path": "",
    "description": DESC,
    "system_prompt": SYSTEM,
    "world_book_id": "",
    "background_id": "",
    "card_type": "character",
    "entries_json": json.dumps(entries, ensure_ascii=False),
    "opening_greetings": json.dumps([GREETING], ensure_ascii=False),
    "meta_json": json.dumps(meta, ensure_ascii=False),
    "user_name": "",
    "user_avatar": "",
    "user_detail_setting": "",
}

manifest = {
    "magic": "LLM_PROJECT_ASSET_V1",
    "asset_type": "character_card",
    "format_version": 1,
    "exported_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
    "app": "LLM Project",
    "contains": {"user_override": False, "world_book": False},
}

out = "samples/织_夜航酒保_UI测试卡.llmcard"
os.makedirs("samples", exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    z.writestr("data/character.json", json.dumps(character, ensure_ascii=False, indent=2))

print("生成:", out, os.path.getsize(out), "bytes")
