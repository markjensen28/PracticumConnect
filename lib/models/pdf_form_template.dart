const maxPdfTemplateFields = 400;

enum SchoolTemplateKind { moa, evaluation }

typedef DefaultPdfTemplate = ({String path, String name});

enum PdfFieldEntry {
  student,
  prefilled,
  locked,
  hidden;

  bool get usesPreset => this == prefilled || this == locked;
  bool get studentEditable => this == student || this == prefilled;

  static PdfFieldEntry fromConfig(Object? value) =>
      values.where((entry) => entry.name == value).firstOrNull ?? student;
}

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
    this.entry = PdfFieldEntry.student,
    this.presetValue,
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
  final PdfFieldEntry entry;
  final Object? presetValue;
  final int? page;
  final double x, y, width, height;
  bool get isPlaced => page != null;
  String get presetText => presetValue is String ? presetValue as String : '';

  String? get presetError {
    if (!entry.usesPreset) return null;
    if (type == 'checkbox') {
      return presetValue == null || presetValue is bool
          ? null
          : 'Choose a checkbox value.';
    }
    if (type == 'choice') {
      return presetText.isEmpty || !options.contains(presetText)
          ? 'Select a prefilled option.'
          : null;
    }
    final limit = maxLength ?? 4000;
    if (presetText.trim().isEmpty) return 'Enter a prefilled value.';
    if (presetText.length > limit) return 'Use at most $limit characters.';
    return null;
  }

  PdfTemplateField copyWith({
    String? label,
    bool? required,
    bool? multiline,
    PdfFieldEntry? entry,
    Object? presetValue,
    double? width,
    double? height,
  }) => PdfTemplateField(
    name: name,
    label: label ?? this.label,
    type: type,
    required: required ?? this.required,
    options: options,
    maxLength: maxLength,
    multiline: multiline ?? this.multiline,
    entry: entry ?? this.entry,
    presetValue: presetValue ?? this.presetValue,
    page: page,
    x: x,
    y: y,
    width: width ?? this.width,
    height: height ?? this.height,
  );

  factory PdfTemplateField.fromMap(Map<String, dynamic> map) =>
      PdfTemplateField(
        name: map['name'] as String,
        label: map['label'] as String? ?? map['name'] as String,
        type: map['type'] as String? ?? 'text',
        required: map['required'] == true,
        options: List<String>.from(map['options'] as List? ?? const []),
        maxLength: (map['maxLength'] as num?)?.toInt(),
        multiline: map['multiline'] == true,
        entry: PdfFieldEntry.fromConfig(map['entry']),
        presetValue: map['presetValue'],
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
    if (entry != PdfFieldEntry.student) 'entry': entry.name,
    if (entry.usesPreset && presetValue != null) 'presetValue': presetValue,
    if (page != null) 'page': page,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

/// Preview-only coordinates for a visible field on a displayed PDF page.
typedef PdfFieldLocation = ({
  int page,
  double x,
  double y,
  double width,
  double height,
});

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

  bool get hasStudentFields =>
      fields.any((field) => field.entry.studentEditable);

  bool get hasCustomEntries =>
      fields.any((field) => field.entry != PdfFieldEntry.student);

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
