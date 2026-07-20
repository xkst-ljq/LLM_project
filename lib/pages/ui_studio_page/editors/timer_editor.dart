import 'package:flutter/material.dart';

/// 定时脉冲发生器规格编辑器
/// 对应 UI 模块类型：UIModuleType.timer
class TimerEditor extends StatefulWidget {
  final Map<String, dynamic> initialProperties;
  final String moduleName;
  final int layerId;
  final Offset initialPosition;
  final VoidCallback onDelete;
  final Function(Map<String, dynamic>) onSave;

  const TimerEditor({
    super.key,
    required this.initialProperties,
    required this.moduleName,
    required this.layerId,
    required this.initialPosition,
    required this.onDelete,
    required this.onSave,
  });

  @override
  State<TimerEditor> createState() => _TimerEditorState();
}

class _TimerEditorState extends State<TimerEditor> {
  late TextEditingController _nameController;
  late TextEditingController _intervalController;
  late TextEditingController _initialDelayController;
  late TextEditingController _maxTicksController;
  late TextEditingController _stepController;
  late TextEditingController _varController;
  late String _pulseType;
  late bool _loop;
  late double _currentVal;

  @override
  void initState() {
    super.initState();
    final props = widget.initialProperties;

    _nameController = TextEditingController(text: widget.moduleName);
    _intervalController = TextEditingController(
      text: ((props['interval'] as num?)?.toDouble() ?? 1.0).toStringAsFixed(1),
    );
    _initialDelayController = TextEditingController(
      text: ((props['initialDelay'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1),
    );
    _maxTicksController = TextEditingController(
      text: ((props['maxTicks'] as num?)?.toInt() ?? 0).toString(),
    );
    _stepController = TextEditingController(
      text: ((props['stepValue'] as num?)?.toDouble() ?? 1.0).toStringAsFixed(1),
    );
    _varController = TextEditingController(
      text: props['sessionVar']?.toString() ?? 'var.timer',
    );

    _pulseType = props['pulseType']?.toString() ?? 'increment';
    _loop = props['loop'] != false;
    _currentVal = (props['currentVal'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _intervalController.dispose();
    _initialDelayController.dispose();
    _maxTicksController.dispose();
    _stepController.dispose();
    _varController.dispose();
    super.dispose();
  }


  void _save() {
    final double intervalVal = (double.tryParse(_intervalController.text.trim()) ?? 1.0).clamp(0.1, 3600.0);
    final double stepVal = double.tryParse(_stepController.text.trim()) ?? 1.0;

    final newProps = {
      'type': 'timer',
      'name': _nameController.text.trim(),
      'interval': intervalVal,
      'initialDelay': (double.tryParse(_initialDelayController.text.trim()) ?? 0.0).clamp(0.0, 3600.0),
      'maxTicks': (int.tryParse(_maxTicksController.text.trim()) ?? 0).clamp(0, 100000),
      'stepValue': stepVal,
      'pulseType': _pulseType,
      'loop': _loop,
      'currentVal': _currentVal,
      'tickCount': (widget.initialProperties['tickCount'] as num?)?.toInt() ?? 0,
      'isRunning': false,
      'sessionVar': _varController.text.trim(),
    };

    widget.onSave(newProps);
    Navigator.of(context).pop();
  }

  void _handleDelete() {
    widget.onDelete();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏（R5防溢出：使用 Expanded 与 ellipsis）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, color: Color(0xFFFF6D00), size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '定时脉冲发生器配置 (Timer)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.moduleName,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),


            // 弹性内容区（R5防溢出）
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHostSection(),
                    const SizedBox(height: 16),
                    _buildPulseTypeSection(),
                    const SizedBox(height: 16),
                    _buildIntervalSection(),
                    const SizedBox(height: 16),
                    _buildRuntimeSection(),
                  ],
                ),
              ),
            ),

            // 底槽按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _handleDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                    label: const Text('删除发生器', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6D00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('保存配置', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('基本信息与字典绑定', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '模块名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: TextField(
                controller: _varController,
                decoration: const InputDecoration(
                  labelText: '绑定会话字典变量',
                  hintText: '如: var.timer',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '物理坐标(${widget.initialPosition.dx.toInt()}, ${widget.initialPosition.dy.toInt()}) · 运行时对读者隐形，纯后台发送信号',
          style: TextStyle(color: Colors.grey[600], fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildPulseTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('脉冲信号输出方案 (决定每次跳动发出的数据)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildTypeChip('increment', '⚡ 递增计数 (+步长)', '累加次数或驱动进度条上升'),
            _buildTypeChip('toggle', '⚡ 0/1 翻转 (开关)', '真假横跳，驱动指示灯闪烁警报'),
            _buildTypeChip('timestamp', '⚡ 运行秒戳 (时间)', '输出发生器已启动的总运行秒长'),
            _buildTypeChip('countdown', '⏳ 倒计时 (-步长)', '每次递减，归零时终止倒数任务'),
          ],
        ),
        if (_pulseType == 'increment' || _pulseType == 'countdown') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('每次脉冲增减步长:', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
              const SizedBox(width: 10),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _stepController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _pulseType == 'increment' ? '注：每次脉冲跳动 +${_stepController.text}' : '注：每次脉冲跳动 -${_stepController.text}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTypeChip(String type, String title, String subtitle) {
    final bool active = _pulseType == type;
    return GestureDetector(
      onTap: () => setState(() => _pulseType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFF3E0) : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? const Color(0xFFFF6D00) : Colors.grey.shade300, width: active ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.w600, color: active ? const Color(0xFFE65100) : const Color(0xFF111116))),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildIntervalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('触发周期间隔 (决定多久跳动发出一次信号)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('周期间隔 (秒):', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
            const SizedBox(width: 10),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _intervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _initialDelayController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '首次延迟（秒）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _maxTicksController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '最大 Tick 数（0 = 无限）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [0.5, 1.0, 3.0, 5.0, 10.0, 30.0, 60.0].map((val) {
            return ActionChip(
              label: Text('${val}s', style: const TextStyle(fontSize: 10)),
              onPressed: () {
                setState(() {
                  _intervalController.text = val.toStringAsFixed(1);
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRuntimeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('运行控制', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        const Text(
          'Timer 会根据连接拓扑自动决定运行方式：系统条件控制优先；存在 Button toggle 时等待手动触发；没有控制通路时进入预览/运行时自动启动。',
          style: TextStyle(fontSize: 11, color: Color(0xFF555562), height: 1.35),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('倒计时归零后循环:', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
            const Spacer(),
            Switch(
              value: _loop,
              onChanged: (v) => setState(() => _loop = v),
              activeThumbColor: const Color(0xFFFF6D00),
            ),
          ],
        ),
      ],
    );
  }
}
