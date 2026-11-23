import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
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

  /// Saves every file with ONE folder choice. If Android refuses direct
  /// writes to that folder (common on Android 11+), falls back to saving all
  /// files as a single ZIP through the normal "Save as" screen.
  /// Returns a message to show the user, or null if they cancelled.
  static Future<String?> saveAll(List<ConvertedFile> files) async {
    final dir = await FilePicker.platform
        .getDirectoryPath(dialogTitle: 'Choose a folder for all files');
    if (dir == null) return null;

    try {
      for (final f in files) {
        await File(_freePath(dir, f.name)).writeAsBytes(f.bytes, flush: true);
      }
      return 'Saved ${files.length} files to the chosen folder.';
    } on FileSystemException {
      // Folder not writable: fall back to one ZIP.
      final zip = await Isolate.run(() => _zip(files));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save all files as a ZIP',
        fileName: 'converted_files.zip',
        bytes: zip,
      );
      return path == null
          ? null
          : 'That folder is protected, so all ${files.length} files were saved as one ZIP.';
    }
  }

  static String _freePath(String dir, String name) {
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var path = p.join(dir, name);
    for (var i = 2; File(path).existsSync(); i++) {
      path = p.join(dir, '$base ($i)$ext');
    }
    return path;
  }

  static Uint8List _zip(List<ConvertedFile> files) {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(ArchiveFile.bytes(f.name, f.bytes));
    }
    return ZipEncoder().encodeBytes(archive);
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
