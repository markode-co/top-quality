import 'file_export_io.dart'
    if (dart.library.html) 'file_export_web.dart';

Future<String> saveFile({
  required String filename,
  required List<int> bytes,
  required String mimeType,
}) => saveFilePlatform(
      filename: filename,
      bytes: bytes,
      mimeType: mimeType,
    );
