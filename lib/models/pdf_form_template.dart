/// Reusable configuration for requirement, MOA, evaluation, and other SIP PDFs.
/// Coordinates use fractions of the page, measured from its top-left corner.
class PdfTemplateField {
  const PdfTemplateField({
    required this.name,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.options = const [],
    this.maxLength,
    this.multiline = false,
    this.page,
    this.x = 0,
    this.y = 0,
    this.width = .35,
    this.height = .035,
  });

  final String name;
  final String label;
  final String type;
  final bool required;
  final List<String> options;
  final int? maxLength;
  final bool multiline;
  final int? page;
  final double x, y, width, height;
  bool get isPlaced => page != null;

  factory PdfTemplateField.fromMap(Map<String, dynamic> map) =>
      PdfTemplateField(
        name: map['name'] as String,
        label: map['label'] as String? ?? map['name'] as String,
        type: map['type'] as String? ?? 'text',
        required: map['required'] == true,
        options: List<String>.from(map['options'] as List? ?? const []),
        maxLength: (map['maxLength'] as num?)?.toInt(),
        multiline: map['multiline'] == true,
        page: (map['page'] as num?)?.toInt(),
        x: (map['x'] as num?)?.toDouble() ?? 0,
        y: (map['y'] as num?)?.toDouble() ?? 0,
        width: (map['width'] as num?)?.toDouble() ?? .35,
        height: (map['height'] as num?)?.toDouble() ?? .035,
      );

  Map<String, dynamic> toMap() => {
    'name': name,
    'label': label,
    'type': type,
    'required': required,
    'options': options,
    'maxLength': maxLength,
    'multiline': multiline,
    if (page != null) 'page': page,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

class PdfFormTemplate {
  const PdfFormTemplate({
    required this.officialPath,
    required this.officialName,
    this.samplePath,
    this.sampleName,
    this.fields = const [],
  });

  final String officialPath;
  final String officialName;
  final String? samplePath;
  final String? sampleName;
  final List<PdfTemplateField> fields;

  factory PdfFormTemplate.fromMap(Map<String, dynamic> map) => PdfFormTemplate(
    officialPath: map['officialPath'] as String,
    officialName: map['officialName'] as String,
    samplePath: map['samplePath'] as String?,
    sampleName: map['sampleName'] as String?,
    fields: (map['fields'] as List? ?? const [])
        .map(
          (item) =>
              PdfTemplateField.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );

  Map<String, dynamic> toMap() => {
    'officialPath': officialPath,
    'officialName': officialName,
    'samplePath': samplePath,
    'sampleName': sampleName,
    'fields': fields.map((field) => field.toMap()).toList(),
  };
}
