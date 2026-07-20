/// Stable Select option model.
///
/// Legacy string options are migrated in memory as label=value.
class SelectOption {
  final String label;
  final String value;

  const SelectOption({required this.label, required this.value});

  factory SelectOption.fromDynamic(dynamic raw) {
    if (raw is Map) {
      final label = raw['label']?.toString() ?? raw['value']?.toString() ?? '';
      final value = raw['value']?.toString() ?? label;
      return SelectOption(label: label, value: value);
    }
    final text = raw?.toString() ?? '';
    return SelectOption(label: text, value: text);
  }

  Map<String, dynamic> toJson() => {'label': label, 'value': value};

  static List<SelectOption> parseList(dynamic raw) {
    final list = raw is List ? raw : const [];
    final options = list
        .map(SelectOption.fromDynamic)
        .where((option) => option.label.trim().isNotEmpty && option.value.trim().isNotEmpty)
        .toList();
    return options.isEmpty
        ? const [SelectOption(label: '选项 1', value: 'option_1')]
        : options;
  }
}
