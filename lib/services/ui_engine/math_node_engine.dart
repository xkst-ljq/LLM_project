/// Pure Dart evaluator for UI Studio Math Node V1.
class MathNodeEngine {
  static dynamic evaluate({
    required String operation,
    required List<num> operands,
    num fallbackValue = 0,
  }) {
    if (operation == 'set') {
      return operands.isEmpty ? fallbackValue.toDouble() : operands.first.toDouble();
    }
    if (operands.length < 2) return fallbackValue.toDouble();

    final values = operands.map((value) => value.toDouble()).toList();
    switch (operation) {
      case '+':
        return values.reduce((left, right) => left + right);
      case '-':
        return values.reduce((left, right) => left - right);
      case '*':
        return values.reduce((left, right) => left * right);
      case '/':
        if (values.skip(1).any((value) => value == 0)) {
          return fallbackValue.toDouble();
        }
        return values.reduce((left, right) => left / right);
      case '>':
        return values[0] > values[1];
      case '<':
        return values[0] < values[1];
      case '>=':
        return values[0] >= values[1];
      case '<=':
        return values[0] <= values[1];
      case '==':
        return (values[0] - values[1]).abs() < 1e-9;
      default:
        return fallbackValue.toDouble();
    }
  }

  static bool isValidOperandCount(String operation, int count) {
    if (operation == 'set') return count >= 1;
    if (['>', '<', '>=', '<=', '=='].contains(operation)) {
      return count == 2;
    }
    return count >= 2;
  }

  static double toNumber(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    if (value is bool) return value ? 1 : 0;
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
