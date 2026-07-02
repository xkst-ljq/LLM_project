import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'linker_service.dart';
import 'ui_models.dart';

class UIRenderer {
  /// 将 UIElement 渲染为 Flutter Widget
  static Widget render(BuildContext context, UIElement element) {
    final bool isStudio = UISceneModeScope.of(context);
    if (!isStudio && LinkerService.isTargetHiddenBySwitch(element.id)) {
      return const SizedBox.shrink();
    }
    Widget widget;
    if (element.isComposite && element.composite != null) {
      widget = _renderComposite(context, element.composite!, element.size);
    } else if (!element.isComposite && element.module != null) {
      widget = _renderModule(context, element, element.module!, element.size);
    } else {
      widget = const SizedBox();
    }
    // 围绕元素自身中心旋转。工作室拖拽与运行时聊天渲染共用此入口，
    // 因此两处表现一致；rotation == 0 时不套 Transform，零开销。
    if (element.rotation != 0.0) {
      return Transform.rotate(
        angle: element.rotation * math.pi / 180.0,
        child: widget,
      );
    }
    return widget;
  }

  static Widget _renderModule(BuildContext context, UIElement element, UIModule module, Size size) {
    // 原子部件只渲染自己的单一职责：
    // progress = 一根条；text = 一段文字；surface/base_box = 一个视觉表面；
    // button/input = 透明逻辑热区，不自带任何边框或底色。
    switch (module.type) {
      case 'progress':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildProgressBar(module, size),
        );
      case 'text':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildTextBlock(module),
        );
      case 'input':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildInputBlock(context, module),
        );
      case 'switch':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildSwitchBlock(context, module),
        );
      case 'line':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildLineBlock(module, size),
        );
      case 'image':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildImageBlock(context, module),
        );
      case 'slider':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildSlider(module, size),
        );
      case 'primitive_art':
      case 'surface_art':
      case 'light_effect':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: CustomPaint(
            painter: UIPrimitiveArtPainter(module.properties),
          ),
        );
      case 'button':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildButton(context, module),
        );
      case 'surface':
      case 'base_box':
        return _applyMaterialAndShape(
          module.material,
          module.shape,
          module.color,
          module.opacity,
          module.borderRadius,
          _buildBaseBox(),
          size,
        );
      case 'linker':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildLinkerNode(module, size),
        );
      case 'math_node':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildMathNodeBlock(module, size),
        );
      case 'select':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildSelectBlock(context, element, module, size),
        );
      case 'indicator':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildIndicatorBlock(context, element, module, size),
        );
      case 'scroll_frame':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildScrollFrameBlock(context, element, module, size),
        );
      case 'timer':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildTimerBlock(context, element, module, size),
        );
      default:
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Center(
            child: Text(
              '未知控件: ${module.type}',
              style: const TextStyle(color: Color(0xFF111116), fontSize: 12),
            ),
          ),
        );
    }
  }

  static Widget _renderComposite(BuildContext context, UIComposite composite, Size size) {
    // 复合组件渲染其子元素（当前简化实现：stack 布局）
    final children = <Widget>[];
    for (final child in composite.children) {
      final childWidget = render(context, child);
      children.add(
        Positioned(
          left: child.offset.dx,
          top: child.offset.dy,
          width: child.size.width,
          height: child.size.height,
          child: childWidget,
        ),
      );
    }

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: children,
      ),
    );
  }

  static Widget _applyMaterialAndShape(
      UIModuleMaterial material,
      UIModuleShape shape,
      Color color,
      double opacity,
      double borderRadius,
      Widget child,
      Size size,
      ) {
    Widget content = child;

    switch (material) {
      case UIModuleMaterial.glass:
        content = Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity * 0.25),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: child,
        );
        break;
      case UIModuleMaterial.solid:
        content = Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: child,
        );
        break;
      case UIModuleMaterial.gradient:
        content = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: opacity), color.withValues(alpha: opacity * 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: child,
        );
        break;
      case UIModuleMaterial.outline:
        content = Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: color.withValues(alpha: opacity), width: 2),
          ),
          child: child,
        );
        break;
    }

    // 形状裁剪
    switch (shape) {
      case UIModuleShape.circle:
        return ClipOval(child: content);
      case UIModuleShape.capsule:
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: content,
        );
      case UIModuleShape.rounded:
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: content,
        );
      case UIModuleShape.heart:
        return ClipPath(clipper: _PathClipper(getHeartPath), child: content);
      case UIModuleShape.star5:
        return ClipPath(clipper: _PathClipper((r) => getStarPath(r, 5, 0.45)), child: content);
      case UIModuleShape.star4:
        return ClipPath(clipper: _PathClipper((r) => getStarPath(r, 4, 0.4)), child: content);
      case UIModuleShape.rectangle:
        return content;
    }
  }

  static Widget _buildBaseBox() {
    return Container(); // 纯视觉表面，内容由外部决定
  }

  static Widget _buildProgressBar(UIModule module, Size size) {
    final double min = (module.properties['min'] ?? 0).toDouble();
    final double max = (module.properties['max'] ?? 100).toDouble();
    double current = (module.properties['current'] ?? min).toDouble();

    final linkedVal = LinkerService.resolveTargetValue(module);
    if (linkedVal != null && linkedVal is num) {
      current = linkedVal.toDouble();
    }
    final double actualMin = min <= max ? min : max;
    final double actualMax = min <= max ? max : min;
    current = current.clamp(actualMin, actualMax).toDouble();

    final double progress = actualMax > actualMin ? (current - actualMin) / (actualMax - actualMin) : 0.0;

    final fillColor = module.color;
    final int? trackColorVal = module.properties['trackColor'] as int?;
    final Color trackColor = trackColorVal != null ? Color(trackColorVal) : Colors.grey.shade200;
    final String shapeStr = module.properties['progressShape']?.toString() ?? 'rounded';

    if (shapeStr == 'ring') {
      final double shortestSide = math.min(size.width, size.height);
      final double defaultSw = shortestSide * 0.12;
      final dynamic customSwProp = module.properties['strokeWidth'];
      double sw = (customSwProp != null && customSwProp is num) ? customSwProp.toDouble() : defaultSw;
      sw = sw.clamp(2.0, shortestSide * 0.42).toDouble();
      return CustomPaint(
        painter: _RingProgressBarPainter(progress: progress, fillColor: fillColor, trackColor: trackColor, strokeWidth: sw),
        size: size,
      );
    }

    if (shapeStr == 'heart') {
      return ClipPath(
        clipper: _PathClipper(getHeartPath),
        child: Container(
          color: trackColor,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: progress.clamp(0.0, 1.0),
              widthFactor: 1.0,
              child: Container(color: fillColor),
            ),
          ),
        ),
      );
    }

    final radius = shapeStr == 'rectangle' ? BorderRadius.zero : BorderRadius.circular(999);
    return Container(
      decoration: BoxDecoration(color: trackColor, borderRadius: radius),
      child: ClipRRect(
        borderRadius: radius,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            heightFactor: 1.0,
            child: Container(color: fillColor),
          ),
        ),
      ),
    );
  }

  static Widget _buildSlider(UIModule module, Size size) {
    final double min = (module.properties['min'] ?? 0).toDouble();
    final double max = (module.properties['max'] ?? 100).toDouble();
    double current = (module.properties['current'] ?? min).toDouble();

    final linkedVal = LinkerService.resolveTargetValue(module);
    if (linkedVal != null && linkedVal is num) {
      current = linkedVal.toDouble();
    }
    final double actualMin = min <= max ? min : max;
    final double actualMax = min <= max ? max : min;
    current = current.clamp(actualMin, actualMax).toDouble();

    final double ratio = actualMax > actualMin ? (current - actualMin) / (actualMax - actualMin) : 0.0;

    final fillColor = module.color;
    final int? trackColorVal = module.properties['trackColor'] as int?;
    final Color trackColor = trackColorVal != null ? Color(trackColorVal) : Colors.grey.shade300;
    final double knobSize = (module.properties['knobSize'] ?? 18.0).toDouble().clamp(12.0, 36.0).toDouble();
    final String knobShape = module.properties['knobShape']?.toString() ?? 'circle';

    final double h = size.height > 0 ? size.height : 32.0;
    final double trackWidth = math.max(10.0, size.width - 20.0);
    final double maxKnobLeft = math.max(0.0, trackWidth - knobSize);
    final double knobLeft = 10.0 + ratio.clamp(0.0, 1.0) * maxKnobLeft;

    final double activeTrackWidth = math.max(0.0, knobLeft - 10.0 + knobSize / 2);

    return SizedBox(
      height: h,
      child: Stack(
        children: [
          Positioned(
            left: 10,
            right: 10,
            top: (h - 6) / 2,
            height: 6,
            child: Container(
              decoration: BoxDecoration(color: trackColor, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          Positioned(
            left: 10,
            top: (h - 6) / 2,
            width: activeTrackWidth,
            height: 6,
            child: Container(
              decoration: BoxDecoration(color: fillColor.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(3)),
            ),
          ),
          Positioned(
            left: knobLeft,
            top: (h - knobSize) / 2,
            width: knobSize,
            height: knobSize,
            child: Container(
              decoration: BoxDecoration(
                color: fillColor,
                shape: knobShape == 'rectangle' ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: knobShape == 'rectangle' ? BorderRadius.circular(4) : null,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildButton(BuildContext context, UIModule module) {
    final bool isStudio = UISceneModeScope.of(context);
    final bool showOnRuntime = module.properties['showTextOnRuntime'] == true;
    if (!isStudio && !showOnRuntime) {
      return const SizedBox.expand();
    }
    final btnText = module.properties['text']?.toString() ?? module.name;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: module.color.withValues(alpha: module.opacity * 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: module.color.withValues(alpha: 0.45), width: 1),
      ),
      child: Text(
        btnText,
        style: TextStyle(color: module.color, fontSize: 12, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 显示表达式求值（{{key}} 模板替换）
  static String evaluateDisplayExpression(UIModule module, [Map<String, dynamic>? extraContext]) {
    final expr = module.displayExpression?.trim() ?? '';
    if (expr.isEmpty) {
      return module.properties['text']?.toString() ?? module.name;
    }

    String result = expr;
    final context = <String, dynamic>{
      ...module.properties,
      if (extraContext != null) ...extraContext,
    };

    // 标准 {{key}} 替换
    context.forEach((key, value) {
      if (value == null) return;
      final valStr = value is num ? value.toStringAsFixed(0) : value.toString();
      final pattern = RegExp(r'\{\{\s*' + RegExp.escape(key) + r'\s*\}\}');
      result = result.replaceAllMapped(pattern, (_) => valStr);
    });

    // 常见进度别名支持：{{current}}、{{max}}、{{progress.current}} 等
    final cur = context['current'] ?? context['progress']?['current'];
    final mx = context['max'] ?? context['progress']?['max'];
    if (cur != null) {
      final curStr = cur is num ? cur.toStringAsFixed(0) : cur.toString();
      result = result.replaceAll(RegExp(r'\{\{\s*current\s*\}\}'), curStr);
      result = result.replaceAll(RegExp(r'\{\{\s*progress\.current\s*\}\}'), curStr);
    }
    if (mx != null) {
      final mxStr = mx is num ? mx.toStringAsFixed(0) : mx.toString();
      result = result.replaceAll(RegExp(r'\{\{\s*max\s*\}\}'), mxStr);
      result = result.replaceAll(RegExp(r'\{\{\s*progress\.max\s*\}\}'), mxStr);
    }

    // 兜底：如果表达式未被替换且有原始 text，则回退
    if (result == expr) {
      final fallback = module.properties['text']?.toString();
      if (fallback != null && fallback.isNotEmpty) {
        result = fallback;
      }
    }

    return result.isEmpty ? module.name : result;
  }

  static Widget _buildTextBlock(UIModule module) {
    String displayText = module.properties['text']?.toString() ?? module.name;
    final linkedValue = _resolveLinkerValueForText(module);

    if (module.displayExpression != null && module.displayExpression!.trim().isNotEmpty) {
      displayText = evaluateDisplayExpression(
        module,
        LinkerService.getSourceContextForTarget(module),
      );
    } else if (linkedValue != null) {
      displayText = linkedValue;
    }

    final double fs = (module.properties['fontSize'] ?? 14.0).toDouble().clamp(10.0, 72.0).toDouble();
    final String overflowMode = module.properties['overflow']?.toString() ?? 'ellipsis';
    final String alignStr = module.properties['textAlign']?.toString() ?? 'center';

    TextAlign ta = TextAlign.center;
    Alignment boxAlign = Alignment.center;
    if (alignStr == 'left') {
      ta = TextAlign.left;
      boxAlign = Alignment.centerLeft;
    } else if (alignStr == 'right') {
      ta = TextAlign.right;
      boxAlign = Alignment.centerRight;
    }

    final textWidget = Text(
      displayText,
      style: TextStyle(color: module.color, fontSize: fs, fontWeight: FontWeight.w600),
      textAlign: ta,
      overflow: overflowMode == 'ellipsis' ? TextOverflow.ellipsis : null,
    );

    return Container(
      alignment: boxAlign,
      child: overflowMode == 'scroll' ? SingleChildScrollView(child: textWidget) : textWidget,
    );
  }

  /// Linker MVP：尝试解析当前 text 是否被 linker 指向，并返回联动后的值
  static String? _resolveLinkerValueForText(UIModule textModule) {
    return LinkerService.resolveLinkedTextValue(textModule);
  }

  static Widget _buildInputBlock(BuildContext context, UIModule module) {
    final bool isStudio = UISceneModeScope.of(context);
    if (!isStudio) {
      return const SizedBox.expand();
    }
    String placeholder = module.properties['placeholder']?.toString() ?? '请输入...';
    if (placeholder == '请输入...' || placeholder.trim().isEmpty) {
      final linkedVal = LinkerService.resolveTargetValue(module);
      if (linkedVal != null && linkedVal.toString().trim().isNotEmpty) {
        placeholder = '请输入${linkedVal.toString().trim()}...';
      }
    }
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: module.color.withValues(alpha: module.opacity * 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: module.color.withValues(alpha: 0.38), width: 1),
      ),
      child: Text(
        placeholder,
        style: TextStyle(color: module.color.withValues(alpha: 0.75), fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static Widget _buildImageBlock(BuildContext context, UIModule module) {
    final props = module.properties;
    String url = props['url']?.toString() ?? '';
    String assetPath = props['assetPath']?.toString() ?? '';
    final String fitStr = props['fit']?.toString() ?? 'cover';
    final String shapeStr = props['shape']?.toString() ?? 'rectangle';
    final double radiusVal = (props['borderRadius'] ?? 8.0).toDouble();

    final linkedVal = LinkerService.resolveTargetValue(module);
    if (linkedVal != null && linkedVal.toString().trim().isNotEmpty) {
      final str = linkedVal.toString().trim();
      if (str.startsWith('http') || str.startsWith('data:image')) {
        url = str;
      } else {
        assetPath = str;
      }
    }

    BoxFit fit = BoxFit.cover;
    if (fitStr == 'contain') { fit = BoxFit.contain; }
    else if (fitStr == 'fill') { fit = BoxFit.fill; }

    Widget imgContent;
    if (url.isNotEmpty) {
      imgContent = Image.network(
        url,
        fit: fit,
        errorBuilder: (_, _, _) => _buildImagePlaceholder(module, '加载网络图片失败'),
      );
    } else if (assetPath.isNotEmpty) {
      if (assetPath.startsWith('/') || assetPath.contains('\\')) {
        imgContent = Image.file(
          File(assetPath),
          fit: fit,
          errorBuilder: (_, _, _) => _buildImagePlaceholder(module, '读取本地文件失败'),
        );
      } else {
        imgContent = Image.asset(
          assetPath,
          fit: fit,
          errorBuilder: (_, _, _) => _buildImagePlaceholder(module, '未找到内部资产图片'),
        );
      }
    } else {
      imgContent = _buildImagePlaceholder(module, '静态位图占位热区\n(请在编辑器设定图片)');
    }

    if (shapeStr == 'none') {
      return imgContent;
    } else if (shapeStr == 'circle') {
      return ClipOval(child: imgContent);
    } else if (shapeStr == 'capsule') {
      return ClipRRect(borderRadius: BorderRadius.circular(999), child: imgContent);
    } else if (shapeStr == 'heart') {
      return ClipPath(clipper: _PathClipper(getHeartPath), child: imgContent);
    } else if (shapeStr == 'star5') {
      return ClipPath(clipper: _PathClipper((r) => getStarPath(r, 5, 0.45)), child: imgContent);
    } else if (radiusVal > 0) {
      return ClipRRect(borderRadius: BorderRadius.circular(radiusVal), child: imgContent);
    }
    return imgContent;
  }

  static Widget _buildImagePlaceholder(UIModule module, String tip) {
    return Container(
      color: module.color.withValues(alpha: module.opacity * 0.15),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, color: module.color, size: 22),
          const SizedBox(height: 2),
          Text(
            tip,
            style: TextStyle(color: module.color, fontSize: 9, height: 1.2),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  static Widget _buildLineBlock(UIModule module, Size size) {
    final props = module.properties;
    final double th = (props['thickness'] ?? 2.0).toDouble().clamp(1.0, 32.0).toDouble();
    final String ls = props['lineStyle']?.toString() ?? 'solid';
    final String ax = props['axis']?.toString() ?? 'horizontal';
    final double dl = (props['dashLength'] ?? 6.0).toDouble();
    final double gl = (props['gapLength'] ?? 3.0).toDouble();

    return CustomPaint(
      painter: _MultiLinePainter(color: module.color, thickness: th, lineStyle: ls, axis: ax, dashLength: dl, gapLength: gl),
      size: size,
    );
  }

  static Widget _buildSwitchBlock(BuildContext context, UIModule module) {
    final int? inactiveColorVal = module.properties['inactiveTrackColor'] as int?;
    final Color inactiveColor = inactiveColorVal != null ? Color(inactiveColorVal) : Colors.grey.shade300;
    final int? thumbColorVal = module.properties['thumbColor'] as int?;
    final Color thumbColor = thumbColorVal != null ? Color(thumbColorVal) : Colors.white;

    return StatefulBuilder(
      builder: (ctx, setState) {
        final bool currentVal = module.properties['value'] != false;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            module.properties['value'] = !currentVal;
            setState(() {});
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: currentVal ? module.color : inactiveColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: currentVal ? module.color : Colors.grey.shade400, width: 1),
            ),
            alignment: currentVal ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: thumbColor, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))]),
            ),
          ),
        );
      },
    );
  }

  /// 联动器节点渲染（MVP）
  /// 样式：圆角矩形 + 左右端口原点（垂直居中）+ 端口旁标签 + 中间传输方案
  /// 端口已放大并移至中点，方便后续拖拽接线
  static Widget _buildLinkerNode(UIModule module, Size size) {
    final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>() ?? {};

    final sourcePort = linkerData['sourcePort']?.toString() ?? '—';
    final targetPort = linkerData['targetPort']?.toString() ?? '—';
    final scheme = linkerData['scheme']?.toString() ?? '未配置';

    final portColor = module.color.withValues(alpha: 0.95);
    final borderColor = module.color.withValues(alpha: 0.35);
    const double portSize = 15.0; // 放大端口，方便接线交互

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 左上角端口标签
          Positioned(
            left: 8,
            top: 6,
            child: Text(
              sourcePort,
              style: const TextStyle(fontSize: 9, color: Color(0xFF444455), fontWeight: FontWeight.w700),
            ),
          ),

          // 左侧端口（垂直居中）
          Positioned(
            left: 6,
            top: (size.height - portSize) / 2,
            child: Container(
              width: portSize,
              height: portSize,
              decoration: BoxDecoration(
                color: portColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),

          // 右上角端口标签
          Positioned(
            right: 8,
            top: 6,
            child: Text(
              targetPort,
              style: const TextStyle(fontSize: 9, color: Color(0xFF444455), fontWeight: FontWeight.w700),
            ),
          ),

          // 右侧端口（垂直居中）
          Positioned(
            right: 6,
            top: (size.height - portSize) / 2,
            child: Container(
              width: portSize,
              height: portSize,
              decoration: BoxDecoration(
                color: portColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),

          // 中间传输方案
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 2),
              child: Text(
                scheme,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF111116),
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // 底部提示
          Positioned(
            bottom: 3,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '联动器',
                style: TextStyle(
                  fontSize: 8,
                  color: module.color.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 算术算账节点渲染（第一步 MVP）
  /// 浅紫色逻辑背景框，中间粗体运算字符，左端点青色 Data IN，右端点绿色 Data OUT，顶部中心金色 Gate IN
  static Widget _buildMathNodeBlock(UIModule module, Size size) {
    final props = module.properties;
    final String op = props['operation']?.toString() ?? '+';
    final double val = (props['value'] as num?)?.toDouble() ?? 1.0;
    final String valStr = val == val.toInt() ? val.toInt().toString() : val.toString();
    final String opText = op == 'set' ? '= $valStr' : '$op $valStr';

    const double portSize = 9.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDE7F6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF9575CD), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 中点文字算式
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 1.0),
              child: Text(
                '算术计算 : $opText',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF512DA8),
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // 左侧端口 Data IN (青色)
          Positioned(
            left: 4,
            top: (size.height - portSize) / 2,
            child: Container(
              width: portSize,
              height: portSize,
              decoration: BoxDecoration(
                color: const Color(0xFF00ACC1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
          // 右侧端口 Data OUT (绿色)
          Positioned(
            right: 4,
            top: (size.height - portSize) / 2,
            child: Container(
              width: portSize,
              height: portSize,
              decoration: BoxDecoration(
                color: const Color(0xFF66BB6A),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
          // 顶部使能控制孔 Gate IN (金色)
          Positioned(
            top: 2.5,
            left: (size.width - portSize) / 2,
            child: Container(
              width: portSize,
              height: portSize,
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 下拉选择框渲染（第一步 MVP 进阶版）
  /// 白底微圆角矩形，左侧主区域选中，右侧箭头热区点选悬浮展开选项列表，无接线孔
  static Widget _buildSelectBlock(BuildContext context, UIElement element, UIModule module, Size size) {
    final props = module.properties;
    final String currentText = props['current']?.toString() ?? props['defaultValue']?.toString() ?? '选项 1';
    final List<String> options = (props['options'] as List?)?.map((e) => e.toString()).toList() ?? ['选项 1'];
    final bool isStudio = UISceneModeScope.of(context);

    return StatefulBuilder(
      builder: (ctx, setState) {
        final bool isSelected = UISceneModeScope.selectedIdOf(context) == element.id;
        bool isExpanded = props['is_expanded_preview'] == true;
        if (!isSelected && isExpanded) {
          isExpanded = false;
          props['is_expanded_preview'] = false;
        }

        final Widget content = Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isExpanded ? const Color(0xFF7E57C2) : const Color(0xFFD0D0D8),
              width: isExpanded ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isExpanded ? 0.12 : 0.06),
                blurRadius: isExpanded ? 6 : 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text(
                    currentText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111116),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (isStudio)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    props['is_expanded_preview'] = !isExpanded;
                    setState(() {});
                  },
                  child: Container(
                    width: 36,
                    height: double.infinity,
                    alignment: Alignment.center,
                    child: Text(
                      isExpanded ? '▲' : '▼',
                      style: TextStyle(
                        fontSize: 9,
                        color: isExpanded ? const Color(0xFF7E57C2) : const Color(0xFF888896),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Text('▼', style: TextStyle(fontSize: 9, color: Color(0xFF888896))),
                ),
            ],
          ),
        );

        if (!isExpanded || !isStudio) return content;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            Positioned(
              top: size.height + 4,
              left: 0,
              right: 0,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF7E57C2).withValues(alpha: 0.3)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: options.map((opt) {
                        final bool active = opt == currentText;
                        return InkWell(
                          onTap: () {
                            props['current'] = opt;
                            props['is_expanded_preview'] = false;
                            setState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            color: active ? const Color(0xFFEDE7F6) : Colors.transparent,
                            child: Text(
                              opt,
                              style: TextStyle(
                                fontSize: 12,
                                color: active ? const Color(0xFF512DA8) : const Color(0xFF111116),
                                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 多态状态指示点渲染：工作室中 36x36 磁吸感应框，中心呈现 14x14 霓虹 LED 灯
  static Widget _buildIndicatorBlock(BuildContext context, UIElement element, UIModule module, Size size) {
    final props = module.properties;
    final bool isStudio = UISceneModeScope.of(context);
    final String currentVal = (LinkerService.resolveTargetValue(module) ?? props['currentValue'] ?? '').toString().trim();
    final List rules = (props['statusRules'] as List?) ?? [];

    int activeColorInt = (props['defaultColor'] as int?) ?? 0xFF9E9E9E;
    bool activeGlow = props['defaultGlow'] == true;
    double glowRadius = 12.0;

    for (final raw in rules) {
      if (raw is! Map) continue;
      final rule = Map<String, dynamic>.from(raw);
      final matchType = rule['matchType']?.toString() ?? 'exact';
      bool matched = false;

      if (matchType == 'exact') {
        final targetVal = rule['matchValue']?.toString().trim() ?? '';
        if (currentVal == targetVal && targetVal.isNotEmpty) {
          matched = true;
        }
      } else if (matchType == 'bool') {
        final targetBool = rule['matchValue']?.toString().toLowerCase() == 'true';
        final curBool = currentVal.toLowerCase() == 'true' || currentVal == '1' || currentVal == '开启';
        if (curBool == targetBool && currentVal.isNotEmpty) {
          matched = true;
        }
      } else if (matchType == 'range') {
        final double? curNum = double.tryParse(currentVal);
        final double? targetNum = double.tryParse(rule['matchValNum']?.toString() ?? '');
        final op = rule['matchOp']?.toString() ?? '>';
        if (curNum != null && targetNum != null) {
          if (op == '>' && curNum > targetNum) matched = true;
          if (op == '<' && curNum < targetNum) matched = true;
          if (op == '>=' && curNum >= targetNum) matched = true;
          if (op == '<=' && curNum <= targetNum) matched = true;
          if (op == '==' && curNum == targetNum) matched = true;
        }
      }

      if (matched) {
        activeColorInt = (rule['color'] as int?) ?? activeColorInt;
        activeGlow = rule['isGlow'] == true;
        glowRadius = (rule['glowRadius'] as num?)?.toDouble() ?? 12.0;
        break;
      }
    }

    final Color activeColor = Color(activeColorInt);
    final double dotSize = (props['dotSize'] as num?)?.toDouble().clamp(8.0, 28.0) ?? 14.0;

    Widget dot = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        color: activeColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.2),
        boxShadow: activeGlow
            ? [
          BoxShadow(color: activeColor.withValues(alpha: 0.65), blurRadius: glowRadius, spreadRadius: 1.5),
          BoxShadow(color: activeColor.withValues(alpha: 0.35), blurRadius: glowRadius * 1.6, spreadRadius: 3.0),
        ]
            : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 2, offset: const Offset(0, 1)),
        ],
      ),
    );

    if (isStudio) {
      return Container(
        width: size.width,
        height: size.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activeColor.withValues(alpha: 0.06),
          shape: BoxShape.circle,
          border: Border.all(color: activeColor.withValues(alpha: 0.25), width: 1, style: BorderStyle.solid),
        ),
        child: dot,
      );
    }

    return Center(child: dot);
  }

  /// 局部滚动视窗渲染 (第二步全盘完备)：支持双层纯色封底、阻尼切换与收容子元素渲染
  static Widget _buildScrollFrameBlock(BuildContext context, UIElement element, UIModule module, Size size) {
    final props = module.properties;
    final bool isStudio = UISceneModeScope.of(context);
    final String scrollMode = props['scrollMode']?.toString() ?? 'vertical';
    final bool clipToBounds = props['clipToBounds'] != false;
    final double contentWidth = (props['contentWidth'] as num?)?.toDouble() ?? 300.0;
    final double contentHeight = (props['contentHeight'] as num?)?.toDouble() ?? 500.0;
    final int bgColorVal = (props['backgroundColor'] as int?) ?? 0xFFF0F0F5;
    final Color bgColor = Color(bgColorVal);
    final String physicsMode = props['physics']?.toString() ?? 'bouncing';
    final ScrollPhysics scrollPhysics = physicsMode == 'clamping' ? const ClampingScrollPhysics() : const BouncingScrollPhysics();

    final List<UIElement> adoptedChildren = (props['adoptedChildElements'] as List?)
        ?.map((e) => UIElement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList() ??
        [];

    Widget innerContent;
    if (adoptedChildren.isNotEmpty) {
      final childWidgets = <Widget>[];
      for (final child in adoptedChildren) {
        childWidgets.add(
          Positioned(
            left: child.offset.dx,
            top: child.offset.dy,
            width: child.size.width,
            height: child.size.height,
            child: render(context, child),
          ),
        );
      }
      innerContent = Container(
        width: contentWidth,
        height: contentHeight,
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
        child: Stack(clipBehavior: Clip.none, children: childWidgets),
      );
    } else {
      innerContent = Container(
        width: scrollMode == 'horizontal' ? contentWidth : (scrollMode == 'omni' ? contentWidth : size.width),
        height: scrollMode == 'vertical' ? contentHeight : (scrollMode == 'omni' ? contentHeight : size.height),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: isStudio
            ? Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              scrollMode == 'omni' ? Icons.pan_tool_alt_outlined : (scrollMode == 'horizontal' ? Icons.swap_horiz : Icons.swap_vert),
              size: 28,
              color: const Color(0xFF3F51B5).withValues(alpha: 0.6),
            ),
            const SizedBox(height: 8),
            Text(
              scrollMode == 'omni'
                  ? '🗺️ 2D 无极探索沙盘\n[虚拟底板: ${contentWidth.toInt()}x${contentHeight.toInt()}px]'
                  : '📜 局部滚动视窗 (${scrollMode == 'horizontal' ? '横向' : '竖向'}滑动)\n[虚拟高宽: ${contentWidth.toInt()}x${contentHeight.toInt()}px]',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF3F51B5), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text('请在属性配置页或点击“进入内部空间”对收容子元素排版', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        )
            : const SizedBox.shrink(),
      );
    }

    Widget viewport;
    if (scrollMode == 'omni') {
      viewport = InteractiveViewer(
        constrained: false,
        panEnabled: true,
        scaleEnabled: false,
        child: innerContent,
      );
    } else {
      viewport = SingleChildScrollView(
        scrollDirection: scrollMode == 'horizontal' ? Axis.horizontal : Axis.vertical,
        physics: scrollPhysics,
        child: innerContent,
      );
    }

    // 保险一：外层同色封底（在 viewport 外部在套上一层自备颜色的 Container，回弹时露出同色底板）
    final Widget sealedViewport = Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: clipToBounds ? ClipRRect(borderRadius: BorderRadius.circular(12), child: viewport) : viewport,
    );

    final Widget protectedViewport = NotificationListener<ScrollNotification>(
      onNotification: (_) => true, // 吞没滚动事件，手势防穿透隔离
      child: sealedViewport,
    );

    if (isStudio) {
      return Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF3F51B5), width: 1.5, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            protectedViewport,
            Positioned(
              top: 6,
              right: 8,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3F51B5).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    scrollMode == 'omni' ? '🗺️ 无极沙盘' : '📜 视窗容器',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return protectedViewport;
  }

  /// 定时脉冲发生器渲染：工作室显形为带自测热区的逻辑卡片，运行时彻底隐形 SizedBox.shrink()
  static Widget _buildTimerBlock(BuildContext context, UIElement element, UIModule module, Size size) {
    final bool isStudio = UISceneModeScope.of(context);
    return _TimerBlockWidget(element: element, module: module, size: size, isStudio: isStudio);
  }

}

class _TimerBlockWidget extends StatefulWidget {
  final UIElement element;
  final UIModule module;
  final Size size;
  final bool isStudio;

  const _TimerBlockWidget({required this.element, required this.module, required this.size, required this.isStudio});

  @override
  State<_TimerBlockWidget> createState() => _TimerBlockWidgetState();
}

class _TimerBlockWidgetState extends State<_TimerBlockWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkTimerState();
  }

  @override
  void didUpdateWidget(covariant _TimerBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkTimerState();
  }

  void _checkTimerState() {
    final props = widget.module.properties;
    final bool isStudio = widget.isStudio;
    final bool isRunningPreview = props['isRunning_preview'] == true;
    final bool autoStart = props['autoStart'] == true;
    final bool isRunning = isRunningPreview || (!isStudio && autoStart);
    final double interval = (props['interval'] as num?)?.toDouble() ?? 1.0;
    final int intervalMs = (interval * 1000).clamp(100, 60000).toInt();
    final String pulseType = props['pulseType']?.toString() ?? 'increment';
    final double stepVal = (props['stepValue'] as num?)?.toDouble() ?? 1.0;
    final bool loop = props['loop'] != false;

    if (isRunning && _timer == null) {
      _timer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          final double cur = (props['currentVal'] as num?)?.toDouble() ?? 0.0;
          if (pulseType == 'toggle') {
            props['currentVal'] = (cur == 1.0) ? 0.0 : 1.0;
          } else if (pulseType == 'timestamp') {
            props['currentVal'] = cur + interval;
          } else if (pulseType == 'countdown') {
            final double nextVal = cur - stepVal;
            if (nextVal <= 0.0) {
              props['currentVal'] = 0.0;
              if (!loop) {
                props['isRunning_preview'] = false;
                timer.cancel();
                _timer = null;
              }
            } else {
              props['currentVal'] = nextVal;
            }
          } else {
            props['currentVal'] = cur + stepVal;
          }
        });
      });
    } else if (!isRunning && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isStudio) {
      return const SizedBox.shrink(); // 运行时对读者界面彻底隐形，但后台 initState 时钟依然能狂奔发线！
    }
    final props = widget.module.properties;
    final double interval = (props['interval'] as num?)?.toDouble() ?? 1.0;
    final double currentVal = (props['currentVal'] as num?)?.toDouble() ?? 0.0;
    final bool isRunning = props['isRunning_preview'] == true;
    final String pulseType = props['pulseType']?.toString() ?? 'increment';

    String schemeLabel = '⚡ 递增脉冲';
    if (pulseType == 'toggle') schemeLabel = '⚡ 0/1翻转';
    if (pulseType == 'timestamp') schemeLabel = '⚡ 运行秒戳';

    final double stepVal = (props['stepValue'] as num?)?.toDouble() ?? 1.0;

    final Widget playButton = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          props['isRunning_preview'] = !isRunning;
          if (!isRunning) {
            if (pulseType == 'toggle') {
              props['currentVal'] = (currentVal == 1.0) ? 0.0 : 1.0;
            } else if (pulseType == 'timestamp') {
              props['currentVal'] = currentVal + interval;
            } else if (pulseType == 'countdown') {
              props['currentVal'] = (currentVal - stepVal).clamp(0.0, double.infinity);
            } else {
              props['currentVal'] = currentVal + stepVal;
            }
          }
        });
        _checkTimerState();
      },
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isRunning ? const Color(0xFFFF6D00) : const Color(0xFFFF9100).withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isRunning ? Icons.pause : Icons.play_arrow,
          size: 12,
          color: isRunning ? Colors.white : const Color(0xFFF57C00),
        ),
      ),
    );

    Widget content;
    if (widget.size.height < 44) {
      // 高度自适应降级防溢出：当高度小于44px（如遗留旧卡或微缩视图）时，单行横向排布
      content = Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  isRunning ? Icons.timer : Icons.timer_outlined,
                  size: 13,
                  color: isRunning ? const Color(0xFFFF6D00) : const Color(0xFFF57C00),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${interval.toStringAsFixed(1)}s | #${currentVal.toInt()}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isRunning ? FontWeight.w900 : FontWeight.bold,
                      color: isRunning ? const Color(0xFFE65100) : const Color(0xFFF57C00),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          playButton,
        ],
      );
    } else {
      // 标准双行仪表盘：上行时间与次数，下行脉冲方案与操作热区
      content = Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            children: [
              Icon(
                isRunning ? Icons.timer : Icons.timer_outlined,
                size: 14,
                color: isRunning ? const Color(0xFFFF6D00) : const Color(0xFFF57C00),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${interval.toStringAsFixed(1)}s | #${currentVal.toInt()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isRunning ? FontWeight.w900 : FontWeight.bold,
                    color: isRunning ? const Color(0xFFE65100) : const Color(0xFFF57C00),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  schemeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isRunning ? const Color(0xFFE65100) : const Color(0xFFF57C00),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              playButton,
            ],
          ),
        ],
      );
    }

    return Container(
      width: widget.size.width,
      height: widget.size.height,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isRunning ? const Color(0xFFFFF3E0) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning ? const Color(0xFFFF6D00) : const Color(0xFFFF9100),
          width: isRunning ? 1.6 : 1.2,
        ),
        boxShadow: isRunning
            ? [
          BoxShadow(color: const Color(0xFFFF9100).withValues(alpha: 0.35), blurRadius: 6, spreadRadius: 1),
        ]
            : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1)),
        ],
      ),
      child: content,
    );
  }
}


Path getHeartPath(Rect rect) {
  final w = rect.width;
  final h = rect.height;
  final l = rect.left;
  final t = rect.top;
  final path = Path();
  path.moveTo(l + 0.5 * w, t + h * 0.35);
  path.cubicTo(l + 0.2 * w, t + h * 0.1, l - 0.25 * w, t + h * 0.6, l + 0.5 * w, t + h);
  path.cubicTo(l + 1.25 * w, t + h * 0.6, l + 0.8 * w, t + h * 0.1, l + 0.5 * w, t + h * 0.35);
  path.close();
  return path;
}

Path getStarPath(Rect rect, int points, double innerRatio) {
  final cx = rect.center.dx;
  final cy = rect.center.dy;
  final rx = rect.width / 2;
  final ry = rect.height / 2;
  final path = Path();
  final step = math.pi / points;
  var angle = -math.pi / 2;

  for (var i = 0; i < points * 2; i++) {
    final rRatio = (i % 2 == 0) ? 1.0 : innerRatio;
    final x = cx + rx * rRatio * math.cos(angle);
    final y = cy + ry * rRatio * math.sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
    angle += step;
  }
  path.close();
  return path;
}

class _PathClipper extends CustomClipper<Path> {
  final Path Function(Rect rect) getPathFunc;
  _PathClipper(this.getPathFunc);
  @override
  Path getClip(Size size) => getPathFunc(Rect.fromLTWH(0, 0, size.width, size.height));
  @override
  bool shouldReclip(covariant _PathClipper oldClipper) => false;
}

class UIPrimitiveArtPainter extends CustomPainter {
  final Map<String, dynamic> properties;

  UIPrimitiveArtPainter(this.properties);

  @override
  void paint(Canvas canvas, Size size) {
    final rawLayers = properties['layers'];
    if (rawLayers is! List || size.width <= 0 || size.height <= 0) return;

    final layers = <UIPrimitiveLayer>[];
    for (final raw in rawLayers) {
      if (raw is Map) {
        layers.add(UIPrimitiveLayer.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    if (layers.isEmpty) return;

    for (final layer in layers) {
      _paintLayer(canvas, size, layer);
    }
  }

  Rect _layerRect(Size canvasSize, UIPrimitiveLayer layer) {
    final x = layer.offset.dx * canvasSize.width;
    final y = layer.offset.dy * canvasSize.height;
    final w = layer.size.width * canvasSize.width;
    final h = layer.size.height * canvasSize.height;
    return Rect.fromLTWH(x, y, w, h);
  }

  void _paintLayer(Canvas canvas, Size size, UIPrimitiveLayer layer) {
    final rect = _layerRect(size, layer);
    if (rect.width <= 0 || rect.height <= 0) return;

    final paint = Paint()
      ..color = layer.color.withValues(alpha: layer.opacity)
      ..style = PaintingStyle.fill;

    final r = layer.borderRadius;

    switch (layer.shape) {
      case UIModuleShape.circle:
        canvas.drawOval(rect, paint);
        break;
      case UIModuleShape.capsule:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
          paint,
        );
        break;
      case UIModuleShape.rounded:
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), paint);
        break;
      case UIModuleShape.heart:
        canvas.drawPath(getHeartPath(rect), paint);
        break;
      case UIModuleShape.star5:
        canvas.drawPath(getStarPath(rect, 5, 0.45), paint);
        break;
      case UIModuleShape.star4:
        canvas.drawPath(getStarPath(rect, 4, 0.4), paint);
        break;
      case UIModuleShape.rectangle:
        canvas.drawRect(rect, paint);
        break;
    }

    // 额外描边支持
    if (layer.properties['stroke'] == true) {
      final strokePaint = Paint()
        ..color = (layer.properties['strokeColor'] != null
            ? Color(layer.properties['strokeColor'])
            : Colors.black)
            .withValues(alpha: layer.opacity * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (layer.properties['strokeWidth'] ?? 1.5).toDouble();
      switch (layer.shape) {
        case UIModuleShape.circle:
          canvas.drawOval(rect, strokePaint);
          break;
        case UIModuleShape.capsule:
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
            strokePaint,
          );
          break;
        case UIModuleShape.rounded:
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), strokePaint);
          break;
        case UIModuleShape.heart:
          canvas.drawPath(getHeartPath(rect), strokePaint);
          break;
        case UIModuleShape.star5:
          canvas.drawPath(getStarPath(rect, 5, 0.45), strokePaint);
          break;
        case UIModuleShape.star4:
          canvas.drawPath(getStarPath(rect, 4, 0.4), strokePaint);
          break;
        case UIModuleShape.rectangle:
          canvas.drawRect(rect, strokePaint);
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant UIPrimitiveArtPainter oldDelegate) {
    return oldDelegate.properties != properties;
  }
}

class _MultiLinePainter extends CustomPainter {
  final Color color;
  final double thickness;
  final String lineStyle;
  final String axis;
  final double dashLength;
  final double gapLength;

  _MultiLinePainter({required this.color, required this.thickness, required this.lineStyle, required this.axis, required this.dashLength, required this.gapLength});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = lineStyle == 'dotted' ? StrokeCap.round : StrokeCap.butt;

    final bool isHoriz = axis != 'vertical';
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    void drawLineSegment(Offset p1, Offset p2) {
      if (lineStyle == 'solid') {
        canvas.drawLine(p1, p2, paint);
      } else if (lineStyle == 'dotted') {
        final double step = thickness * 2.5;
        final double totalLen = (p2 - p1).distance;
        final Offset dir = (p2 - p1) / (totalLen > 0 ? totalLen : 1.0);
        var dist = 0.0;
        while (dist <= totalLen) {
          canvas.drawPoints(ui.PointMode.points, [p1 + dir * dist], paint);
          dist += step;
        }
      } else {
        final double dl = math.max(1.0, dashLength);
        final double gl = math.max(1.0, gapLength);
        final double totalLen = (p2 - p1).distance;
        final Offset dir = (p2 - p1) / (totalLen > 0 ? totalLen : 1.0);
        var dist = 0.0;
        while (dist < totalLen) {
          final double next = math.min(totalLen, dist + dl);
          canvas.drawLine(p1 + dir * dist, p1 + dir * next, paint);
          dist = next + gl;
        }
      }
    }

    if (lineStyle == 'curve') {
      final curvePath = Path();
      if (isHoriz) {
        curvePath.moveTo(0, cy);
        curvePath.quadraticBezierTo(size.width / 2, size.height * 0.88, size.width, cy);
      } else {
        curvePath.moveTo(cx, 0);
        curvePath.quadraticBezierTo(size.width * 0.88, size.height / 2, cx, size.height);
      }
      canvas.drawPath(curvePath, paint);
    } else if (lineStyle == 'double') {
      final double offset = thickness * 1.5;
      if (isHoriz) {
        drawLineSegment(Offset(0, cy - offset), Offset(size.width, cy - offset));
        drawLineSegment(Offset(0, cy + offset), Offset(size.width, cy + offset));
      } else {
        drawLineSegment(Offset(cx - offset, 0), Offset(cx - offset, size.height));
        drawLineSegment(Offset(cx + offset, 0), Offset(cx + offset, size.height));
      }
    } else {
      if (isHoriz) {
        drawLineSegment(Offset(0, cy), Offset(size.width, cy));
      } else {
        drawLineSegment(Offset(cx, 0), Offset(cx, size.height));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MultiLinePainter old) =>
      old.color != color || old.thickness != thickness || old.lineStyle != lineStyle || old.axis != axis || old.dashLength != dashLength || old.gapLength != gapLength;
}

class _RingProgressBarPainter extends CustomPainter {
  final double progress;
  final Color fillColor;
  final Color trackColor;
  final double strokeWidth;

  _RingProgressBarPainter({required this.progress, required this.fillColor, required this.trackColor, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);
    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress.clamp(0.0, 1.0), false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingProgressBarPainter old) =>
      old.progress != progress || old.fillColor != fillColor || old.trackColor != trackColor || old.strokeWidth != strokeWidth;
}
