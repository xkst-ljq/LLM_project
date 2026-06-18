import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 从 PNG 角色卡中读取内嵌的角色元数据。
///
/// 兼容 SillyTavern / Character Card V2 / V3 常见做法：
///   - 角色 JSON 经过 base64 编码后，存放在 PNG 的文本块里；
///   - 关键字通常是 `chara`（V2）或 `ccv3`（V3）。
///
/// 支持的 PNG 文本块类型：tEXt / zTXt / iTXt。
///
/// 纯 Dart，不依赖第三方包，PC 与移动端通用。
class PngCharaReader {
  static const List<int> _signature = [137, 80, 78, 71, 13, 10, 26, 10];

  /// 判断字节是否为 PNG。
  static bool isPng(List<int> bytes) {
    if (bytes.length < 8) return false;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != _signature[i]) return false;
    }
    return true;
  }

  /// 读取 PNG 中所有文本块，返回 keyword -> 原始文本。
  ///
  /// 注意：返回的是文本块里的原始字符串（通常是 base64），未做 base64 解码。
  static Map<String, String> readTextChunks(List<int> input) {
    final bytes = input is Uint8List ? input : Uint8List.fromList(input);
    final result = <String, String>{};
    if (!isPng(bytes)) return result;

    final data = ByteData.sublistView(bytes);
    var offset = 8; // 跳过签名

    while (offset + 8 <= bytes.length) {
      final length = data.getUint32(offset, Endian.big);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      final chunkStart = offset + 8;
      final chunkEnd = chunkStart + length;
      if (chunkEnd > bytes.length) break; // 损坏

      final chunk = bytes.sublist(chunkStart, chunkEnd);

      switch (type) {
        case 'tEXt':
          _parseTextChunk(chunk, result);
          break;
        case 'zTXt':
          _parseZTextChunk(chunk, result);
          break;
        case 'iTXt':
          _parseITextChunk(chunk, result);
          break;
        case 'IEND':
          return result;
      }

      offset = chunkEnd + 4; // 跳过 4 字节 CRC
    }
    return result;
  }

  /// 提取角色 JSON（已解码）。找不到返回 null。
  ///
  /// 优先级：ccv3 > chara。会处理 base64，并兼容 latin-1 与 utf-8。
  static Map<String, dynamic>? extractCharacterJson(List<int> bytes) {
    final chunks = readTextChunks(bytes);
    for (final key in const ['ccv3', 'chara']) {
      final raw = chunks[key];
      if (raw == null || raw.trim().isEmpty) continue;
      final decoded = _decodeMaybeBase64Json(raw);
      if (decoded != null) return decoded;
    }
    // 兜底：任意文本块里若能解析出含 name/data 的 JSON 也接受。
    for (final raw in chunks.values) {
      final decoded = _decodeMaybeBase64Json(raw);
      if (decoded != null &&
          (decoded.containsKey('name') ||
              decoded.containsKey('data') ||
              decoded.containsKey('spec'))) {
        return decoded;
      }
    }
    return null;
  }

  static void _parseTextChunk(List<int> chunk, Map<String, String> out) {
    final sep = chunk.indexOf(0);
    if (sep < 0) return;
    final keyword = _latin1(chunk.sublist(0, sep));
    final value = _latin1(chunk.sublist(sep + 1));
    out[keyword] = value;
  }

  static void _parseZTextChunk(List<int> chunk, Map<String, String> out) {
    final sep = chunk.indexOf(0);
    if (sep < 0) return;
    final keyword = _latin1(chunk.sublist(0, sep));
    // chunk[sep+1] 是压缩方法（0=deflate）。
    final compressed = chunk.sublist(sep + 2);
    final inflated = _inflate(compressed);
    if (inflated != null) {
      out[keyword] = _latin1(inflated);
    }
  }

  static void _parseITextChunk(List<int> chunk, Map<String, String> out) {
    // 结构：keyword \0 compFlag compMethod langTag \0 transKeyword \0 text
    var p = chunk.indexOf(0);
    if (p < 0) return;
    final keyword = _latin1(chunk.sublist(0, p));
    if (p + 2 >= chunk.length) return;
    final compFlag = chunk[p + 1];
    // p+2 = compression method
    var q = p + 3;
    final langEnd = chunk.indexOf(0, q);
    if (langEnd < 0) return;
    final transEnd = chunk.indexOf(0, langEnd + 1);
    if (transEnd < 0) return;
    final textBytes = chunk.sublist(transEnd + 1);
    if (compFlag == 1) {
      final inflated = _inflate(textBytes);
      out[keyword] = inflated != null
          ? utf8.decode(inflated, allowMalformed: true)
          : _latin1(textBytes);
    } else {
      out[keyword] = utf8.decode(textBytes, allowMalformed: true);
    }
  }

  /// 用 archive 的纯 Dart zlib 解压，避免依赖 dart:io（兼容 web）。
  static List<int>? _inflate(List<int> data) {
    try {
      return ZLibDecoder().decodeBytes(data);
    } catch (_) {
      return null;
    }
  }

  /// 尝试把字符串当作 base64(JSON) 解析；失败则当作纯 JSON。
  static Map<String, dynamic>? _decodeMaybeBase64Json(String raw) {
    final trimmed = raw.trim();
    // 1) 直接是 JSON
    final direct = _tryJson(trimmed);
    if (direct != null) return direct;

    // 2) base64 -> utf-8 JSON
    try {
      final normalized = trimmed.replaceAll(RegExp(r'\s'), '');
      final bytes = base64.decode(base64.normalize(normalized));
      final text = utf8.decode(bytes, allowMalformed: true);
      final parsed = _tryJson(text);
      if (parsed != null) return parsed;
    } catch (_) {
      // ignore
    }
    return null;
  }

  static Map<String, dynamic>? _tryJson(String text) {
    try {
      final v = jsonDecode(text);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  static String _latin1(List<int> bytes) =>
      String.fromCharCodes(bytes); // latin-1 等价：逐字节
}
