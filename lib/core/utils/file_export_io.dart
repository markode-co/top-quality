import 'dart:io';

Future<String> saveFilePlatform({
  required String filename,
  required List<int> bytes,
  required String mimeType,
}) async {
  final sanitized = filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  final target = File('${Directory.systemTemp.path}/$sanitized');
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}
