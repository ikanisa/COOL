import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

import 'momo_statement_export_service.dart';

class StatementDownloadResult {
  const StatementDownloadResult({
    required this.fileName,
    required this.savedPath,
    required this.usedSaveAs,
  });

  final String fileName;
  final String savedPath;
  final bool usedSaveAs;
}

abstract class StatementFileSaver {
  Future<String> saveFile({
    required String name,
    required Uint8List bytes,
    required String fileExtension,
    required MimeType mimeType,
  });

  Future<String?> saveAs({
    required String name,
    required Uint8List bytes,
    required String fileExtension,
    required MimeType mimeType,
  });
}

class FileSaverStatementFileSaver implements StatementFileSaver {
  @override
  Future<String> saveFile({
    required String name,
    required Uint8List bytes,
    required String fileExtension,
    required MimeType mimeType,
  }) {
    return FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: fileExtension,
      mimeType: mimeType,
    );
  }

  @override
  Future<String?> saveAs({
    required String name,
    required Uint8List bytes,
    required String fileExtension,
    required MimeType mimeType,
  }) {
    return FileSaver.instance.saveAs(
      name: name,
      bytes: bytes,
      fileExtension: fileExtension,
      mimeType: mimeType,
    );
  }
}

class MomoStatementDownloadService {
  MomoStatementDownloadService({StatementFileSaver? fileSaver})
    : _fileSaver = fileSaver ?? FileSaverStatementFileSaver();

  final StatementFileSaver _fileSaver;

  Future<StatementDownloadResult> saveExport(
    StatementExportFile exportFile,
  ) async {
    final extension = _fileExtension(exportFile.fileName);
    final stem = _fileStem(exportFile.fileName);
    final mimeType = _mimeTypeForExtension(extension);

    if (_supportsSaveAs) {
      final path = await _fileSaver.saveAs(
        name: stem,
        bytes: exportFile.bytes,
        fileExtension: extension,
        mimeType: mimeType,
      );
      if (path != null && path.trim().isNotEmpty) {
        return StatementDownloadResult(
          fileName: exportFile.fileName,
          savedPath: path,
          usedSaveAs: true,
        );
      }
    }

    final path = await _fileSaver.saveFile(
      name: stem,
      bytes: exportFile.bytes,
      fileExtension: extension,
      mimeType: mimeType,
    );
    return StatementDownloadResult(
      fileName: exportFile.fileName,
      savedPath: path,
      usedSaveAs: false,
    );
  }

  bool get _supportsSaveAs {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }
}

String _fileExtension(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
    return 'bin';
  }
  return fileName.substring(dotIndex + 1);
}

String _fileStem(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex <= 0) {
    return fileName;
  }
  return fileName.substring(0, dotIndex);
}

MimeType _mimeTypeForExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'pdf':
      return MimeType.pdf;
    case 'xlsx':
      return MimeType.microsoftExcel;
    case 'csv':
      return MimeType.csv;
    default:
      return MimeType.other;
  }
}
