import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';

class PickResult {
  const PickResult(this.files, this.skipped);
  final List<InputFile> files;
  final List<String> skipped; // unsupported file names
}

class FileService {
  /// Opens the system picker. We use FileType.any and filter ourselves,
  /// because some Android phones grey out .epub with custom extension filters.
  static Future<PickResult> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: true,
    );
    if (result == null) return const PickResult([], []);

    final files = <InputFile>[];
    final skipped = <String>[];
    for (final f in result.files) {
      final kind = inputKindOf(f.name);
      var bytes = f.bytes;
      if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
      if (kind == null || bytes == null) {
        skipped.add(f.name);
      } else {
        files.add(InputFile(name: f.name, bytes: bytes, kind: kind));
      }
    }
    return PickResult(files, skipped);
  }

  /// Shows Android's "Save as" screen so the user chooses the folder.
  /// Returns true if saved.
  static Future<bool> save(ConvertedFile file) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save ${file.name}',
      fileName: file.name,
      bytes: file.bytes,
    );
    return path != null;
  }

  /// Shares one or more results (WhatsApp, Drive, Telegram, ...).
  static Future<void> share(List<ConvertedFile> files) async {
    final dir = await getTemporaryDirectory();
    final xfiles = <XFile>[];
    for (final f in files) {
      final out = File(p.join(dir.path, f.name));
      await out.writeAsBytes(f.bytes, flush: true);
      xfiles.add(XFile(out.path, mimeType: f.format.mimeType, name: f.name));
    }
    await SharePlus.instance.share(ShareParams(files: xfiles));
  }
}
