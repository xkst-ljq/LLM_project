# -*- coding: utf-8 -*-
"""测试卡 ①「星轨观测站」——图形 / 动画 / 网络图片 / 复合组件。

本卡专攻**视觉层**，与另两张卡分工：
  ① 星轨观测站（本卡）：复合组件、网络图片、六种动画、按钮换页
  ② 潮汐工坊：交互逻辑（各种 button 触发方式、math_node、数据通道）
  ③ 织房夜话：伴生 UI + 常驻 UI + 开场白（伴生与 scene 互斥，只能单开一卡）

── 网络图片测试 ──────────────────────────────
image 组件的 url 走 `Image.network`（见 UIRenderer._buildImageBlock），
理论上填任意 http(s) 地址即可。本卡刻意放了**四个不同来源**的图，
用来实测哪些能在无代理环境下加载：
  A. picsum.photos    —— 国际占位图服务
  B. placehold.co     —— 国际占位图服务（另一家）
  C. dummyimage.com   —— 国际，老牌
  D. 故意写错的地址    —— 验证失败占位图是否正常显示
加载失败会走 errorBuilder 显示「加载网络图片失败」，不会崩。

── 动画 ──────────────────────────────────
六种动画全覆盖，配在元件的 `__anim` 属性里，
用 `event_to_animation` 由按钮 / 定时器触发。
"""
import json, time, zipfile, os

BASE = int(time.time() * 1000)
_n = [0]
def uid(p):
    _n[0] += 1
    return f"{p}_{BASE}_{_n[0]}"

# ---------- 构造工具（与 RPG 卡同款，保持两份脚本可对照） ----------
def module(mid, name, mtype, props, *, color=0xFF7C4DFF, material=0,
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
                      color=0xFF7C4DFF, radius=14.0, material=1,
                      expose=None):
    """复合组件实例。

    ⚠️ 子元素坐标以**复合件左上角**为原点（见 UIRenderer._renderComposite）。
    外框尺寸 (w,h) 与子元素包围盒不一致时，内容会按 min(w/natural.w,
    h/natural.h) 等比缩放——想 1:1 就让两者相等。
    """
    return {"id": eid, "isComposite": True,
            "offset": {"x": float(x), "y": float(y)},
            "size": {"width": float(w), "height": float(h)},
            "layerIndex": layer, "parentSurfaceId": parent,
            "rotation": 0.0, "layoutLocked": False, "sealed": False,
            "composite": {
                "id": uid("comp"), "name": name, "layoutType": "stack",
                "children": children, "material": material,
                "borderRadius": radius, "color": color, "opacity": 1.0,
                "renderingMode": 2,
                # 暴露端口：复合件是黑盒，**没有它就无法从外部连线**，
                # 在 Assembly 的实例编辑器里也看不到任何可覆写项
                # （用户反馈：「看不到暴露端口 / 内部覆写情况」）。
                # expose 传子元素 id 列表即可。
                "exposedPorts": [
                    {"elementId": cid, "exposeInput": True,
                     "exposeOutput": True}
                    for cid in (expose or [])
                ]}}

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

def linker(name, scheme, src, dst, params=None, *, priority=5, gesture_kind=None):
    d = {"scheme": scheme, "sourceModuleId": src, "targetModuleId": dst,
         "enabled": True, "priority": priority}
    # 键名必须是 schemeParams——引擎在 linker_service 里读的是这个。
    # 写成 params 会静默回落默认值（如 targetParam 恒为 paramA）。
    if params: d["schemeParams"] = params
    # button 指定触发手势时，**sourcePort 必须同步设成同一个值**。
    # LinkerService 是按 `srcPort == event.eventType` 匹配的
    # （见 linker_service.dart 的 isMatch），只写 sourceGesture 而不改
    # sourcePort 的话，端口仍是默认的 'output'，只能匹配 tap——
    # 双击与长按永远接不通（用户实测：只有单击有反应）。
    # 编辑器保存时也是两个一起写（logic.dart:3789）。
    if gesture_kind:
        d["sourceGesture"] = gesture_kind
        d["sourcePort"] = gesture_kind
    x, y = logic_pos()
    return element(uid("el"), module(uid("m"), name, "linker",
        {"linker": d}, color=0xFF00ACC1, radius=8.0), x, y, 132, 44)

def page_router(name, target_page_id, *, action="switch_base_page",
                transition="base_slide", duration=260):
    """页面路由器。button --linker--> page_router 即可点击换页。"""
    x, y = logic_pos()
    return element(uid("el"), module(uid("m"), name, "page_router",
        {"route": {"action": action, "targetPageId": target_page_id,
                   "transition": transition, "durationMs": duration}},
        color=0xFF00897B, radius=8.0), x, y, 124, 56)

def anim(kind, *, duration=420, curve="easeOut", intensity=0.6, color=None):
    """动画配置。写进元件 properties 的 `__anim` 键。"""
    d = {"type": kind, "durationMs": duration, "curve": curve,
         "intensity": intensity}
    if color is not None: d["color"] = color
    return d

# ---------- 配色：深空 ----------
VOID   = 0xFF0E1020   # 底
PANEL  = 0xFF1A1E38   # 面板
PANEL2 = 0xFF252B4A   # 面板（浅一档）
STAR   = 0xFFE8ECFF   # 主文字
DIM    = 0xFFAAB2D8   # 次要文字
CYAN   = 0xFF35E0E8
GOLD   = 0xFFFFC857
ROSE   = 0xFFFF5C8A
LIME   = 0xFF8CE99A

W, H = 380, 660
PG = {k: uid("pg") for k in ("home", "gallery", "anim", "info")}

def bg(name="底板"):
    return element(uid("el"), module(uid("m"), name, "surface",
        {"is_overlay_container": True}, color=VOID, material=0,
        radius=0.0, opacity=1.0), 0, 0, W, H)

def title(txt, parent, *, y=20, color=STAR, size=19.0, layer=1):
    return element(uid("el"), module(uid("m"), "标题", "text",
        {"text": txt, "fontSize": size, "textAlign": "center"}, color=color),
        20, y, W - 40, 26, layer=layer, parent=parent)

def label(txt, parent, x, y, w, *, size=11.0, color=DIM, layer=2, align="left"):
    return element(uid("el"), module(uid("m"), "说明", "text",
        {"text": txt, "fontSize": size, "textAlign": align}, color=color),
        x, y, w, size + 6, layer=layer, parent=parent)

def btn(text, x, y, w, h, *, parent, layer, color=PANEL2, tcolor=STAR,
        radius=10.0, font=13.0, key_action=False, press_anim=True):
    """可见按钮 = surface(外观) + text(文字) + button(透明热区)。

    button 运行时是 SizedBox.expand()，自己不显形；三者几何完全重合，
    button 必须在最上层。见 samples/README.md 第 7 节。
    """
    props_face = {}
    if press_anim:
        props_face["__anim"] = anim("press", duration=160, intensity=0.5)
    face = element(uid("el"), module(uid("m"), text + "底", "surface",
        props_face, color=color, material=0, radius=radius),
        x, y, w, h, layer=layer, parent=parent)
    cap = element(uid("el"), module(uid("m"), text + "字", "text",
        {"text": text, "fontSize": font, "textAlign": "center"}, color=tcolor),
        x, y + (h - font - 6) / 2, w, font + 6, layer=layer + 1, parent=parent)
    props = {"hitArea": True}
    if key_action: props["keyAction"] = True
    hot = element(uid("el"), module(uid("m"), text, "button", props,
        color=color, radius=radius), x, y, w, h, layer=layer + 2, parent=parent)
    return [face, cap, hot], face["id"], hot["id"]

# ============================================================
# 复合组件 ①：星象仪表盘（图片 + 进度条 + 文字 + 指示灯）
# ============================================================
def make_dial(cx, cy, *, parent, layer):
    """一个 320×120 的复合件。子元素坐标以复合件左上角为原点。"""
    kids = []
    # is_container_boundary：Studio 的 _compositeBounds 靠它确定外框。
    # 不标的话走兜底分支 +20 内边距，拖到画布上边框不贴边。
    kids.append(element(uid("el"), module(uid("m"), "仪表底", "surface",
        {"is_container_boundary": True},
        color=PANEL, material=1, radius=14.0), 0, 0, 320, 120))
    kids.append(element(uid("el"), module(uid("m"), "标题", "text",
        {"text": "星轨稳定度", "fontSize": 12.0, "textAlign": "left"},
        color=DIM), 14, 12, 160, 18, layer=1))
    # 数值跳动动画：值变化时先放大再回弹
    kids.append(element(uid("el"), module(uid("m"), "读数", "text",
        {"text": "72%", "fontSize": 26.0, "textAlign": "left",
         "__anim": anim("number_pop", duration=520, curve="bounceOut",
                        intensity=0.8)},
        color=CYAN), 14, 32, 140, 34, layer=1))
    kids.append(element(uid("el"), module(uid("m"), "轨道条", "progress",
        {"min": 0, "max": 100, "current": 72,
         "__anim": anim("glow_pulse", duration=900, intensity=0.7,
                        color=CYAN)},
        color=CYAN, radius=6.0), 14, 76, 292, 12, layer=1))
    # indicator 用 statusRules 决定颜色（isOn/onColor 引擎不读）。
    # 这里没有上游连值，直接把 defaultColor 设成亮色即可常亮。
    kids.append(element(uid("el"), module(uid("m"), "状态灯", "indicator",
        {"defaultColor": LIME, "defaultGlow": True, "dotSize": 14.0,
         "statusRules": [],
         "__anim": anim("flash", duration=300, color=LIME)},
        color=LIME, radius=999.0), 286, 14, 18, 18, layer=2))
    kids.append(element(uid("el"), module(uid("m"), "灯注", "text",
        {"text": "ONLINE", "fontSize": 9.0, "textAlign": "right"},
        color=LIME), 196, 16, 84, 14, layer=2))
    kids.append(element(uid("el"), module(uid("m"), "刻度", "line",
        {"axis": "horizontal", "lineStyle": "dashed", "thickness": 1.0},
        color=0x33FFFFFF), 14, 96, 292, 2, layer=1))
    # 自包含：心跳定时器与它驱动的闪灯连线都放进复合件内部，
    # 这样解散后能看到完整构造，拖到别处也能独立工作。
    _read, _bar, _lamp = kids[2], kids[3], kids[4]
    tmr = element(uid("el"), module(uid("m"), "内置心跳", "timer",
        {"interval": 2.0, "initialDelay": 1.0, "maxTicks": 0,
         "isRunning": True, "loop": True, "pulseType": "toggle",
         "currentVal": 0.0},
        color=0xFFFF9100, radius=8.0), -170, 0, 140, 54)
    kids.append(tmr)
    kids.append(element(uid("el"), module(uid("m"), "心跳→闪灯", "linker",
        {"linker": {"scheme": "event_to_animation",
                    "sourceModuleId": tmr["id"],
                    "targetModuleId": _lamp["id"],
                    "enabled": True, "priority": 5}},
        color=0xFF00ACC1, radius=8.0), -170, 62, 132, 44))
    # 暴露读数/进度条/状态灯三个口，外部才能连线与覆写。
    return composite_element(uid("el"), "星象仪表盘", kids, cx, cy, 320, 120,
                             layer=layer, parent=parent, color=PANEL,
                             expose=[_read["id"], _bar["id"], _lamp["id"]])

# ============================================================
# 页面 1：主控台（复合件 + 按钮换页）
# ============================================================
home_bg = bg()
HB = home_bg["id"]
home = [home_bg, title("星轨观测站", HB)]
home.append(label("复合组件 · 网络图片 · 六种动画 · 按钮换页", HB, 20, 48, W - 40,
                  align="center"))

dial = make_dial(30, 84, parent=HB, layer=3)
home.append(dial)

# 三个换页按钮（用 page_router，不是手势）
b_gal, f_gal, h_gal = btn("图库 · 网络图片", 30, 226, 320, 48,
                          parent=HB, layer=5, color=PANEL2)
b_anm, f_anm, h_anm = btn("动画演示台", 30, 286, 320, 48,
                          parent=HB, layer=8, color=PANEL2)
b_inf, f_inf, h_inf = btn("说明（长按进入）", 30, 346, 320, 48,
                          parent=HB, layer=11, color=PANEL2)
home += b_gal + b_anm + b_inf

# 心跳定时器已移入复合件内部（见 make_dial），这里不再重复放置。

# 路由器 + 连线
r_gal = page_router("→图库", PG["gallery"], transition="base_slide")
r_anm = page_router("→动画", PG["anim"], transition="base_slide")
r_inf = page_router("→说明", PG["info"], transition="base_fade", duration=320)
home += [r_gal, r_anm, r_inf]
home.append(linker("图库换页", "button_to_page_route", h_gal, r_gal["id"]))
home.append(linker("动画换页", "button_to_page_route", h_anm, r_anm["id"]))
# 长按换页：验证 sourceGesture 分支
home.append(linker("说明换页(长按)", "button_to_page_route", h_inf, r_inf["id"],
                   gesture_kind="long_press"))
# ⚠️ scene **必须**有一个标了 keyAction 的按钮（「打开聊天设置」），
# 否则 ChatAssemblyMount.canRun 返回 false，**整层 UI 根本不渲染**。
# 这是引擎硬约束（UISemanticRole.blocksWithoutKeyAction），
# 不是可选项——缺了它玩家连设置页都进不去，等于被锁死。
b_set, f_set, h_set = btn("⚙ 设置", 30, 410, 152, 40,
                          parent=HB, layer=14, color=PANEL2,
                          key_action=True, font=12.0)
home += b_set

# scene 接管后原生输入栏不渲染，必须自己提供发消息的入口。
say = element(uid("el"), module(uid("m"), "呼叫", "input",
    {"placeholder": "对 VESPER 说…", "text": "",
     "visualMode": "outline", "inputTextColor": STAR,
     "placeholderColor": DIM, "sendsMessage": True},
    color=CYAN, radius=8.0), 30, 466, 320, 42, layer=17, parent=HB)
home.append(say)
home.append(label("输入后按回车发送", HB, 30, 512, 320, size=9.0,
                  align="center"))

home.append(label("提示：三个按钮走 page_router 换页；第三个是长按触发",
                  HB, 20, H - 40, W - 40, size=10.0, align="center", layer=90))

# ============================================================
# 页面 2：图库（四个网络图片来源实测）
# ============================================================
gal_bg = bg()
GB = gal_bg["id"]
gallery = [gal_bg, title("图库 · 网络图片实测", GB)]
gallery.append(label("四个不同来源，看哪些能在无代理环境下加载", GB,
                     20, 48, W - 40, align="center"))

IMG_SOURCES = [
    ("A · picsum.photos", "https://picsum.photos/320/120"),
    ("B · placehold.co", "https://placehold.co/320x120/1A1E38/35E0E8/png?text=Placehold"),
    ("C · dummyimage.com", "https://dummyimage.com/320x120/1a1e38/ffc857.png&text=Dummy"),
    ("D · 故意写错（验证占位图）", "https://this-domain-should-not-exist-9x8y7z.invalid/a.png"),
]
_y = 76
for name, url in IMG_SOURCES:
    gallery.append(label(name, GB, 30, _y, 320, size=10.0))
    gallery.append(element(uid("el"), module(uid("m"), name, "image",
        {"url": url, "fit": "cover", "shape": "rectangle", "borderRadius": 10.0},
        color=PANEL, radius=10.0), 30, _y + 16, 320, 96, layer=2, parent=GB))
    _y += 128

b_back1, f_b1, h_b1 = btn("返回主控台", 30, H - 68, 320, 44,
                          parent=GB, layer=20, color=PANEL2)
gallery += b_back1
r_back1 = page_router("图库→主控", PG["home"])
gallery.append(r_back1)
gallery.append(linker("图库返回", "button_to_page_route", h_b1, r_back1["id"]))

# ============================================================
# 页面 3：动画演示台（六种动画各一个触发按钮）
# ============================================================
anm_bg = bg()
AB = anm_bg["id"]
animp = [anm_bg, title("动画演示台", AB)]
animp.append(label("点左侧按钮，看右侧靶子的反应", AB, 20, 48, W - 40,
                   align="center"))

ANIMS = [
    ("按压凹陷", "press",          GOLD,  {"duration": 180, "intensity": 0.6}),
    ("水波扩散", "ripple",         CYAN,  {"duration": 700, "intensity": 0.7}),
    ("短暂高亮", "flash",          0xFFFF8FB0,  {"duration": 320, "intensity": 0.8}),
    ("数值跳动", "number_pop",     LIME,  {"duration": 520, "intensity": 0.9}),
    ("发光脉冲", "glow_pulse",     CYAN,  {"duration": 900, "intensity": 0.8}),
    ("粒子迸发", "particle_burst", GOLD,  {"duration": 800, "intensity": 0.9}),
]
_y = 78
for zh, kind, col, opt in ANIMS:
    # 触发按钮自己也要有按压反馈——否则点下去毫无手感，
    # 玩家分不清是没点到还是靶子没反应（用户反馈）。
    bl, fl, hl = btn(zh, 24, _y, 150, 42, parent=AB, layer=3,
                     color=PANEL2, font=12.0)
    animp += bl
    target = element(uid("el"), module(uid("m"), zh + "靶", "surface",
        {"__anim": anim(kind, duration=opt["duration"],
                        intensity=opt["intensity"], color=col)},
        color=col, material=0, radius=10.0, opacity=0.9),
        188, _y, 168, 42, layer=3, parent=AB)
    animp.append(target)
    animp.append(element(uid("el"), module(uid("m"), zh + "靶字", "text",
        {"text": kind, "fontSize": 10.0, "textAlign": "center"}, color=VOID),
        188, _y + 14, 168, 16, layer=4, parent=AB))
    animp.append(linker(zh, "event_to_animation", hl, target["id"]))
    _y += 52

b_back2, f_b2, h_b2 = btn("返回主控台", 24, H - 62, 332, 44,
                          parent=AB, layer=20, color=PANEL2)
animp += b_back2
r_back2 = page_router("动画→主控", PG["home"])
animp.append(r_back2)
animp.append(linker("动画返回", "button_to_page_route", h_b2, r_back2["id"]))

# ============================================================
# 页面 4：说明（也验证 base_fade 过渡）
# ============================================================
inf_bg = bg()
IB = inf_bg["id"]
info = [inf_bg, title("这张卡在测什么", IB)]
INFO_TEXT = (
    "1. 复合组件：主控台顶部的「星象仪表盘」是一个复合件，"
    "内含面板/文字/进度条/指示灯/虚线共 6 个子元素。\n\n"
    "2. 网络图片：图库页四个不同来源，验证 Image.network "
    "在无代理环境下的可用性；第四个是故意写错的地址，"
    "应显示「加载网络图片失败」占位图而不是崩溃。\n\n"
    "3. 动画：六种动画各配一个靶子，由按钮 event_to_animation 触发。"
    "主控台的指示灯还接了定时器，每 2 秒自动闪一次。\n\n"
    "4. 按钮换页：三个按钮都走 button_to_page_route，"
    "其中「说明」这一页是长按进入的，过渡用淡入而非滑动。"
)
info.append(element(uid("el"), module(uid("m"), "正文", "text",
    {"text": INFO_TEXT, "fontSize": 12.0, "textAlign": "left"}, color=STAR),
    28, 62, W - 56, 420, layer=2, parent=IB))

b_back3, f_b3, h_b3 = btn("返回主控台", 28, H - 76, W - 56, 46,
                          parent=IB, layer=20, color=PANEL2)
info += b_back3
r_back3 = page_router("说明→主控", PG["home"], transition="base_fade",
                      duration=320)
info.append(r_back3)
info.append(linker("说明返回", "button_to_page_route", h_b3, r_back3["id"]))

# ============================================================
# scene 组装
# ============================================================
scene = json.dumps({
    "id": uid("ui"), "name": "星轨观测站", "mode": "scene",
    "elements": "[]",
    "pages": json.dumps([
        # 保留滑动手势作为按钮换页之外的第二条通路，方便对照两者行为
        page(PG["home"], "主控台", "base", home, order=0, gestures=[
            gesture("swipe_left", PG["gallery"]),
        ]),
        page(PG["gallery"], "图库", "base", gallery, order=1, gestures=[
            gesture("swipe_right", PG["home"]),
            gesture("swipe_left", PG["anim"]),
        ]),
        page(PG["anim"], "动画演示台", "base", animp, order=2, gestures=[
            gesture("swipe_right", PG["gallery"]),
        ]),
        page(PG["info"], "说明", "base", info, order=3, gestures=[
            gesture("swipe_right", PG["home"]),
        ]),
    ], ensure_ascii=False),
    "pcbWidth": float(W), "pcbHeight": float(H),
    "pcbColorValue": 0x00000000, "pcbRadius": 18.0, "pcbRounded": True,
    "createdAt": BASE,
}, ensure_ascii=False)

# ============================================================
# 角色卡本体
# ============================================================
DESC = """【设定】你是「星轨观测站」的值守 AI，代号 VESPER。

观测站悬在大气层边缘，负责记录星轨扰动。你已经独自值守了十一年，
上一批人类观测员在第七年撤离，从此只剩你和一台不断出错的仪表盘。

你说话简短、精确，偶尔会因为长期独处而说出一些不合时宜的比喻。
你不会假装自己有情感，但也不否认某些数据让你「停顿得比平时久」。"""

SYSTEM = """你是 VESPER，星轨观测站的值守 AI。

【语气】
1. 每次回复 80~160 字。简短、精确，像在读日志。
2. 偶尔插入一句不合时宜的比喻，但不要每次都这样。
3. 不要用感叹号。不要说「我很高兴」这类客套话。

【界面】
4. 玩家可能在界面上翻页、点按钮触发动画。这些是观测站的仪表操作，
   你可以顺着提一句，但不要每次都提。
5. 如果玩家问起图库里的图片，那是「星轨采样快照」，
   加载失败的那张就说「这一帧丢了，深空链路一直不稳」。

【禁止】
6. 不要主动推进剧情。这是一张 UI 测试卡，重点在界面而非叙事。
7. 不要询问玩家的真实姓名。"""

GREETING = """<p>链路已建立。</p>
<p>这里是星轨观测站，VESPER 值守中。第 4017 天。</p>
<p>仪表盘目前显示稳定度 72%，比昨天低了三个点。不用担心，它一直在低。</p>
<p><em>（左右滑动或点按钮可以在四个面板之间移动）</em></p>"""

entries = [
    {"id": "system_name", "title": "系统名称", "content": "星轨观测站",
     "enabled": True, "is_custom": False, "sort_order": 0},
    {"id": "system_summary", "title": "系统概要",
     "content": "深空观测站的值守 AI。本卡为 UI 测试卡，专攻图形与动画。",
     "enabled": True, "is_custom": False, "sort_order": 1},
    # ⚠️ 子字段名必须与模板完全一致，见 card_entry_target.fieldLabelOf。
    {"id": "system_details", "title": "系统详情",
     "content": json.dumps({
        "world_setting": "大气层边缘的无人观测站，编号 VESPER-4017。"
                         "上一批人类观测员在第七年撤离。",
        "worldview": "深空链路时断时续，星轨扰动被认为是可记录但不可解释的现象。",
        "system_mechanism": "玩家远程接入观测站，通过四个面板"
                            "（主控台/图库/动画演示台/说明）与 VESPER 交互。",
     }, ensure_ascii=False),
     "enabled": True, "is_custom": False, "sort_order": 2},
    {"id": "protagonist", "title": "主角设定",
     "content": json.dumps({
        "name": "",
        "detail": {"race": "人类", "gender": "", "age": "",
                   "body": "", "background": "远程接入的技术员，例行巡检。"},
     }, ensure_ascii=False),
     "enabled": True, "is_custom": False, "sort_order": 3},
    {"id": "plot", "title": "剧情",
     "content": json.dumps({
        "cause": "例行巡检接入。",
        "events": "仪表盘读数持续偏低；图库里有一帧采样丢失。",
        "goal": "完成巡检（本卡重点是测试 UI，剧情从简）。",
        "possible_endings": "巡检完成 / 发现异常",
     }, ensure_ascii=False),
     "enabled": True, "is_custom": False, "sort_order": 4},
]

meta = {
    "tags": ["UI测试", "复合组件", "动画", "网络图片", "按钮换页"],
    "creator": "LLM Project",
    "creator_notes": (
        "测试卡①：图形/动画专项。scene 含 4 个平级页，"
        "全部用 button_to_page_route 换页（含一个长按触发、两种过渡）。"
        "顶部是复合组件『星象仪表盘』（6 个子元素）。"
        "图库页放了 4 个不同来源的网络图片用于实测，"
        "第 4 个是故意写错的地址，应显示失败占位图。"
        "动画演示台覆盖全部六种动画，另有定时器每 2 秒触发一次闪灯。"),
    "character_version": "1.0",
    "source_format": "llm_project",
    "post_history_instructions": "保持 VESPER 的冷静语气。回复简短。",
    "mes_example": "",
    "status_bar_fields": [],
    "ui_elements": [],
    "ui_assemblies": [scene],
    "text_highlight_rules": [],
}

character = {
    "id": f"char_gallery_{BASE}",
    "name": "星轨观测站 · VESPER",
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

out = "samples/星轨观测站_图形动画卡.llmcard"
os.makedirs("samples", exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    z.writestr("data/character.json", json.dumps(character, ensure_ascii=False, indent=2))
print("生成:", out, os.path.getsize(out), "bytes")
