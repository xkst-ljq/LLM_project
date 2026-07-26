import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/ui_assembly_info.dart';
import '../services/ui_engine/ui_models.dart';
import '../services/ui_engine/ui_renderer.dart';

/// Runtime-style renderer for an Assembly UI.
///
/// Design coordinates are always 360 × pcbHeight. The runtime viewport never
/// stretches PCB non-uniformly and never upscales above 1:1: it uses a single
/// scale-down contain scale, centers the PCB, and optionally fills letterbox
/// space with a blurred cover-scaled copy.
class UIAssemblyRuntimeView extends StatelessWidget {
  static const double designWidth = 360.0;

  final UIAssemblyInfo assemblyInfo;
  final String? activePageId;
  final bool showBlurredBackdrop;
  final bool showDebugInfo;
  final double blurSigma;

  const UIAssemblyRuntimeView({
    super.key,
    required this.assemblyInfo,
    this.activePageId,
    this.showBlurredBackdrop = true,
    this.showDebugInfo = false,
    this.blurSigma = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final pages = _restorePages(assemblyInfo);
    final activePage = _resolveActivePage(pages, activePageId);
    final ancestors = _ancestorPagesFor(pages, activePage);
    final designHeight = assemblyInfo.pcbHeight.clamp(64.0, 2000.0).toDouble();
    final designSize = Size(designWidth, designHeight);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : designSize.width;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : designSize.height;

        final rawContainScale = math.min(
          availableWidth / designSize.width,
          availableHeight / designSize.height,
        );
        final safeContainScale = rawContainScale.isFinite && rawContainScale > 0
            ? math.min(1.0, rawContainScale)
            : 1.0;
        final renderedWidth = designSize.width * safeContainScale;
        final renderedHeight = designSize.height * safeContainScale;

        return ClipRect(
          child: Stack(
            children: [
              if (showBlurredBackdrop)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _buildFittedDesignSurface(
                      context,
                      pages: pages,
                      activePage: activePage,
                      ancestors: ancestors,
                      designSize: designSize,
                      fit: BoxFit.cover,
                      blur: true,
                      opacity: 0.48,
                    ),
                  ),
                ),
              Positioned.fill(
                child: _buildFittedDesignSurface(
                  context,
                  pages: pages,
                  activePage: activePage,
                  ancestors: ancestors,
                  designSize: designSize,
                  fit: BoxFit.scaleDown,
                  blur: false,
                ),
              ),
              if (showDebugInfo)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: _buildDebugInfo(
                    scale: safeContainScale,
                    renderedWidth: renderedWidth,
                    renderedHeight: renderedHeight,
                    designHeight: designHeight,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFittedDesignSurface(
    BuildContext context, {
    required List<AssemblyPage> pages,
    required AssemblyPage activePage,
    required List<AssemblyPage> ancestors,
    required Size designSize,
    required BoxFit fit,
    required bool blur,
    double opacity = 1.0,
  }) {
    Widget child = ClipRect(
      child: FittedBox(
        fit: fit,
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: designSize.width,
          height: designSize.height,
          child: _buildDesignSurface(
            context,
            pages: pages,
            activePage: activePage,
            ancestors: ancestors,
            designSize: designSize,
          ),
        ),
      ),
    );

    if (blur) {
      child = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Opacity(opacity: opacity, child: child),
      );
      child = Stack(
        fit: StackFit.expand,
        children: [
          child,
          Container(color: Colors.black.withValues(alpha: 0.12)),
        ],
      );
    }

    return child;
  }

  Widget _buildDesignSurface(
    BuildContext context, {
    required List<AssemblyPage> pages,
    required AssemblyPage activePage,
    required List<AssemblyPage> ancestors,
    required Size designSize,
  }) {
    final elementsForSnapshot = <UIElement>[
      ...ancestors.expand((page) => page.elements),
      ...activePage.elements,
    ];
    final snapshot = LinkerSnapshot.fromElements(elementsForSnapshot);
    final borderRadius = BorderRadius.circular(assemblyInfo.pcbRounded ? 20 : 0);

    return UILinkerSnapshotScope(
      snapshot: snapshot,
      child: UISceneModeScope(
        isStudioCreationMode: false,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Container(
            width: designSize.width,
            height: designSize.height,
            decoration: BoxDecoration(
              color: Color(assemblyInfo.pcbColorValue),
              borderRadius: borderRadius,
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                ...ancestors.expand((page) {
                  return page.elements.map(
                    (element) => _buildRuntimeElement(
                      context,
                      element,
                      overrides: page.propertyOverrides,
                      opacity: 0.35,
                    ),
                  );
                }),
                ...activePage.elements.map(
                  (element) => _buildRuntimeElement(
                    context,
                    element,
                    overrides: activePage.propertyOverrides,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuntimeElement(
    BuildContext context,
    UIElement element, {
    List<PropertyOverride> overrides = const <PropertyOverride>[],
    double opacity = 1.0,
  }) {
    final displayElement = _applyPropertyOverridesToElement(element, overrides);
    Widget child = UIRenderer.render(context, displayElement);
    if (opacity < 1.0) {
      child = Opacity(opacity: opacity, child: child);
    }
    return Positioned(
      left: element.offset.dx,
      top: element.offset.dy,
      width: element.size.width,
      height: element.size.height,
      child: child,
    );
  }

  Widget _buildDebugInfo({
    required double scale,
    required double renderedWidth,
    required double renderedHeight,
    required double designHeight,
  }) {
    return Align(
      alignment: Alignment.center,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            '设计 360×${designHeight.toStringAsFixed(0)} · '
            'scale ${scale.toStringAsFixed(3)} · '
            '渲染 ${renderedWidth.toStringAsFixed(0)}×${renderedHeight.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  static List<AssemblyPage> _restorePages(UIAssemblyInfo info) {
    final pages = <AssemblyPage>[];
    final rawPages = info.pagesJson.trim();
    if (rawPages.isNotEmpty && rawPages != '[]') {
      try {
        final decoded = jsonDecode(rawPages);
        if (decoded is List) {
          pages.addAll(
            decoded.whereType<Map>().map(
                  (item) => AssemblyPage.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                ),
          );
        }
      } catch (_) {
        pages.clear();
      }
    }

    if (pages.isNotEmpty) {
      pages.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return pages;
    }

    final legacyElements = <UIElement>[];
    final rawElements = info.elementsJson.trim();
    if (rawElements.isNotEmpty && rawElements != '[]') {
      try {
        final decoded = jsonDecode(rawElements);
        if (decoded is List) {
          legacyElements.addAll(
            decoded.whereType<Map>().map(
                  (item) => UIElement.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                ),
          );
        }
      } catch (_) {}
    }

    return [
      AssemblyPage(
        id: 'runtime_root',
        name: '主菜单',
        type: 'base',
        elements: legacyElements,
      ),
    ];
  }

  static AssemblyPage _resolveActivePage(
    List<AssemblyPage> pages,
    String? activePageId,
  ) {
    if (pages.isEmpty) {
      return AssemblyPage(id: 'runtime_empty', name: '主菜单', type: 'base');
    }
    if (activePageId != null && activePageId.isNotEmpty) {
      for (final page in pages) {
        if (page.id == activePageId) return page;
      }
    }
    final bases = pages.where((page) => page.isBase).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return bases.isNotEmpty ? bases.first : pages.first;
  }

  static List<AssemblyPage> _ancestorPagesFor(
    List<AssemblyPage> pages,
    AssemblyPage activePage,
  ) {
    final ancestors = <AssemblyPage>[];
    var parentId = activePage.parentPageId;
    final visited = <String>{activePage.id};
    while (parentId != null && parentId.isNotEmpty && visited.add(parentId)) {
      final index = pages.indexWhere((page) => page.id == parentId);
      if (index == -1) break;
      final page = pages[index];
      ancestors.insert(0, page);
      parentId = page.parentPageId;
    }
    return ancestors;
  }

  static UIElement _applyPropertyOverridesToElement(
    UIElement element,
    List<PropertyOverride> overrides,
  ) {
    if (!element.isComposite || element.composite == null || overrides.isEmpty) {
      return element;
    }

    UIElement patchNode(UIElement node) {
      if (!node.isComposite && node.module != null) {
        final matched = overrides
            .where((override) => override.componentId == node.id)
            .toList();
        if (matched.isEmpty) return node;
        final props = Map<String, dynamic>.from(
          _deepCloneValue(node.module!.properties) as Map,
        );
        for (final override in matched) {
          props.addAll(
            Map<String, dynamic>.from(
              _deepCloneValue(override.overrides) as Map,
            ),
          );
        }
        return node.copyWith(module: node.module!.copyWith(properties: props));
      }
      if (node.isComposite && node.composite != null) {
        return node.copyWith(
          composite: node.composite!.copyWith(
            children: node.composite!.children.map(patchNode).toList(),
          ),
        );
      }
      return node;
    }

    return element.copyWith(
      composite: element.composite!.copyWith(
        children: element.composite!.children.map(patchNode).toList(),
      ),
    );
  }

  static dynamic _deepCloneValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(key, _deepCloneValue(entry)),
      );
    }
    if (value is List) return value.map(_deepCloneValue).toList();
    return value;
  }
}
