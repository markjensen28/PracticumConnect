import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import '../models/pdf_form_template.dart';

@JS('sipPdfTemplates.inspect')
external JSPromise<JSString> _inspect(JSUint8Array bytes);
@JS('sipPdfTemplates.locate')
external JSPromise<JSString> _locate(JSUint8Array bytes);
@JS('sipPdfTemplates.fill')
external JSPromise<JSUint8Array> _fill(
  JSUint8Array bytes,
  JSString fields,
  JSString values,
  JSBoolean templateOnly,
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

  static Future<Map<String, List<PdfFieldLocation>>> locate(
    Uint8List bytes,
  ) async {
    final json = (await _locate(bytes.toJS).toDart).toDart;
    final fields = jsonDecode(json) as Map<String, dynamic>;
    return {
      for (final entry in fields.entries)
        entry.key: [
          for (final position in entry.value as List)
            (
              page: position['page'] as int,
              x: (position['x'] as num).toDouble(),
              y: (position['y'] as num).toDouble(),
              width: (position['width'] as num).toDouble(),
              height: (position['height'] as num).toDouble(),
            ),
        ],
    };
  }

  static Future<Uint8List> fill(
    Uint8List bytes,
    List<PdfTemplateField> fields,
    Map<String, dynamic> values, {
    bool templateOnly = false,
  }) async {
    try {
      return (await _fill(
        bytes.toJS,
        jsonEncode(fields.map((field) => field.toMap()).toList()).toJS,
        jsonEncode(values).toJS,
        templateOnly.toJS,
      ).toDart).toDart;
    } catch (error) {
      throw StateError('Unable to fill the PDF: $error');
    }
  }
}
