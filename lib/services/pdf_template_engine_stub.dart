import 'dart:typed_data';
import '../models/pdf_form_template.dart';

class PdfTemplateEngine {
  static const available = false;
  static Future<List<PdfTemplateField>> inspect(Uint8List bytes) async =>
      throw UnsupportedError('Open the web app to configure PDF form fields.');
  static Future<Uint8List> fill(
    Uint8List bytes,
    List<PdfTemplateField> fields,
    Map<String, dynamic> values,
  ) async =>
      throw UnsupportedError('Open the web app to fill this PDF template.');
}
