import 'package:file_picker/file_picker.dart';

import '../domain/import/transaction_import_models.dart';

class TransactionImportFileService {
  Future<SelectedCsvFile?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.bytes == null) {
      throw const TransactionImportException(
        'Could not read the selected CSV.',
      );
    }
    return SelectedCsvFile(name: file.name, bytes: file.bytes!);
  }
}
