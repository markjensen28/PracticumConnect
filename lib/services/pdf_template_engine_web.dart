import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import '../models/pdf_form_template.dart';

@JS('sipPdfTemplates.inspect')
external JSPromise<JSString> _inspect(JSUint8Array bytes);
@JS('sipPdfTemplates.fill')
external JSPromise<JSUint8Array> _fill(
  JSUint8Array bytes,
  JSString fields,
  JSString values,
);

class PdfTemplateEngine {
  static const available = true;

  static Future<List<PdfTemplateField>> inspect(Uint8List bytes) async {
    try {
      final json = (await _inspect(bytes.toJS).toDart).toDart;
      return (jsonDecode(json) as List)
          .map(
            (item) => PdfTemplateField.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (error) {
      throw StateError('Cannot use this official template: $error');
    }
  }

  static Future<Uint8List> fill(
    Uint8List bytes,
    List<PdfTemplateField> fields,
    Map<String, dynamic> values,
  ) async {
    try {
      return (await _fill(
        bytes.toJS,
        jsonEncode(fields.map((field) => field.toMap()).toList()).toJS,
        jsonEncode(values).toJS,
      ).toDart).toDart;
    } catch (error) {
      throw StateError('Unable to fill the PDF: $error');
    }
  }
}
