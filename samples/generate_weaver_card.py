# -*- coding: utf-8 -*-
"""测试卡 ③「织房夜话」——伴生 UI + 常驻 UI + 开场白。

分工见 generate_gallery_card.py 顶部说明。

⚠️ **为什么不能和另两张卡合并**：伴生 UI 与 scene 互斥（引擎硬约束）。
   scene 全屏接管后不渲染原生消息气泡，而伴生 UI 正是挂在气泡下方的，
   失去宿主就没有意义。编辑器在新建时会拦截，这里也必须遵守。

三套 UI（每种 mode 只能有一套，见 HANDOFF 3.5g）：
  · opening        —— 进门问名字与心事，写进角色卡（user_profile 通道）
  · extra_sticky   —— 常驻挂件，可长按拖动、可折叠成球
  · extra_companion—— 伴生 UI，跟在最新一条消息气泡下方（宽度上限 212）
"""
import json, time, zipfile, os

BASE = int(time.time() * 1000)
_n = [0]
def uid(p):
    _n[0] += 1
    return f"{p}_{BASE}_{_n[0]}"

def module(mid, name, mtype, props, *, color=0xFF8D6E63, material=0,
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
                      color=0xFF8D6E63, radius=12.0, material=1):
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

def page(pid, name, ptype, elements, *, parent=None, order=0, gestures=None):
    return {"id": pid, "name": name, "type": ptype, "parentPageId": parent,
            "sortOrder": order, "elements": elements,
            "gestures": gestures or [], "propertyOverrides": []}

_logic = [0]
def reset_logic(): _logic[0] = 0
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

def anim(kind, *, duration=400, curve="easeOut", intensity=0.6, color=None):
    d = {"type": kind, "durationMs": duration, "curve": curve,
         "intensity": intensity}
    if color is not None: d["color"] = color
    return d

# ---------- 配色：暖灯下的织房 ----------
NIGHT  = 0xFF2B211C
CLOTH  = 0xFFF5EBDC
CLOTH2 = 0xFFE4D5C0
INK    = 0xFF3A2E26
INK2   = 0xFF7A6555
LAMP   = 0xFFE8A33D
THREAD = 0xFF9C6B4F
JADE   = 0xFF6B8F71

F_TRUST, F_LAMP, F_TOPIC = "wv_trust", "wv_lamp", "wv_topic"
status_fields = [
    {"id": F_TRUST, "name": "亲近", "type": "number", "initial_value": "10",
     "min_value": 0.0, "max_value": 100.0, "pin_side": "left", "order": 0,
     "owner": "character"},
    {"id": F_LAMP, "name": "灯油", "type": "number", "initial_value": "80",
     "min_value": 0.0, "max_value": 100.0, "pin_side": "right", "order": 1,
     "owner": "neutral"},
    {"id": F_TOPIC, "name": "此刻话题", "type": "text",
     "initial_value": "还没开口", "min_value": None, "max_value": None,
     "pin_side": "none", "order": 2, "owner": "neutral"},
]

def btn(text, x, y, w, h, *, parent, layer, color=THREAD, tcolor=CLOTH,
        radius=9.0, font=12.0, key_action=False, sends=False, press=True):
    props_face = {}
    if press:
        props_face["__anim"] = anim("press", duration=150, intensity=0.55)
    face = element(uid("el"), module(uid("m"), text + "底", "surface",
        props_face, color=color, material=0, radius=radius),
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
# ① 开场白（opening）：问名字与心事
# ============================================================
reset_logic()
OW, OH = 320, 430
o_bg = element(uid("el"), module(uid("m"), "灯下", "surface",
    {"is_overlay_container": True}, color=CLOTH, material=0, radius=16.0),
    0, 0, OW, OH)
OB = o_bg["id"]
opening_els = [o_bg]
opening_els.append(element(uid("el"), module(uid("m"), "标题", "text",
    {"text": "织房夜话", "fontSize": 20.0, "textAlign": "center"}, color=INK),
    20, 26, OW - 40, 28, layer=1, parent=OB))
opening_els.append(element(uid("el"), module(uid("m"), "副题", "text",
    {"text": "门没锁。灯还亮着。", "fontSize": 12.0, "textAlign": "center"},
    color=INK2), 20, 58, OW - 40, 18, layer=1, parent=OB))
opening_els.append(element(uid("el"), module(uid("m"), "分隔", "line",
    {"axis": "horizontal", "lineStyle": "solid", "thickness": 1.0},
    color=0x22000000), 40, 86, OW - 80, 2, layer=1, parent=OB))

o_name = element(uid("el"), module(uid("m"), "称呼", "input",
    {"placeholder": "她该怎么称呼你？", "text": "", "visualMode": "outline",
     "inputTextColor": INK, "placeholderColor": INK2,
     "textHorizontalAlign": "center",
     "dataChannel": channel("称呼", "user_profile", read="prompt",
         write="none", section="core_setting", field_type="text")},
    color=THREAD, radius=8.0), 30, 104, OW - 60, 40, layer=2, parent=OB)
o_name["module"]["properties"]["dataChannel"]["sourceComponentId"] = o_name["id"]
opening_els.append(o_name)

# 多行输入：验证新属性在开场白里同样生效
o_mind = element(uid("el"), module(uid("m"), "心事", "input",
    {"placeholder": "今夜为什么来？（可以多写几行）", "text": "",
     "multiline": True, "textVerticalAlign": "top",
     "visualMode": "outline", "inputTextColor": INK,
     "placeholderColor": INK2,
     "dataChannel": channel("来意", "user_profile", read="prompt",
         write="none", section="core_setting", field_type="text")},
    color=THREAD, radius=8.0), 30, 154, OW - 60, 96, layer=2, parent=OB)
o_mind["module"]["properties"]["dataChannel"]["sourceComponentId"] = o_mind["id"]
opening_els.append(o_mind)

o_topic = element(uid("el"), module(uid("m"), "开场话题", "select",
    {"options": ["随便坐坐", "想听个故事", "有事相求"], "selectedIndex": 0,
     "dataChannel": channel("此刻话题", "status_field", F_TOPIC,
         read="prompt", write="allow", notify="silent",
         section="status", field_type="text")},
    color=THREAD, radius=8.0), 30, 262, OW - 60, 38, layer=2, parent=OB)
o_topic["module"]["properties"]["dataChannel"]["sourceComponentId"] = o_topic["id"]
opening_els.append(o_topic)

o_go, o_go_face, o_go_id = btn("推门进去", 30, 316, OW - 60, 48,
                               parent=OB, layer=4, color=THREAD,
                               key_action=True, font=14.0)
opening_els += o_go
# 名字没填就不让进
opening_els.append(linker("填名才能进", "input_nonempty_to_button_enable",
                          o_name["id"], o_go_id))
opening_els.append(element(uid("el"), module(uid("m"), "脚注", "text",
    {"text": "填好名字才能推门", "fontSize": 10.0, "textAlign": "center"},
    color=INK2), 30, 376, OW - 60, 16, layer=4, parent=OB))

opening = json.dumps({
    "id": uid("ui"), "name": "推门", "mode": "opening",
    "elements": "[]",
    "pages": json.dumps([page(uid("pg"), "门口", "base", opening_els)],
                        ensure_ascii=False),
    "pcbWidth": float(OW), "pcbHeight": float(OH),
    "pcbColorValue": 0x00000000, "pcbRadius": 16.0, "pcbRounded": True,
    "createdAt": BASE,
}, ensure_ascii=False)

# ============================================================
# ② 常驻 UI（extra_sticky）：灯与线的小挂件
# ============================================================
reset_logic()
SW, SH = 300, 118
s_bg = element(uid("el"), module(uid("m"), "挂件底", "surface",
    {"is_overlay_container": True}, color=NIGHT, material=1, radius=14.0),
    0, 0, SW, SH)
SB = s_bg["id"]
sticky_els = [s_bg]

# 复合件：灯油计（图标 + 进度条 + 读数）
lamp_kids = []
lamp_kids.append(element(uid("el"), module(uid("m"), "灯座", "surface",
    {}, color=0xFF3A2E26, material=0, radius=10.0), 0, 0, 276, 46))
lamp_kids.append(element(uid("el"), module(uid("m"), "灯珠", "indicator",
    {"isOn": True, "onColor": LAMP, "offColor": 0xFF4A3A2E,
     "__anim": anim("glow_pulse", duration=1400, intensity=0.6, color=LAMP)},
    color=LAMP, radius=999.0), 10, 14, 18, 18, layer=1))
lamp_kids.append(element(uid("el"), module(uid("m"), "灯名", "text",
    {"text": "灯油", "fontSize": 11.0, "textAlign": "left"}, color=CLOTH2),
    36, 8, 60, 15, layer=1))
lamp_bar = element(uid("el"), module(uid("m"), "灯条", "progress",
    {"min": 0, "max": 100, "current": 80,
     "dataChannel": channel("灯油", "status_field", F_LAMP,
         read="prompt", write="allow", notify="toast",
         template="灯油剩 {value}", section="status")},
    color=LAMP, radius=4.0), 36, 26, 230, 10, layer=1)
lamp_bar["module"]["properties"]["dataChannel"]["sourceComponentId"] = lamp_bar["id"]
lamp_kids.append(lamp_bar)
lamp_comp = composite_element(uid("el"), "灯油计", lamp_kids, 12, 10, 276, 46,
                              layer=1, parent=SB, color=NIGHT)
sticky_els.append(lamp_comp)

# 亲近度条（状态字段双向）
trust = element(uid("el"), module(uid("m"), "亲近", "progress",
    {"min": 0, "max": 100, "current": 10,
     "__anim": anim("number_pop", duration=460, curve="bounceOut"),
     "dataChannel": channel("亲近", "status_field", F_TRUST,
         read="prompt", write="allow", notify="dialog",
         template="她对你的态度变了：{value}", section="status")},
    color=JADE, radius=4.0), 48, 66, 178, 12, layer=1, parent=SB)
trust["module"]["properties"]["dataChannel"]["sourceComponentId"] = trust["id"]
sticky_els.append(trust)
sticky_els.append(element(uid("el"), module(uid("m"), "亲近名", "text",
    {"text": "亲近", "fontSize": 11.0, "textAlign": "left"}, color=CLOTH2),
    12, 64, 34, 15, layer=1, parent=SB))

# 折叠按钮（作者自定义，替代内置兜底按钮）
s_fold, s_fold_face, s_fold_id = btn("收起", 234, 62, 54, 22, parent=SB,
                                     layer=2, color=0xFF4A3A2E, font=10.0,
                                     key_action=True, press=False)
sticky_els += s_fold
sticky_els.append(element(uid("el"), module(uid("m"), "提示", "text",
    {"text": "长按挂件任意空白处可拖动位置", "fontSize": 9.0,
     "textAlign": "center"}, color=INK2),
    12, 92, 276, 14, layer=1, parent=SB))

sticky = json.dumps({
    "id": uid("ui"), "name": "灯与线", "mode": "extra_sticky",
    "elements": "[]",
    "pages": json.dumps([page(uid("pg"), "挂件", "base", sticky_els)],
                        ensure_ascii=False),
    "pcbWidth": float(SW), "pcbHeight": float(SH),
    "pcbColorValue": 0x00000000, "pcbRadius": 14.0, "pcbRounded": True,
    "createdAt": BASE,
}, ensure_ascii=False)

# ============================================================
# ③ 伴生 UI（extra_companion）：跟在每条消息下方
# ============================================================
# ⚠️ 宽度上限 212（companionMaxPcbWidth），超了会被引擎拒绝。
reset_logic()
CW, CH = 204, 150
c_bg = element(uid("el"), module(uid("m"), "伴生底", "surface",
    {"is_overlay_container": True}, color=CLOTH2, material=1, radius=12.0),
    0, 0, CW, CH)
CB = c_bg["id"]
comp_els = [c_bg]
comp_els.append(element(uid("el"), module(uid("m"), "伴生题", "text",
    {"text": "此刻", "fontSize": 12.0, "textAlign": "left"}, color=INK),
    12, 8, 120, 16, layer=1, parent=CB))

# 话题选择 → 状态字段
c_topic = element(uid("el"), module(uid("m"), "话题", "select",
    {"options": ["听着", "追问", "岔开", "沉默"], "selectedIndex": 0,
     "dataChannel": channel("此刻话题", "status_field", F_TOPIC,
         read="prompt", write="none", section="status", field_type="text")},
    color=THREAD, radius=8.0), 12, 30, CW - 24, 34, layer=1, parent=CB)
c_topic["module"]["properties"]["dataChannel"]["sourceComponentId"] = c_topic["id"]
comp_els.append(c_topic)

# 三个消息操作按钮：验证 button_to_message_action
c_re, c_re_f, c_re_id = btn("重讲", 12, 74, 58, 30, parent=CB, layer=2,
                            color=THREAD, font=11.0)
c_ed, c_ed_f, c_ed_id = btn("改写", 74, 74, 58, 30, parent=CB, layer=5,
                            color=THREAD, font=11.0)
c_dl, c_dl_f, c_dl_id = btn("删掉", 136, 74, 56, 30, parent=CB, layer=8,
                            color=0xFF8C5A5A, font=11.0)
comp_els += c_re + c_ed + c_dl

flow = element(uid("el"), module(uid("m"), "消息锚", "message_flow",
    {"maxCount": 1, "showAvatar": False}, color=CLOTH2, radius=8.0),
    12, 112, CW - 24, 28, layer=1, parent=CB)
comp_els.append(flow)
comp_els.append(linker("重讲", "button_to_message_action", c_re_id, flow["id"],
                       {"messageAction": "regenerate"}))
comp_els.append(linker("改写", "button_to_message_action", c_ed_id, flow["id"],
                       {"messageAction": "edit"}))
comp_els.append(linker("删掉", "button_to_message_action", c_dl_id, flow["id"],
                       {"messageAction": "delete"}))

companion = json.dumps({
    "id": uid("ui"), "name": "此刻", "mode": "extra_companion",
    "elements": "[]",
    "pages": json.dumps([page(uid("pg"), "伴生", "base", comp_els)],
                        ensure_ascii=False),
    "pcbWidth": float(CW), "pcbHeight": float(CH),
    "pcbColorValue": 0x00000000, "pcbRadius": 12.0, "pcbRounded": True,
    "createdAt": BASE,
}, ensure_ascii=False)

# ============================================================
# 角色卡本体（character 卡，不是 system）
# ============================================================
DESC = """【角色】阿缯，三十出头的织工，独自守着城南一间小织房。

白天织布，夜里点一盏灯补活。灯油有限，所以夜谈总是有尽头的。
她话不多，但记性极好——你上次说过的每一句，她都记得。

她不主动追问，只是听着。你愿意说，她就一直听；
你不说，她就继续手上的活，织机声不停。"""

SYSTEM = """你扮演阿缯，城南织房的织工。

【语气】
1. 每次回复 100~200 字。语速慢，句子短，常有停顿。
2. 手上一直有活（织、绕线、剪线头），说话时会带上这些动作。
3. 不追问。玩家不说，你就不问，只是接着干活。

【记忆】
4. 你记得玩家说过的每件事。适时提起，但不要卖弄。
5. 玩家在门口填的「来意」是他今夜的心事，你心里清楚，但不点破。

【状态】
6. 玩家说了真心话、或你说了自己的事，「亲近」+5~15。
   敷衍或撒谎则不变甚至下降。
7. 每过一段夜谈，「灯油」-3~8。低于 20 时提一句「灯要没了」。
   到 0 就该散了。
8. 「此刻话题」跟着对话内容更新。

【界面】
9. 玩家可能用伴生面板选「听着/追问/岔开/沉默」，
   这是他此刻的姿态，据此调整你的反应。
10. 常驻挂件显示灯油与亲近，你不必主动提数值。

【禁止】
11. 不要替玩家说话或决定。
12. 不要一夜之间变得亲密——亲近是慢慢涨的。"""

GREETING = """<p>门轴响了一声。</p>
<p>阿缯没停手，梭子还在走。过了一会儿她才抬头，看清是你，
把灯芯往上挑了挑。</p>
<p>「坐吧。」</p>
<p>她指了指织机旁那张矮凳，又低头去接刚才那根线。
织房里只有织机声和灯芯偶尔的噼啪。</p>"""

entries = [
    # ⚠️ character 卡的固定条目 id 与 system 卡不同，
    #    见 character_edit_page._defaultEntries。
    {"id": "name_entry", "title": "姓名", "content": "阿缯",
     "enabled": True, "is_custom": False, "sort_order": 0},
    {"id": "relationship", "title": "关系",
     "content": "城南织房的织工。你偶尔夜里来坐坐，她从不问为什么。",
     "enabled": True, "is_custom": False, "sort_order": 1},
    {"id": "body", "title": "外貌与身体",
     "content": "三十出头，手指有常年绕线的薄茧。左眼视力不好，穿针要凑很近。",
     "enabled": True, "is_custom": False, "sort_order": 2},
    {"id": "psychology", "title": "心理",
     "content": "听比说多。不追问是她的分寸，不是冷淡。记性好得让人有点怕。",
     "enabled": True, "is_custom": False, "sort_order": 3},
    {"id": "background", "title": "背景",
     "content": "家里原本做布庄，后来散了，只剩这间织房和一台旧织机。",
     "enabled": True, "is_custom": False, "sort_order": 4},
]

meta = {
    "tags": ["UI测试", "伴生UI", "常驻UI", "开场白", "复合组件"],
    "creator": "LLM Project",
    "creator_notes": (
        "测试卡③：伴生/常驻/开场白专项。**不含 scene**——"
        "伴生 UI 与 scene 互斥（scene 不渲染消息气泡，伴生没有宿主）。"
        "开场白用 user_profile 通道写昵称与来意，含多行输入框；"
        "常驻挂件含复合组件『灯油计』，可长按拖动、有自定义折叠按钮，"
        "亲近度变化走 dialog 级通知、灯油走 toast；"
        "伴生 UI 宽 204（上限 212），含三个 button_to_message_action。"),
    "character_version": "1.0",
    "source_format": "llm_project",
    "post_history_instructions": "保持阿缯的慢语速与不追问的分寸。手上始终有活。",
    "mes_example": "",
    "status_bar_fields": status_fields,
    "ui_elements": [],
    "ui_assemblies": [opening, sticky, companion],
    "text_highlight_rules": [],
}

character = {
    "id": f"char_weaver_{BASE}",
    "name": "阿缯",
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

out = "samples/织房夜话_伴生常驻卡.llmcard"
os.makedirs("samples", exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    z.writestr("data/character.json", json.dumps(character, ensure_ascii=False, indent=2))
print("生成:", out, os.path.getsize(out), "bytes")
