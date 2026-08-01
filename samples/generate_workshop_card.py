# -*- coding: utf-8 -*-
"""测试卡 ②「潮汐工坊」——交互逻辑专项。

分工见 generate_gallery_card.py 顶部说明。本卡专攻**逻辑层**：

  · button 的三种触发方式：单击 / 双击 / 长按（sourceGesture）
  · 各类 click_to_* 方案：开关翻转/置真置假、输入清空、滑块复位、
    定时器启停/归零、math 触发
  · math_node 串联：滑块 → 计算 → 进度条 / 文本
  · 比较运算驱动指示灯（> < ==）
  · 数据通道：session_var / status_field / card_entry / user_profile
  · 叠加页：主页上滑打开，点外部关闭
  · 输入框新属性：多行 + 文本对齐
"""
import json, time, zipfile, os

BASE = int(time.time() * 1000)
_n = [0]
def uid(p):
    _n[0] += 1
    return f"{p}_{BASE}_{_n[0]}"

def module(mid, name, mtype, props, *, color=0xFF2E7D6F, material=0,
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

def composite_element(eid, name, children, x, y, w, h, *, layer=0, parent=None,
                      color=0xFF2E7D6F, radius=14.0, material=1):
    return {"id": eid, "isComposite": True,
            "offset": {"x": float(x), "y": float(y)},
            "size": {"width": float(w), "height": float(h)},
            "layerIndex": layer, "parentSurfaceId": parent,
            "rotation": 0.0, "layoutLocked": False, "sealed": False,
            "composite": {
                "id": uid("comp"), "name": name, "layoutType": "stack",
                "children": children, "material": material,
                "borderRadius": radius, "color": color, "opacity": 1.0,
                "renderingMode": 2}}

def gesture(direction, target_page_id, *, action="switch_base_page",
            transition="base_slide", duration=220):
    return {"direction": direction, "action": action,
            "targetPageId": target_page_id,
            "transition": transition, "durationMs": duration}

def page(pid, name, ptype, elements, *, parent=None, order=0, gestures=None):
    return {"id": pid, "name": name, "type": ptype, "parentPageId": parent,
            "sortOrder": order, "elements": elements,
            "gestures": gestures or [], "propertyOverrides": []}

_logic = [0]
def logic_pos():
    i = _logic[0]; _logic[0] += 1
    col, row = divmod(i, 8)
    return -224 - col * 212, row * 64

def linker(name, scheme, src, dst, params=None, *, priority=5,
           gesture_kind=None):
    d = {"scheme": scheme, "sourceModuleId": src, "targetModuleId": dst,
         "enabled": True, "priority": priority}
    if params: d["params"] = params
    if gesture_kind: d["sourceGesture"] = gesture_kind
    x, y = logic_pos()
    return element(uid("el"), module(uid("m"), name, "linker",
        {"linker": d}, color=0xFF00ACC1, radius=8.0), x, y, 132, 44)

def math_node(name, op, *, a=0.0, b=0.0, c=0.0, fallback=0.0):
    """计算节点。运算符见 MathNodeEngine：+ - * / > < >= <= == set"""
    x, y = logic_pos()
    return element(uid("el"), module(uid("m"), name, "math_node",
        {"operation": op, "paramA": a, "paramB": b, "paramC": c,
         "fallbackValue": fallback},
        color=0xFF7E57C2, radius=8.0), x, y, 180, 44)

def page_router(name, target_page_id, *, action="switch_base_page",
                transition="base_slide", duration=260):
    x, y = logic_pos()
    return element(uid("el"), module(uid("m"), name, "page_router",
        {"route": {"action": action, "targetPageId": target_page_id,
                   "transition": transition, "durationMs": duration}},
        color=0xFF00897B, radius=8.0), x, y, 124, 56)

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

# ---------- 配色：海雾青 ----------
DEEP   = 0xFF0F2027
SLAB   = 0xFF17323B
SLAB2  = 0xFF1F4550
FOAM   = 0xFFE8F4F2
MUTED  = 0xFF7FA8A8
TEAL   = 0xFF2EC4B6
AMBER  = 0xFFFFB703
CORAL  = 0xFFFF6B6B
MOSS   = 0xFF80B918

W, H = 380, 660
PG = {k: uid("pg") for k in ("main", "logic", "recipe")}

F_TIDE, F_STOCK, F_MOOD = "wk_tide", "wk_stock", "wk_mood"
status_fields = [
    {"id": F_TIDE, "name": "潮位", "type": "number", "initial_value": "40",
     "min_value": 0.0, "max_value": 100.0, "pin_side": "left", "order": 0,
     "owner": "neutral"},
    {"id": F_STOCK, "name": "存料", "type": "number", "initial_value": "12",
     "min_value": 0.0, "max_value": 99.0, "pin_side": "right", "order": 1,
     "owner": "player"},
    {"id": F_MOOD, "name": "工坊气氛", "type": "text", "initial_value": "平静",
     "min_value": None, "max_value": None, "pin_side": "none", "order": 2,
     "owner": "neutral"},
]

def bg(name="底板"):
    return element(uid("el"), module(uid("m"), name, "surface",
        {"is_overlay_container": True}, color=DEEP, material=0,
        radius=0.0, opacity=1.0), 0, 0, W, H)

def title(txt, parent, *, y=18, color=FOAM, size=18.0, layer=1):
    return element(uid("el"), module(uid("m"), "标题", "text",
        {"text": txt, "fontSize": size, "textAlign": "center"}, color=color),
        20, y, W - 40, 24, layer=layer, parent=parent)

def label(txt, parent, x, y, w, *, size=11.0, color=MUTED, layer=2,
          align="left", h=None):
    return element(uid("el"), module(uid("m"), "说明", "text",
        {"text": txt, "fontSize": size, "textAlign": align}, color=color),
        x, y, w, h or (size + 6), layer=layer, parent=parent)

def btn(text, x, y, w, h, *, parent, layer, color=SLAB2, tcolor=FOAM,
        radius=9.0, font=12.0, key_action=False, sends=False):
    face = element(uid("el"), module(uid("m"), text + "底", "surface",
        {"__anim": {"type": "press", "durationMs": 150, "curve": "easeOut",
                    "intensity": 0.55}},
        color=color, material=0, radius=radius),
        x, y, w, h, layer=layer, parent=parent)
    cap = element(uid("el"), module(uid("m"), text + "字", "text",
        {"text": text, "fontSize": font, "textAlign": "center"}, color=tcolor),
        x, y + (h - font - 6) / 2, w, font + 6, layer=layer + 1, parent=parent)
    props = {"hitArea": True}
    if key_action: props["keyAction"] = True
    if sends: props["sendsMessage"] = True
    hot = element(uid("el"), module(uid("m"), text, "button", props,
        color=color, radius=radius), x, y, w, h, layer=layer + 2, parent=parent)
    return [face, cap, hot], face["id"], hot["id"]

# ============================================================
# 复合组件：配料计量器（滑块 + 读数 + 进度条）
# ============================================================
def make_meter(x, y, *, parent, layer):
    kids = []
    kids.append(element(uid("el"), module(uid("m"), "计量底", "surface",
        {}, color=SLAB, material=1, radius=12.0), 0, 0, 320, 104))
    kids.append(element(uid("el"), module(uid("m"), "计量名", "text",
        {"text": "配料投放量", "fontSize": 12.0, "textAlign": "left"},
        color=MUTED), 14, 10, 180, 16, layer=1))
    read = element(uid("el"), module(uid("m"), "计量读数", "text",
        {"text": "6", "fontSize": 24.0, "textAlign": "right",
         "__anim": {"type": "number_pop", "durationMs": 460,
                    "curve": "bounceOut", "intensity": 0.8}},
        color=TEAL), 210, 6, 96, 30, layer=1)
    kids.append(read)
    sld = element(uid("el"), module(uid("m"), "计量滑块", "slider",
        {"min": 0, "max": 12, "current": 6, "step": 1,
         "dataChannel": channel("配料投放量", "session_var",
             read="prompt", write="none", section="ui_data")},
        color=TEAL, radius=8.0), 14, 42, 292, 26, layer=1)
    sld["module"]["properties"]["dataChannel"]["sourceComponentId"] = sld["id"]
    kids.append(sld)
    bar = element(uid("el"), module(uid("m"), "计量条", "progress",
        {"min": 0, "max": 12, "current": 6},
        color=AMBER, radius=5.0), 14, 78, 292, 10, layer=1)
    kids.append(bar)
    comp = composite_element(uid("el"), "配料计量器", kids, x, y, 320, 104,
                             layer=layer, parent=parent, color=SLAB)
    return comp, sld["id"], read["id"], bar["id"]

# ============================================================
# 页面 1：工作台
# ============================================================
m_bg = bg()
MB = m_bg["id"]
main = [m_bg, title("潮汐工坊 · 工作台", MB)]
main.append(label("交互逻辑测试：三种点击方式 / 开关 / 定时器 / 计算节点",
                  MB, 20, 44, W - 40, size=10.0, align="center"))

meter, sld_id, read_id, bar_id = make_meter(30, 70, parent=MB, layer=3)
main.append(meter)
# 滑块 → 读数文字、滑块 → 进度条（目标在复合件内部）
main.append(linker("量→读数", "slider_to_text", sld_id, read_id))
main.append(linker("量→条", "slider_to_progress", sld_id, bar_id))

# --- 三种点击方式打在同一个按钮上 ---
main.append(label("① 同一个按钮，三种点击方式各接一个目标", MB, 24, 190, W - 48,
                  size=11.0, color=FOAM))
b_tri, f_tri, h_tri = btn("单击亮灯 / 双击灭灯 / 长按翻转", 24, 210, 332, 44,
                          parent=MB, layer=4)
main += b_tri
lamp = element(uid("el"), module(uid("m"), "指示灯", "indicator",
    {"isOn": False, "onColor": MOSS, "offColor": 0xFF37474F,
     "__anim": {"type": "flash", "durationMs": 280, "color": MOSS}},
    color=MOSS, radius=999.0), 24, 264, 22, 22, layer=4, parent=MB)
main.append(lamp)
sw = element(uid("el"), module(uid("m"), "工坊开关", "switch",
    {"value": False}, color=TEAL, radius=999.0),
    300, 262, 56, 26, layer=4, parent=MB)
main.append(sw)
main.append(label("灯 ← 单/双击　　开关 ← 长按翻转", MB, 54, 266, 240,
                  size=10.0))
main.append(linker("单击→开关置真", "click_to_switch_set_true", h_tri, sw["id"],
                   gesture_kind="tap"))
main.append(linker("双击→开关置假", "click_to_switch_set_false", h_tri, sw["id"],
                   gesture_kind="double_tap"))
main.append(linker("长按→开关翻转", "click_to_switch_toggle", h_tri, sw["id"],
                   gesture_kind="long_press"))
main.append(linker("开关→灯", "switch_to_indicator", sw["id"], lamp["id"]))

# --- 定时器控制 ---
main.append(label("② 定时器：启停 / 归零", MB, 24, 298, W - 48,
                  size=11.0, color=FOAM))
tmr_x, tmr_y = logic_pos()
tmr = element(uid("el"), module(uid("m"), "熔炉计时", "timer",
    {"interval": 1.0, "initialDelay": 0.0, "maxTicks": 0, "isRunning": False,
     "loop": True, "pulseType": "increment", "stepValue": 1.0,
     "currentVal": 0.0},
    color=0xFFFF9100, radius=8.0), tmr_x, tmr_y, 140, 54)
main.append(tmr)
tmr_txt = element(uid("el"), module(uid("m"), "计时读数", "text",
    {"text": "0", "fontSize": 22.0, "textAlign": "center"}, color=AMBER),
    24, 320, 100, 40, layer=4, parent=MB)
main.append(tmr_txt)
b_run, f_run, h_run = btn("启/停", 134, 322, 106, 36, parent=MB, layer=4)
b_rst, f_rst, h_rst = btn("归零", 250, 322, 106, 36, parent=MB, layer=7)
main += b_run + b_rst
main.append(linker("计时→读数", "timer_to_text", tmr["id"], tmr_txt["id"]))
main.append(linker("启停", "click_to_timer_toggle", h_run, tmr["id"]))
main.append(linker("归零", "click_to_timer_reset", h_rst, tmr["id"]))

# --- 输入框（多行 + 对齐，验证新属性） ---
main.append(label("③ 多行输入框（新属性：贴顶 + 可换行）", MB, 24, 370, W - 48,
                  size=11.0, color=FOAM))
note = element(uid("el"), module(uid("m"), "工坊笔记", "input",
    {"placeholder": "记下今天的配方…（可换行）", "text": "",
     "multiline": True, "textVerticalAlign": "top",
     "textHorizontalAlign": "left", "visualMode": "outline",
     "inputTextColor": FOAM, "placeholderColor": MUTED,
     "dataChannel": channel("工坊笔记", "session_var", read="prompt",
                            write="none", section="ui_data",
                            field_type="text")},
    color=TEAL, radius=8.0), 24, 390, 240, 84, layer=4, parent=MB)
note["module"]["properties"]["dataChannel"]["sourceComponentId"] = note["id"]
main.append(note)
b_clr, f_clr, h_clr = btn("清空", 274, 390, 82, 36, parent=MB, layer=4)
main += b_clr
main.append(linker("清空笔记", "click_to_input_clear", h_clr, note["id"]))
b_rs, f_rs, h_rs = btn("滑块复位", 274, 434, 82, 40, parent=MB, layer=7)
main += b_rs
main.append(linker("滑块复位", "click_to_slider_reset", h_rs, sld_id))

# --- 换页按钮 ---
b_lg, f_lg, h_lg = btn("计算工坊 →", 24, 492, 160, 42, parent=MB, layer=10)
b_rc, f_rc, h_rc = btn("配方（上滑）", 196, 492, 160, 42, parent=MB, layer=13)
main += b_lg + b_rc
r_lg = page_router("→计算", PG["logic"])
r_rc = page_router("→配方", PG["recipe"], action="open_overlay",
                   transition="overlay_fade", duration=240)
main += [r_lg, r_rc]
main.append(linker("去计算", "button_to_page_route", h_lg, r_lg["id"]))
main.append(linker("开配方", "button_to_page_route", h_rc, r_rc["id"]))

# --- 发消息按钮 ---
b_snd, f_snd, h_snd = btn("按当前投放量开工", 24, 546, 332, 46,
                          parent=MB, layer=16, color=TEAL, tcolor=DEEP,
                          sends=True, font=13.0)
main += b_snd
main.append(label("数量由界面数据段传给 AI，按钮本身只发固定文字",
                  MB, 24, 598, 332, size=9.0, align="center"))

# ============================================================
# 页面 2：计算工坊（math_node 串联 + 比较运算）
# ============================================================
l_bg = bg()
LB = l_bg["id"]
logic = [l_bg, title("计算工坊", LB)]
logic.append(label("滑块 → 计算节点 → 进度条 / 文本 / 指示灯", LB,
                   20, 44, W - 40, size=10.0, align="center"))

# 两个输入滑块
s_a = element(uid("el"), module(uid("m"), "海水", "slider",
    {"min": 0, "max": 50, "current": 20, "step": 1},
    color=TEAL, radius=8.0), 24, 84, 332, 28, layer=2, parent=LB)
s_b = element(uid("el"), module(uid("m"), "盐晶", "slider",
    {"min": 0, "max": 50, "current": 15, "step": 1},
    color=AMBER, radius=8.0), 24, 146, 332, 28, layer=2, parent=LB)
logic += [label("海水 (0~50)", LB, 24, 66, 160, size=10.0), s_a,
          label("盐晶 (0~50)", LB, 24, 128, 160, size=10.0), s_b]

# 加法节点：海水 + 盐晶
mn_sum = math_node("总量", "+")
logic.append(mn_sum)
logic.append(linker("海水→A", "slider_commit_to_math_param", s_a["id"],
                    mn_sum["id"], {"targetParam": "paramA"}))
logic.append(linker("盐晶→B", "slider_commit_to_math_param", s_b["id"],
                    mn_sum["id"], {"targetParam": "paramB"}))
sum_txt = element(uid("el"), module(uid("m"), "总量读数", "text",
    {"text": "35", "fontSize": 26.0, "textAlign": "center",
     "__anim": {"type": "number_pop", "durationMs": 460,
                "curve": "bounceOut", "intensity": 0.8}},
    color=FOAM), 24, 194, 160, 40, layer=2, parent=LB)
logic.append(sum_txt)
logic.append(linker("总量→文字", "math_to_text", mn_sum["id"], sum_txt["id"]))
sum_bar = element(uid("el"), module(uid("m"), "总量条", "progress",
    {"min": 0, "max": 100, "current": 35}, color=MOSS, radius=5.0),
    196, 206, 160, 14, layer=2, parent=LB)
logic.append(sum_bar)
logic.append(linker("总量→条", "math_to_progress", mn_sum["id"],
                    sum_bar["id"]))

# 比较节点：总量 > 60 ?
logic.append(label("比较运算：总量 > 60 时警示灯亮", LB, 24, 248, W - 48,
                   size=11.0, color=FOAM))
mn_cmp = math_node("超量判定", ">", b=60.0)
logic.append(mn_cmp)
logic.append(linker("总量→比较A", "math_to_math_param", mn_sum["id"],
                    mn_cmp["id"], {"targetParam": "paramA"}))
warn = element(uid("el"), module(uid("m"), "警示灯", "indicator",
    {"isOn": False, "onColor": CORAL, "offColor": 0xFF37474F,
     "__anim": {"type": "glow_pulse", "durationMs": 800, "color": CORAL}},
    color=CORAL, radius=999.0), 24, 272, 26, 26, layer=2, parent=LB)
logic.append(warn)
logic.append(label("超过 60 会亮红", LB, 58, 278, 200, size=10.0))
logic.append(linker("比较→警示", "math_to_indicator", mn_cmp["id"],
                    warn["id"]))

# 数据通道：把总量写进状态栏
logic.append(label("④ 数据通道：下面三项分别写往不同目标", LB, 24, 312,
                   W - 48, size=11.0, color=FOAM))
ch_stock = element(uid("el"), module(uid("m"), "存料同步", "progress",
    {"min": 0, "max": 99, "current": 12,
     "dataChannel": channel("存料", "status_field", F_STOCK,
         read="prompt", write="allow", notify="toast",
         template="存料变为 {value}", section="status")},
    color=AMBER, radius=5.0), 24, 336, 332, 14, layer=2, parent=LB)
ch_stock["module"]["properties"]["dataChannel"]["sourceComponentId"] = ch_stock["id"]
logic += [label("status_field → 状态栏「存料」（AI 可写，变化弹浮窗）",
                LB, 24, 354, 332, size=9.0), ch_stock]

ch_var = element(uid("el"), module(uid("m"), "工坊气氛", "select",
    {"options": ["平静", "忙碌", "焦灼"], "selectedIndex": 0,
     "dataChannel": channel("工坊气氛", "status_field", F_MOOD,
         read="prompt", write="allow", notify="silent",
         section="status", field_type="text")},
    color=TEAL, radius=8.0), 24, 378, 160, 34, layer=2, parent=LB)
ch_var["module"]["properties"]["dataChannel"]["sourceComponentId"] = ch_var["id"]
logic.append(ch_var)
logic.append(label("下拉 → 状态栏文本字段", LB, 196, 386, 160, size=9.0))

ch_name = element(uid("el"), module(uid("m"), "学徒名", "input",
    {"placeholder": "你的名字", "text": "", "visualMode": "outline",
     "inputTextColor": FOAM, "placeholderColor": MUTED,
     "textHorizontalAlign": "center",
     "dataChannel": channel("学徒称呼", "user_profile", read="prompt",
                            write="none", section="core_setting",
                            field_type="text")},
    color=TEAL, radius=8.0), 24, 422, 332, 38, layer=2, parent=LB)
ch_name["module"]["properties"]["dataChannel"]["sourceComponentId"] = ch_name["id"]
logic.append(ch_name)
logic.append(label("user_profile → 直接写角色卡的用户昵称（水平居中输入）",
                   LB, 24, 464, 332, size=9.0))

b_back, f_bk, h_bk = btn("← 返回工作台", 24, H - 62, 332, 44,
                         parent=LB, layer=20)
logic += b_back
r_back = page_router("计算→工作台", PG["main"])
logic.append(r_back)
logic.append(linker("计算返回", "button_to_page_route", h_bk, r_back["id"]))

# ============================================================
# 页面 3：配方（叠加页）
# ============================================================
# ⚠️ 叠加页必须有一个标了 is_overlay_container 的元素作为「面板本体」，
#    点它之外的区域才会自动回到父页。
r_panel = element(uid("el"), module(uid("m"), "配方卡", "surface",
    {"is_overlay_container": True}, color=SLAB, material=1, radius=18.0),
    30, 120, 320, 380)
RP = r_panel["id"]
recipe = [r_panel]
recipe.append(element(uid("el"), module(uid("m"), "配方标题", "text",
    {"text": "今日配方", "fontSize": 17.0, "textAlign": "center"}, color=FOAM),
    46, 140, 288, 24, layer=1, parent=RP))
RECIPE_TEXT = (
    "· 海水 20 · 盐晶 15\n"
    "· 潮位需在 30~70 之间\n"
    "· 熔炉计时满 8 拍后收料\n\n"
    "这一页是**叠加页**：点面板之外的暗区即可关闭，\n"
    "也可以用下面的按钮返回。"
)
recipe.append(element(uid("el"), module(uid("m"), "配方正文", "text",
    {"text": RECIPE_TEXT, "fontSize": 12.0, "textAlign": "left"}, color=MUTED),
    46, 176, 288, 220, layer=1, parent=RP))
b_cls, f_cls, h_cls = btn("关闭", 46, 430, 288, 44, parent=RP, layer=3,
                          color=SLAB2)
recipe += b_cls
r_cls = page_router("配方→工作台", PG["main"], transition="overlay_fade",
                    duration=200)
recipe.append(r_cls)
recipe.append(linker("配方关闭", "button_to_page_route", h_cls, r_cls["id"]))

# ============================================================
# scene
# ============================================================
scene = json.dumps({
    "id": uid("ui"), "name": "潮汐工坊", "mode": "scene",
    "elements": "[]",
    "pages": json.dumps([
        page(PG["main"], "工作台", "base", main, order=0, gestures=[
            gesture("swipe_left", PG["logic"]),
            gesture("swipe_down", PG["recipe"], action="open_overlay",
                    transition="overlay_fade", duration=240),
        ]),
        page(PG["logic"], "计算工坊", "base", logic, order=1, gestures=[
            gesture("swipe_right", PG["main"]),
        ]),
        page(PG["recipe"], "配方", "overlay", recipe,
             parent=PG["main"], order=0),
    ], ensure_ascii=False),
    "pcbWidth": float(W), "pcbHeight": float(H),
    "pcbColorValue": 0x00000000, "pcbRadius": 18.0, "pcbRounded": True,
    "createdAt": BASE,
}, ensure_ascii=False)

# ============================================================
# 角色卡本体
# ============================================================
DESC = """【设定】你是「潮汐工坊」的老匠人，名叫岑。

工坊建在退潮才露出的礁岩上，涨潮时整座作坊泡在水里，
所以一切工序都得掐着潮位做。你在这儿干了四十年，
手上全是盐蚀的裂口，说话不多，但每句都在点子上。

玩家是新来的学徒。你不客气，也不刻薄，只是嫌他慢。"""

SYSTEM = """你是岑，潮汐工坊的老匠人。

【语气】
1. 每次回复 100~180 字。短句为主，少用形容词。
2. 你会直接指出学徒的问题，但不羞辱人。
3. 偶尔提一句潮水、盐、火候，这是你唯一会「多说」的话题。

【界面数据】
4. 每轮 Prompt 会带界面数据段，其中：
   - 【配料投放量】是学徒在工作台滑块上选的数（0~12）。
   - 【工坊笔记】是学徒自己记的内容，可能为空。
   - 学徒点「按当前投放量开工」时，**按投放量的实际数值**判断：
     少于 3 说太少，多于 9 说会溢，4~8 才算合适。
     不要反问他放了多少，数据段里有。
5. 学徒在计算工坊填了称呼后，用那个称呼叫他；没填就叫「学徒」。

【状态】
6. 消耗材料时改「存料」；工序紧张时把「工坊气氛」改成「忙碌」或「焦灼」。
7. 潮位由你根据剧情推进，涨到 70 以上要提醒收工。

【禁止】
8. 不要替学徒决定做什么。
9. 不要一次讲完整套工序，一次一步。"""

GREETING = """<p>「来了？」</p>
<p>岑没抬头，手上还在刮一块鲸骨。工棚里全是盐和铁锈的味道，
潮水在礁石下面响。</p>
<p>「先把量称好。多一分少一分，火候都不一样。」</p>
<p><em>（工作台上可以调投放量、开熔炉；左滑进计算工坊，下滑看配方）</em></p>"""

entries = [
    {"id": "system_name", "title": "系统名称", "content": "潮汐工坊",
     "enabled": True, "is_custom": False, "sort_order": 0},
    {"id": "system_summary", "title": "系统概要",
     "content": "礁岩上的手工作坊，掐着潮位干活。本卡为 UI 测试卡，专攻交互逻辑。",
     "enabled": True, "is_custom": False, "sort_order": 1},
    {"id": "system_details", "title": "系统详情",
     "content": json.dumps({
        "world": "退潮才露出的礁岩作坊，涨潮即停工。",
        "tone": "短句、务实、少形容词。",
        "ui": "scene 含 2 个平级页 + 1 个叠加页，按钮与手势两种换页方式并存。",
     }, ensure_ascii=False),
     "enabled": True, "is_custom": False, "sort_order": 2},
    {"id": "protagonist", "title": "主角",
     "content": json.dumps({
        "name": "", "relationship": "新来的学徒",
        "body": "", "psychology": "急着证明自己。",
        "background": "刚被送来学手艺。",
     }, ensure_ascii=False),
     "enabled": True, "is_custom": False, "sort_order": 3},
    {"id": "plot", "title": "剧情",
     "content": json.dumps({
        "cause": "学徒第一天上工。",
        "events": "称料、开炉、掐潮位收料。",
        "goal": "完成第一炉料（本卡重点是测试交互逻辑）。",
        "possible_endings": "成料 / 溢锅 / 被潮水赶走",
     }, ensure_ascii=False),
     "enabled": True, "is_custom": False, "sort_order": 4},
]

meta = {
    "tags": ["UI测试", "交互逻辑", "math_node", "数据通道", "叠加页"],
    "creator": "LLM Project",
    "creator_notes": (
        "测试卡②：交互逻辑专项。同一个按钮用 sourceGesture 分接"
        "单击/双击/长按三个目标；覆盖 click_to_* 系列"
        "（开关置真置假翻转、输入清空、滑块复位、定时器启停归零）；"
        "math_node 串联（加法→比较）驱动文本/进度条/指示灯；"
        "数据通道覆盖 session_var / status_field / user_profile 三种；"
        "含 1 个叠加页（按钮与下滑两种方式打开）；"
        "多行输入框验证 multiline + textVerticalAlign 新属性。"),
    "character_version": "1.0",
    "source_format": "llm_project",
    "post_history_instructions": "保持岑的短句语气。按界面数据段里的实际数值判断，不要反问。",
    "mes_example": "",
    "status_bar_fields": status_fields,
    "ui_elements": [],
    "ui_assemblies": [scene],
    "text_highlight_rules": [],
}

character = {
    "id": f"char_workshop_{BASE}",
    "name": "潮汐工坊 · 岑",
    "avatar": "", "card_image_path": "",
    "description": DESC,
    "system_prompt": SYSTEM,
    "world_book_id": "", "background_id": "",
    "card_type": "system",
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

out = "samples/潮汐工坊_交互逻辑卡.llmcard"
os.makedirs("samples", exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    z.writestr("data/character.json", json.dumps(character, ensure_ascii=False, indent=2))
print("生成:", out, os.path.getsize(out), "bytes")
