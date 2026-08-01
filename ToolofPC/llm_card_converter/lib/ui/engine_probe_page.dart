import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';

/// UI 引擎移植验证页（阶段 0）。
///
/// ## 这个页面用来做什么
///
/// 只回答一个问题：**主项目的 UI 引擎能不能在本工具里跑起来。**
///
/// 它不接入转译流程、不读任何文件，只用一份写死的 assembly JSON
/// 走一遍「解析 → 渲染」。通了，后面的预览面板与 AI 工作台才有地基；
/// 不通，就得改共享方式，而不是继续往上盖。
///
/// ## 为什么值得单独做一页
///
/// 引擎是 25 个文件 / 约 1.3 万行，跨项目引用有几个只能实测的风险：
///
/// 1. **着色器资源路径**：`ripple_shader.dart` 从
///    `packages/llm_ui_engine/shaders/...` 加载。作为 package 提供时
///    路径规则和应用内不同，写错只会「水波动画没了」而不报错；
/// 2. **平台实现**：引擎原本跑在 Android，Windows 桌面端是第一次；
/// 3. **依赖闭包**：引擎只需要 flutter_markdown / markdown / flutter_html
///    三个包，验证它们在桌面端能正常工作。
///
/// 这些问题混在真实业务里排查会很痛苦，单独一页能快速定位。
///
/// ## 怎么用
///
/// 从主页进入本页 → 看是否渲染出一块深色面板与几个组件。
/// 顶部三个指示灯给出引擎自检结果；底部可切换查看原始 JSON。
class EngineProbePage extends StatefulWidget {
  const EngineProbePage({super.key});

  @override
  State<EngineProbePage> createState() => _EngineProbePageState();
}

class _EngineProbePageState extends State<EngineProbePage> {
  UIAssemblyInfo? _info;
  String? _parseError;
  bool _showJson = false;

  /// 着色器加载结果。null 表示尚未探测。
  bool? _shaderOk;

  @override
  void initState() {
    super.initState();
    _parse();
    _probeShader();
  }

  /// 探测着色器能否加载。
  ///
  /// 失败**不影响**其余渲染：引擎内部会退回「不播水波动画」，
  /// 这是设计好的降级路径。这里单独把结果显示出来，
  /// 是因为它静默失败时最难发现（见 ripple_shader.dart 的注释）。
  Future<void> _probeShader() async {
    await RippleShaderLoader.ensureLoaded();
    if (!mounted) return;
    setState(() => _shaderOk = RippleShaderLoader.isReady);
  }

  void _parse() {
    try {
      final map = jsonDecode(_probeAssemblyJson) as Map<String, dynamic>;
      setState(() {
        _info = UIAssemblyInfo.fromJson(map);
        _parseError = null;
      });
    } catch (e, s) {
      setState(() {
        _info = null;
        _parseError = '$e\n\n$s';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UI 引擎验证'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _showJson = !_showJson),
            icon: const Icon(Icons.data_object, size: 18),
            label: Text(_showJson ? '看渲染' : '看 JSON'),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          const Divider(height: 1),
          Expanded(
            child: _showJson ? _buildJsonView() : _buildRenderView(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    Widget lamp(String label, bool? ok, {String? detail}) {
      final color = ok == null
          ? Colors.grey
          : (ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828));
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: 4),
              Text(detail,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        children: [
          lamp('模型解析', _parseError == null && _info != null),
          lamp(
            '着色器',
            _shaderOk,
            detail: _shaderOk == false ? '降级为无水波（不影响其余渲染）' : null,
          ),
          lamp('渲染', _info != null),
        ],
      ),
    );
  }

  Widget _buildRenderView() {
    if (_parseError != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          '解析失败：\n$_parseError',
          style: const TextStyle(color: Color(0xFFC62828), fontSize: 12),
        ),
      );
    }
    final info = _info;
    if (info == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      color: const Color(0xFFEDEDF2),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              '${info.name} · mode=${info.mode} · '
              '${info.pcbWidth.toStringAsFixed(0)}×'
              '${info.pcbHeight.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF666672)),
            ),
            const SizedBox(height: 12),
            // 真正的验证点：把引擎的运行时视图搬到桌面端跑。
            DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: SizedBox(
                width: info.pcbWidth,
                height: info.pcbHeight,
                child: UIAssemblyRuntimeView(assemblyInfo: info),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJsonView() {
    return Container(
      color: const Color(0xFF1E1E22),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          const JsonEncoder.withIndent('  ')
              .convert(jsonDecode(_probeAssemblyJson)),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: Color(0xFFD4D4D8),
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

/// 验证用的最小 assembly。
///
/// 刻意覆盖几类**不同渲染路径**的组件，只通一种不能说明引擎跑通了：
///
/// | 组件 | 验证什么 |
/// |---|---|
/// | `surface` | 底板：材质 / 圆角 / 颜色（ARGB 整数） |
/// | `text` | 文本与字号，最基础的绘制路径 |
/// | `progress` | 数值型组件的量程与当前值 |
/// | `button` | 交互热区（运行时不显形） |
///
/// ## 注意结构（写错只会静默失效）
///
/// - `elements` 与 `pages` **是 JSON 字符串**，不是数组；
/// - `material` / `shape` 是**枚举下标整数**，不是字符串；
/// - `color` 是 **ARGB 整数**（0xFF1B1B22 = 4279371298）；
/// - scene 模式必须有组件标记 `keyAction`，否则**整层不渲染**
///   （见 ASSEMBLY_HANDOFF.md 3.5j）——这里由 button 承担。
const String _probeAssemblyJson = '''
{
  "id": "probe_assembly",
  "name": "引擎验证",
  "mode": "extra_sticky",
  "elements": "[]",
  "pcbWidth": 320.0,
  "pcbHeight": 220.0,
  "pcbColorValue": 4279371298,
  "pcbRadius": 14.0,
  "pcbRounded": true,
  "createdAt": "2026-01-01T00:00:00.000",
  "pages": "[{\\"id\\":\\"page_root\\",\\"name\\":\\"主页\\",\\"type\\":\\"base\\",\\"parentPageId\\":null,\\"sortOrder\\":0,\\"gestures\\":[],\\"propertyOverrides\\":[],\\"elements\\":[{\\"id\\":\\"el_bg\\",\\"isComposite\\":false,\\"offset\\":{\\"x\\":0.0,\\"y\\":0.0},\\"size\\":{\\"width\\":320.0,\\"height\\":220.0},\\"layerIndex\\":0,\\"parentSurfaceId\\":null,\\"rotation\\":0.0,\\"layoutLocked\\":false,\\"sealed\\":false,\\"module\\":{\\"id\\":\\"m_bg\\",\\"name\\":\\"底板\\",\\"type\\":\\"surface\\",\\"material\\":1,\\"shape\\":1,\\"color\\":4280558628,\\"opacity\\":1.0,\\"borderRadius\\":14.0,\\"properties\\":{},\\"boundVariable\\":\\"\\",\\"statusFieldMirrorKey\\":\\"\\",\\"displayExpression\\":\\"\\",\\"linkedSources\\":[]}},{\\"id\\":\\"el_title\\",\\"isComposite\\":false,\\"offset\\":{\\"x\\":20.0,\\"y\\":24.0},\\"size\\":{\\"width\\":280.0,\\"height\\":30.0},\\"layerIndex\\":1,\\"parentSurfaceId\\":null,\\"rotation\\":0.0,\\"layoutLocked\\":false,\\"sealed\\":false,\\"module\\":{\\"id\\":\\"m_title\\",\\"name\\":\\"标题\\",\\"type\\":\\"text\\",\\"material\\":1,\\"shape\\":0,\\"color\\":4294967295,\\"opacity\\":1.0,\\"borderRadius\\":0.0,\\"properties\\":{\\"text\\":\\"引擎移植验证\\",\\"fontSize\\":18.0,\\"textAlign\\":\\"center\\",\\"overflow\\":\\"ellipsis\\",\\"richText\\":false},\\"boundVariable\\":\\"\\",\\"statusFieldMirrorKey\\":\\"\\",\\"displayExpression\\":\\"\\",\\"linkedSources\\":[]}},{\\"id\\":\\"el_label\\",\\"isComposite\\":false,\\"offset\\":{\\"x\\":20.0,\\"y\\":74.0},\\"size\\":{\\"width\\":280.0,\\"height\\":22.0},\\"layerIndex\\":2,\\"parentSurfaceId\\":null,\\"rotation\\":0.0,\\"layoutLocked\\":false,\\"sealed\\":false,\\"module\\":{\\"id\\":\\"m_label\\",\\"name\\":\\"说明\\",\\"type\\":\\"text\\",\\"material\\":1,\\"shape\\":0,\\"color\\":4290822336,\\"opacity\\":1.0,\\"borderRadius\\":0.0,\\"properties\\":{\\"text\\":\\"能看到这块面板即表示引擎可用\\",\\"fontSize\\":12.0,\\"textAlign\\":\\"center\\",\\"overflow\\":\\"ellipsis\\",\\"richText\\":false},\\"boundVariable\\":\\"\\",\\"statusFieldMirrorKey\\":\\"\\",\\"displayExpression\\":\\"\\",\\"linkedSources\\":[]}},{\\"id\\":\\"el_bar\\",\\"isComposite\\":false,\\"offset\\":{\\"x\\":30.0,\\"y\\":120.0},\\"size\\":{\\"width\\":260.0,\\"height\\":16.0},\\"layerIndex\\":3,\\"parentSurfaceId\\":null,\\"rotation\\":0.0,\\"layoutLocked\\":false,\\"sealed\\":false,\\"module\\":{\\"id\\":\\"m_bar\\",\\"name\\":\\"进度\\",\\"type\\":\\"progress\\",\\"material\\":1,\\"shape\\":2,\\"color\\":4282622023,\\"opacity\\":1.0,\\"borderRadius\\":8.0,\\"properties\\":{\\"min\\":0.0,\\"max\\":100.0,\\"current\\":68.0,\\"progressShape\\":\\"capsule\\"},\\"boundVariable\\":\\"\\",\\"statusFieldMirrorKey\\":\\"\\",\\"displayExpression\\":\\"\\",\\"linkedSources\\":[]}},{\\"id\\":\\"el_btn\\",\\"isComposite\\":false,\\"offset\\":{\\"x\\":110.0,\\"y\\":160.0},\\"size\\":{\\"width\\":100.0,\\"height\\":36.0},\\"layerIndex\\":4,\\"parentSurfaceId\\":null,\\"rotation\\":0.0,\\"layoutLocked\\":false,\\"sealed\\":false,\\"module\\":{\\"id\\":\\"m_btn\\",\\"name\\":\\"确认\\",\\"type\\":\\"button\\",\\"material\\":1,\\"shape\\":1,\\"color\\":4282622023,\\"opacity\\":1.0,\\"borderRadius\\":10.0,\\"properties\\":{\\"keyAction\\":true},\\"boundVariable\\":\\"\\",\\"statusFieldMirrorKey\\":\\"\\",\\"displayExpression\\":\\"\\",\\"linkedSources\\":[]}}]}]"
}
''';
