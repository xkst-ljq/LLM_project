part of 'ui_studio_page.dart';

/// 四个侧边抽屉
mixin _UIStudioDrawers on _UIStudioDialogs {
  // ===== 图层管理抽屉 =====
  Widget _buildDedicatedLayerManagerDrawer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 25)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showLayerManager = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_forward_ios,
                                size: 10, color: Color(0xFF00ACC1)),
                            Text(
                              ' 收回',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF00ACC1),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Text(
                      '动态图层总览',
                      style: TextStyle(
                        color: Color(0xFF111116),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.black12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: const Color(0xFF111116),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.add_circle, size: 18),
                  label: const Text('新建图层',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _createNewSceneLayer,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  '图层专注模式：仅激活选中层，屏蔽旧图层误触',
                  style: TextStyle(fontSize: 10, color: Color(0xFF888896)),
                ),
              ),
              const Divider(color: Colors.black12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  children: _sceneLayers.map((ly) {
                    final bool isSel = _activeLayerIndex == ly.id;
                    return Card(
                      color: isSel
                          ? const Color(0xFF111116)
                          : const Color(0xFFF6F6F9),
                      elevation: isSel ? 4 : 0,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSel
                              ? const Color(0xFF00E5FF)
                              : Colors.black.withValues(alpha: 0.05),
                          width: isSel ? 1.5 : 1,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.layers,
                          color: isSel
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFF888896),
                          size: 18,
                        ),
                        title: Text(
                          ly.name,
                          style: TextStyle(
                            color: isSel ? Colors.white : const Color(0xFF111116),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        trailing: isSel
                            ? const Icon(Icons.check_circle,
                            color: Color(0xFF00E5FF), size: 18)
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        onTap: () => _switchActiveSceneLayer(ly.id),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== 左侧原材料抽屉 =====
  Widget _buildLeftCompactAssetPreviewDrawer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '原材料',
                      style: TextStyle(
                        color: Color(0xFF111116),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showLeftDrawer = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4081).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Text(
                              '收回 ',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFFF4081),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Icon(Icons.arrow_back_ios,
                                size: 10, color: Color(0xFFFF4081)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.black12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  children: [
                    const Text('数据条原子预览',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'prog',
                        name: '数据条原子',
                        type: 'progress',
                        properties: {'min': 0, 'max': 100, 'current': 75},
                        color: const Color(0xFFFF4081),
                      ),
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.75,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF4081),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('面原子预览',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'surface',
                        name: '面原子 / 胶囊',
                        type: 'surface',
                        properties: {},
                        color: const Color(0xFF651FFF),
                        material: UIModuleMaterial.gradient,
                        shape: UIModuleShape.capsule,
                      ),
                      Container(
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFF651FFF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('点击热区原子预览',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'btn',
                        name: '点击热区原子',
                        type: 'button',
                        properties: {'action': 'tap'},
                        color: Colors.transparent,
                      ),
                      Container(
                        height: 34,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFF4081),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '点击热区',
                          style: TextStyle(
                            color: Color(0xFFFF4081),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('文本原子预览',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'txt',
                        name: '文本原子',
                        type: 'text',
                        properties: {'text': '文本'},
                        color: const Color(0xFF00B0FF),
                      ),
                      const SizedBox(
                        height: 30,
                        child: Center(
                          child: Text(
                            '文本',
                            style: TextStyle(
                              color: Color(0xFF00B0FF),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('滑块原子预览',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'slider',
                        name: '滑块原子',
                        type: 'slider',
                        properties: {'min': 0, 'max': 100, 'current': 50},
                        color: const Color(0xFF00ACC1),
                      ),
                      SizedBox(
                        height: 34,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 5,
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E2E8),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            Container(
                              height: 5,
                              width: 62,
                              margin: const EdgeInsets.only(left: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00ACC1),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            Positioned(
                              left: 58,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00ACC1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('输入热区原子预览',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'inp',
                        name: '输入热区原子',
                        type: 'input',
                        properties: {'variable': 'var.input'},
                        color: Colors.transparent,
                      ),
                      Container(
                        height: 34,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFF00ACC1),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '输入热区',
                          style: TextStyle(
                            color: Color(0xFF00ACC1),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('布尔开关预览',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'sw',
                        name: '布尔开关原子',
                        type: 'switch',
                        properties: {'value': true, 'variable': 'switch_var'},
                        color: const Color(0xFF00E676),
                      ),
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('多功能线段预览',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'ln',
                        name: '多功能线段原子',
                        type: 'line',
                        properties: {'thickness': 2.0, 'lineStyle': 'solid', 'axis': 'horizontal', 'dashLength': 6.0, 'gapLength': 3.0},
                        color: const Color(0xFFB0BEC5),
                      ),
                      Container(
                        height: 20,
                        alignment: Alignment.center,
                        child: Container(
                          height: 2,
                          color: const Color(0xFFB0BEC5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('静态位图插槽预览',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'img',
                        name: '静态位图插槽原子',
                        type: 'image',
                        properties: {'url': '', 'fit': 'cover', 'shape': 'rectangle', 'borderRadius': 8.0, 'assetPath': ''},
                        color: const Color(0xFF2979FF),
                      ),
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF90CAF9)),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_outlined, size: 20, color: Color(0xFF2979FF)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('联动器节点',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'linker_mvp',
                        name: '联动器',
                        type: 'linker',
                        properties: {
                          'linker': {
                            'sourceModuleId': '',
                            'sourcePort': '',
                            'sourceType': '',
                            'targetModuleId': '',
                            'targetPort': '',
                            'targetType': '',
                            'scheme': '未配置',
                            'enabled': true,
                          },
                        },
                        color: const Color(0xFF00ACC1),
                      ),
                      Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF00ACC1).withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 8,
                              top: 6,
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF00ACC1),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Text(
                                    'current',
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: Color(0xFF555562),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              right: 8,
                              top: 6,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'text',
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: Color(0xFF555562),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF00ACC1),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Center(
                              child: Text(
                                'current→text',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111116),
                                ),
                              ),
                            ),
                            const Positioned(
                              bottom: 3,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Text(
                                  '联动器',
                                  style: TextStyle(
                                    fontSize: 7,
                                    color: Color(0xFF00ACC1),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('算术计算节点',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'math_node_mvp',
                        name: '算术节点',
                        type: 'math_node',
                        properties: {
                          'operation': '+',
                          'value': 1.0,
                          'extractMethod': 'first',
                          'delimiter': '/',
                        },
                        color: const Color(0xFFD1C4E9),
                      ),
                      Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE7F6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF9575CD), width: 1.2),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '算术 : +1',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF512DA8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('下拉单选节点',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'select_mvp',
                        name: '下拉单选框',
                        type: 'select',
                        properties: {
                          'options': ['选项 1'],
                          'current': '选项 1',
                          'variable': 'var.select',
                        },
                        color: const Color(0xFF7E57C2),
                      ),
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFD0D0D8)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('选项 1', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                            Text('▼', style: TextStyle(fontSize: 8, color: Color(0xFF888896))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('多态状态指示点',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'indicator_mvp',
                        name: '状态指示点',
                        type: 'indicator',
                        properties: {
                          'currentValue': '',
                          'defaultColor': 0xFF9E9E9E,
                          'defaultGlow': false,
                          'dotSize': 14.0,
                          'statusRules': [
                            {
                              'matchType': 'exact',
                              'matchValue': '正常',
                              'color': 0xFF4CAF50,
                              'isGlow': true,
                              'glowRadius': 12.0,
                            },
                            {
                              'matchType': 'exact',
                              'matchValue': '警报',
                              'color': 0xFFEF5350,
                              'isGlow': true,
                              'glowRadius': 14.0,
                            },
                          ],
                        },
                        color: const Color(0xFF4CAF50),
                      ),
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFD0D0D8)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Color(0xFF4CAF50),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('正常 / 警报', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('局部滚动视窗',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'scroll_frame_mvp',
                        name: '局部滚动视窗',
                        type: 'scroll_frame',
                        properties: {
                          'scrollMode': 'vertical',
                          'clipToBounds': true,
                          'showScrollbar': true,
                          'contentWidth': 300.0,
                          'contentHeight': 500.0,
                          'backgroundColor': 0xFFF0F0F5,
                        },
                        color: const Color(0xFF5C6BC0),
                      ),
                      Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8EAF6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF5C6BC0), width: 1.2),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.view_day_outlined, size: 14, color: Color(0xFF3F51B5)),
                            SizedBox(width: 6),
                            Text('📜 视窗 : 竖直滚动', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF3F51B5))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('定时脉冲发生器',
                        style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(
                        id: 'timer_mvp',
                        name: '定时脉冲发生器',
                        type: 'timer',
                        properties: {
                          'interval': 1.0,
                          'autoStart': false,
                          'loop': true,
                          'pulseType': 'increment',
                          'currentVal': 0.0,
                          'isRunning_preview': false,
                        },
                        color: const Color(0xFFFF9100),
                      ),
                      Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFF9100), width: 1.2),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.timer_outlined, size: 13, color: Color(0xFFF57C00)),
                                SizedBox(width: 4),
                                Text('1.0s', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF57C00))),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('#0', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFE65100))),
                                Icon(Icons.play_arrow, size: 14, color: Color(0xFFF57C00)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewDraggableCard(UIModule module, Widget visualPreview) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: visualPreview,
    );

    return LongPressDraggable<DragPayload>(
      data: DragPayload(module: module),
      delay: const Duration(milliseconds: 180),
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.88,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: card,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.38, child: card),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: card),
    );
  }

  // ===== 构造层抽屉 =====
  Widget _buildAtomicConstructionDrawer() {
    final bakeable = _currentElements.where(_isBakeableElement).length;
    final total = _currentElements.length;
    final notBakeable = total - bakeable;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 14, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          setState(() => _showConstructionManager = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_forward_ios,
                                size: 10, color: Color(0xFF00ACC1)),
                            Text(
                              ' 收回',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF00ACC1),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Text(
                      '元素列表',
                      style: TextStyle(
                        color: Color(0xFF111116),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F6F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.04),
                    ),
                  ),
                  child: Text(
                    '可烘焙 $bakeable 层 · 不参与 $notBakeable 层',
                    style: TextStyle(
                      color: notBakeable > 0
                          ? const Color(0xFFFF8F00)
                          : const Color(0xFF00A86B),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Text(
                  '可将视觉层烘焙为新的面原子；文本/数据/交互层暂不参与烘焙。',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF888896),
                    height: 1.25,
                  ),
                ),
              ),
              const Divider(color: Colors.black12),
              Expanded(
                child: _currentElements.isEmpty
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(18.0),
                    child: Text(
                      '还没有构造层。\n从左侧拖入面、数据条、文本等原材料。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF888896),
                        height: 1.35,
                      ),
                    ),
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  itemCount: _currentElements.length,
                  itemBuilder: (context, index) {
                    final el = _currentElements[index];
                    final selected = _selectedTransformationId == el.id;
                    final bake = _isBakeableElement(el);
                    final name =
                        el.module?.name ?? el.composite?.name ?? '未命名层';
                    return Card(
                      color: selected
                          ? const Color(0xFF111116)
                          : const Color(0xFFF6F6F9),
                      elevation: selected ? 3 : 0,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFF00E5FF)
                              : Colors.black.withValues(alpha: 0.04),
                          width: selected ? 1.4 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(
                                () => _selectedTransformationId = el.id),
                        onLongPress: () =>
                            _showTailoredPrecisionEditorDialog(el),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 7),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: bake
                                          ? const Color(0xFF00C853)
                                          : const Color(0xFFFF8F00),
                                      borderRadius:
                                      BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      bake ? '烘焙' : '跳过',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : const Color(0xFF111116),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_elementTypeLabel(el)} · L${el.layerIndex} · ${el.size.width.toStringAsFixed(0)}×${el.size.height.toStringAsFixed(0)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white70
                                      : const Color(0xFF777783),
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _buildLayerMiniButton(
                                    Icons.keyboard_arrow_up_rounded,
                                        () => _moveAtomicConstructionLayer(
                                        el.id, -1),
                                    selected,
                                  ),
                                  _buildLayerMiniButton(
                                    Icons.keyboard_arrow_down_rounded,
                                        () => _moveAtomicConstructionLayer(
                                        el.id, 1),
                                    selected,
                                  ),
                                  _buildLayerMiniButton(
                                    Icons.tune_rounded,
                                        () => _showTailoredPrecisionEditorDialog(
                                        el),
                                    selected,
                                  ),
                                  _buildLayerMiniButton(
                                    Icons.delete_outline_rounded,
                                        () => _deleteElement(el.id),
                                    selected,
                                    danger: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayerMiniButton(
      IconData icon,
      VoidCallback onTap,
      bool selected, {
        bool danger = false,
      }) {
    final color = danger
        ? const Color(0xFFFF4081)
        : (selected ? Colors.white : const Color(0xFF555562));
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  // ===== 右侧资产库抽屉 =====
  Widget _buildRightCompletedAssetsDrawer() {
    final modules = _assetService.getAllModules();
    final composites = _assetService.getAllComposites();
    final isEmpty = modules.isEmpty && composites.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 14, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showRightDrawer = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_forward_ios,
                                size: 10, color: Color(0xFF00ACC1)),
                            Text(
                              ' 收回',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF00ACC1),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Text(
                      '完成资产库',
                      style: TextStyle(
                        color: Color(0xFF111116),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.black12),
              Expanded(
                child: isEmpty
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(18.0),
                    child: Text(
                      '还没有保存的资产。\n在工作台拖入积木后点「保存」即可入库。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF888896),
                        height: 1.35,
                      ),
                    ),
                  ),
                )
                    : ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  children: [
                    ...modules.map(_buildAssetLibraryModuleCard),
                    if (composites.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 10, 4, 2),
                        child: Text(
                          '复合组件',
                          style: TextStyle(
                            color: Color(0xFF888896),
                            fontSize: 10,
                          ),
                        ),
                      ),
                      ...composites.map(_buildAssetLibraryCompositeCard),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssetLibraryModuleCard(UIModule module) {
    final card = Card(
      color: const Color(0xFFF6F6F9),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.03)),
      ),
      child: ListTile(
        title: Text(
          module.name,
          style: const TextStyle(
            color: Color(0xFF111116),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _elementTypeLabel(
            UIElement(id: 'preview_${module.id}', isComposite: false, module: module),
          ),
          style: const TextStyle(color: Color(0xFF888896), fontSize: 9),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.drag_indicator_rounded,
              size: 16,
              color: Color(0xFF00E676),
            ),
            GestureDetector(
              onTap: () => _confirmDeleteModule(module),
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: Color(0xFFFF4081),
                ),
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );

    return LongPressDraggable<DragPayload>(
      data: DragPayload(module: module),
      delay: const Duration(milliseconds: 180),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 150, child: Opacity(opacity: 0.9, child: card)),
      ),
      childWhenDragging: Opacity(opacity: 0.38, child: card),
      child: card,
    );
  }

  Widget _buildAssetLibraryCompositeCard(UIComposite composite) {
    final card = Card(
      color: const Color(0xFFF3E5F5),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        title: Text(
          composite.name,
          style: const TextStyle(
            color: Color(0xFF111116),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '复合组件 · ${composite.children.length} 个子元素',
          style: const TextStyle(color: Color(0xFF888896), fontSize: 9),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.drag_indicator_rounded,
              size: 16,
              color: Color(0xFF651FFF),
            ),
            GestureDetector(
              onTap: () => _confirmDeleteComposite(composite),
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: Color(0xFFFF4081),
                ),
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );

    return LongPressDraggable<DragPayload>(
      data: DragPayload(composite: composite),
      delay: const Duration(milliseconds: 180),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 150, child: Opacity(opacity: 0.9, child: card)),
      ),
      childWhenDragging: Opacity(opacity: 0.38, child: card),
      child: card,
    );
  }
}
