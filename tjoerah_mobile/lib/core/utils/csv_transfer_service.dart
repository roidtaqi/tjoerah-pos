import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CsvPickedFile {
  const CsvPickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class CsvTransferService {
  const CsvTransferService._();

  static Future<CsvPickedFile?> pick() async {
    const typeGroup = XTypeGroup(
      label: 'CSV',
      extensions: ['csv'],
      mimeTypes: ['text/csv', 'text/plain'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return null;

    return CsvPickedFile(name: file.name, bytes: await file.readAsBytes());
  }

  static Future<void> share({
    required Uint8List bytes,
    required String filename,
    required String subject,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: subject,
      ),
    );
  }
}
