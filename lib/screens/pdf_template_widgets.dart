import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../models/pdf_form_template.dart';
import '../services/pdf_template_engine.dart';
import '../services/practicum_repository.dart';

/// Keep this controller with the host form, and persist only when that form saves.
class PdfTemplateEditorController extends ChangeNotifier {
  PdfTemplateEditorController({PdfFormTemplate? template})
    : saved = template,
      fields = List.of(template?.fields ?? const <PdfTemplateField>[]);
  PdfFormTemplate? saved;
  PlatformFile? officialFile, sampleFile;
  List<PdfTemplateField> fields;
  bool removeSample = false;
  bool busy = false;

  Future<PdfFormTemplate?> persist(
    PracticumRepository repository,
    AppUser actor,
  ) async {
    if (busy) {
      throw StateError(
        'Wait for the PDF to finish preparing, then save again.',
      );
    }
    if (officialFile == null &&
        sampleFile == null &&
        !removeSample &&
        saved == null) {
      return null;
    }
    saved = await repository.savePdfFormTemplate(
      actor: actor,
      existing: saved,
      officialFile: officialFile,
      sampleFile: sampleFile,
      removeSample: removeSample,
      fields: fields,
    );
    officialFile = sampleFile = null;
    removeSample = false;
    return saved;
  }
}

/// Coordinator-side upload and mapping UI, independent of a particular SIP module.
class PdfTemplateEditor extends StatefulWidget {
  const PdfTemplateEditor({
    super.key,
    required this.controller,
    required this.repository,
  });
  final PdfTemplateEditorController controller;
  final PracticumRepository repository;
  @override
  State<PdfTemplateEditor> createState() => _PdfTemplateEditorState();
}

class _PdfTemplateEditorState extends State<PdfTemplateEditor> {
  bool _busy = false;
  String? _error;
  PdfTemplateEditorController get draft => widget.controller;

  Future<Uint8List> _bytes(bool sample) async {
    final file = sample ? draft.sampleFile : draft.officialFile;
    if (file != null) return file.readAsBytes();
    final path = sample ? draft.saved?.samplePath : draft.saved?.officialPath;
    if (path == null) throw StateError('Upload the blank official PDF first.');
    return widget.repository.loadPdfTemplateFile(path);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      draft.busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      draft.busy = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(bool sample) => _run(() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return;
    if ((await file.length() ?? 0) > 5 * 1024 * 1024) {
      throw ArgumentError('Each template or sample must be at most 5 MB.');
    }
    final bytes = await file.readAsBytes();
    PracticumRepository.validateTemplatePdf(file.name, bytes);
    final fields = !sample && PdfTemplateEngine.available
        ? await PdfTemplateEngine.inspect(bytes)
        : <PdfTemplateField>[];
    if (!mounted) return;
    setState(() {
      if (sample) {
        draft.sampleFile = file;
        draft.removeSample = false;
      } else {
        draft.officialFile = file;
        draft.fields = fields;
      }
    });
  });

  Future<void> _preview(bool sample) => _run(() async {
    final bytes = await _bytes(sample);
    if (!mounted) return;
    await showPdfTemplatePreview(
      context,
      bytes: bytes,
      title: sample ? 'Completed sample' : 'Blank official form',
      fileName: sample
          ? (draft.sampleFile?.name ?? draft.saved?.sampleName ?? 'sample.pdf')
          : (draft.officialFile?.name ??
                draft.saved?.officialName ??
                'official.pdf'),
    );
  });

  Future<void> _configure() => _run(() async {
    final bytes = await _bytes(false);
    if (!mounted) return;
    final fields = await showDialog<List<PdfTemplateField>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PdfFieldMapper(bytes: bytes, fields: draft.fields),
    );
    if (fields != null && mounted) {
      setState(() => draft.fields = fields);
    }
  });

  @override
  Widget build(BuildContext context) {
    final officialName = draft.officialFile?.name ?? draft.saved?.officialName;
    final sampleName = draft.removeSample
        ? null
        : draft.sampleFile?.name ?? draft.saved?.sampleName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PDF forms', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Each PDF can be up to 5 MB.',
          style: TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final official = _fileRow(
              'Blank official form',
              officialName,
              false,
            );
            final sample = _fileRow(
              'Completed sample (optional)',
              sampleName,
              true,
            );
            if (constraints.maxWidth < 490) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [official, sample],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Expanded(child: official),
                Expanded(child: sample),
              ],
            );
          },
        ),
        if (officialName != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy || !PdfTemplateEngine.available
                ? null
                : _configure,
            icon: const Icon(Icons.edit_document),
            label: Text('Configure fields (${draft.fields.length})'),
          ),
          Text(
            PdfTemplateEngine.available
                ? 'Fillable fields are detected automatically. For a regular PDF, tap where each detail should appear.'
                : 'Open the web app to configure fields and enable automatic filling.',
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: AppTheme.fontSmall,
            ),
          ),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _fileRow(String label, String? name, bool sample) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(AppTheme.controlRadius),
      border: Border.all(color: AppTheme.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            name ?? 'No file attached',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.muted),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _choose(sample),
                icon: const Icon(Icons.upload_file_outlined, size: 17),
                label: Text(name == null ? 'Upload PDF' : 'Replace PDF'),
              ),
              if (name != null) ...[
                TextButton(
                  onPressed: _busy ? null : () => _preview(sample),
                  child: const Text('Preview'),
                ),
                if (sample)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            draft.sampleFile = null;
                            draft.removeSample = true;
                          }),
                    child: const Text('Remove sample'),
                  ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

/// User-side actions. The generated personal copy is downloaded, never submitted.
class PdfTemplateActions extends StatefulWidget {
  const PdfTemplateActions({
    super.key,
    required this.template,
    required this.repository,
    required this.user,
  });
  final PdfFormTemplate template;
  final PracticumRepository repository;
  final AppUser user;
  @override
  State<PdfTemplateActions> createState() => _PdfTemplateActionsState();
}

class _PdfTemplateActionsState extends State<PdfTemplateActions> {
  bool _busy = false;
  String? _error;
  Future<void> _open({bool sample = false, bool fill = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final template = widget.template;
      final path = sample ? template.samplePath! : template.officialPath;
      final bytes = await widget.repository.loadPdfTemplateFile(path);
      if (!mounted) return;
      if (fill) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _FillPdfDialog(
            bytes: bytes,
            template: template,
            user: widget.user,
          ),
        );
      } else {
        await showPdfTemplatePreview(
          context,
          bytes: bytes,
          title: sample ? 'Completed sample' : 'Blank official form',
          fileName: sample
              ? template.sampleName ?? 'sample.pdf'
              : template.officialName,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _open(),
            icon: const Icon(Icons.description_outlined, size: 17),
            label: const Text('Official form'),
          ),
          if (widget.template.samplePath != null)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _open(sample: true),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('View sample form'),
            ),
          if (widget.template.fields.isNotEmpty && PdfTemplateEngine.available)
            FilledButton.icon(
              onPressed: _busy ? null : () => _open(fill: true),
              icon: const Icon(Icons.edit_note_outlined, size: 18),
              label: const Text('Fill & download'),
            ),
        ],
      ),
      if (widget.template.fields.isNotEmpty && !PdfTemplateEngine.available)
        const Text('Open the web app to fill this PDF automatically.'),
      if (_busy)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}

Future<void> showPdfTemplatePreview(
  BuildContext context, {
  required Uint8List bytes,
  required String title,
  required String fileName,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _PdfPreviewDialog(bytes: bytes, title: title, fileName: fileName),
);

class _PdfPreviewDialog extends StatefulWidget {
  const _PdfPreviewDialog({
    required this.bytes,
    required this.title,
    required this.fileName,
  });
  final Uint8List bytes;
  final String title, fileName;
  @override
  State<_PdfPreviewDialog> createState() => _PdfPreviewDialogState();
}

class _PdfPreviewDialogState extends State<_PdfPreviewDialog> {
  bool _saving = false;
  String? _error;
  @override
  Widget build(BuildContext context) => _PdfDialogShell(
    title: widget.title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PdfViewer.data(widget.bytes, sourceName: widget.fileName),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() {
                        _saving = true;
                        _error = null;
                      });
                      try {
                        await FilePicker.saveFile(
                          dialogTitle: 'Save PDF copy',
                          fileName: widget.fileName,
                          bytes: widget.bytes,
                        );
                      } catch (error) {
                        if (mounted) {
                          setState(
                            () => _error = 'Unable to save this copy: $error',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              icon: const Icon(Icons.download_outlined),
              label: Text(_saving ? 'Saving…' : 'Download copy'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _FillPdfDialog extends StatefulWidget {
  const _FillPdfDialog({
    required this.bytes,
    required this.template,
    required this.user,
  });
  final Uint8List bytes;
  final PdfFormTemplate template;
  final AppUser user;
  @override
  State<_FillPdfDialog> createState() => _FillPdfDialogState();
}

class _FillPdfDialogState extends State<_FillPdfDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final field in widget.template.fields) {
      final key = field.label.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
      _values[field.name] = field.type == 'checkbox'
          ? false
          : switch (key) {
              'studentname' || 'fullname' => widget.user.displayName,
              'studentnumber' || 'studentid' => widget.user.studentNumber ?? '',
              'email' || 'emailaddress' => widget.user.email,
              'program' || 'course' => widget.user.program ?? '',
              'academicyear' => widget.user.academicYear ?? '',
              'phonenumber' || 'contactnumber' => widget.user.phone ?? '',
              _ => '',
            };
      if (field.type == 'choice' &&
          !field.options.contains(_values[field.name])) {
        _values[field.name] = '';
      }
    }
  }

  @override
  Widget build(BuildContext context) => _PdfDialogShell(
    title: 'Fill your PDF copy',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter your details, then preview and download your own copy. This does not submit the document.',
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                for (final field in widget.template.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _input(field),
                  ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _preview,
              icon: const Icon(Icons.visibility_outlined),
              label: Text(_busy ? 'Preparing PDF…' : 'Preview filled copy'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _input(PdfTemplateField field) {
    final label = '${field.label}${field.required ? ' *' : ''}';
    if (field.type == 'checkbox') {
      return FormField<bool>(
        initialValue: false,
        validator: (value) => field.required && value != true
            ? 'This checkbox is required.'
            : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              value: state.value,
              onChanged: _busy
                  ? null
                  : (value) {
                      state.didChange(value);
                      _values[field.name] = value;
                    },
            ),
            if (state.errorText != null)
              Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    if (field.type == 'choice') {
      return DropdownButtonFormField<String>(
        initialValue: (_values[field.name] as String).isEmpty
            ? null
            : _values[field.name] as String,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: '', child: Text('No selection')),
          ...field.options
              .where((option) => option.isNotEmpty)
              .toSet()
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              ),
        ],
        onChanged: _busy ? null : (value) => _values[field.name] = value ?? '',
        validator: (value) => field.required && (value == null || value.isEmpty)
            ? 'Choose ${field.label}.'
            : null,
      );
    }
    return TextFormField(
      initialValue: _values[field.name] as String,
      enabled: !_busy,
      decoration: InputDecoration(labelText: label),
      maxLength: field.maxLength ?? 4000,
      minLines: field.multiline ? 3 : 1,
      maxLines: field.multiline ? 6 : 1,
      onChanged: (value) => _values[field.name] = value,
      validator: (value) =>
          field.required && (value == null || value.trim().isEmpty)
          ? 'Enter ${field.label}.'
          : null,
    );
  }

  Future<void> _preview() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await PdfTemplateEngine.fill(
        widget.bytes,
        widget.template.fields,
        _values,
      );
      if (!mounted) return;
      final base = widget.template.officialName.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final student = (widget.user.studentNumber ?? widget.user.displayName)
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      await showPdfTemplatePreview(
        context,
        bytes: bytes,
        title: 'Your filled copy',
        fileName: '${base}_$student.pdf',
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _PdfDialogShell extends StatelessWidget {
  const _PdfDialogShell({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: SizedBox(
      width: 1000,
      height: MediaQuery.sizeOf(context).height * .9,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

class _PdfFieldMapper extends StatefulWidget {
  const _PdfFieldMapper({required this.bytes, required this.fields});
  final Uint8List bytes;
  final List<PdfTemplateField> fields;
  @override
  State<_PdfFieldMapper> createState() => _PdfFieldMapperState();
}

class _PdfFieldMapperState extends State<_PdfFieldMapper> {
  late final List<PdfTemplateField> _fields = List.of(widget.fields);
  late final bool _hasNativeFields = _fields.any((field) => !field.isPlaced);

  Future<void> _edit(PdfTemplateField field, {bool add = false}) async {
    if (add && _fields.length >= 200) return;
    final label = TextEditingController(text: add ? '' : field.label);
    var required = field.required;
    var multiline = field.multiline;
    var width = field.width;
    var height = field.height;
    String? error;
    final result = await showDialog<PdfTemplateField>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(add ? 'Add detail field' : 'Edit detail field'),
          content: SizedBox(
            width: 390,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: label,
                    autofocus: true,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: 'Detail label',
                      hintText: 'For example, Student name',
                      errorText: error,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Required'),
                    value: required,
                    onChanged: (value) =>
                        setDialogState(() => required = value ?? false),
                  ),
                  if (field.type == 'text')
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Multiple lines'),
                      value: multiline,
                      onChanged: (value) =>
                          setDialogState(() => multiline = value ?? false),
                    ),
                  if (field.isPlaced) ...[
                    Text('Width: ${(width * 100).round()}% of page'),
                    Slider(
                      value: width,
                      min: .02,
                      max: (1 - field.x).clamp(.02, 1),
                      onChanged: (value) => setDialogState(() => width = value),
                    ),
                    Text('Height: ${(height * 100).round()}% of page'),
                    Slider(
                      value: height,
                      min: .015,
                      max: (1 - field.y).clamp(.015, .4),
                      onChanged: (value) =>
                          setDialogState(() => height = value),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (label.text.trim().isEmpty) {
                  setDialogState(
                    () => error = 'Enter a label for this detail.',
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  PdfTemplateField(
                    name: field.name,
                    label: label.text.trim(),
                    type: field.type,
                    required: required,
                    multiline: multiline,
                    options: field.options,
                    maxLength: field.maxLength,
                    page: field.page,
                    x: field.x,
                    y: field.y,
                    width: width,
                    height: height,
                  ),
                );
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    // Dispose after the dialog route has finished animating out.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    label.dispose();
    if (result != null && mounted) {
      setState(() {
        if (add) {
          _fields.add(result);
        } else {
          _fields[_fields.indexOf(field)] = result;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => _PdfDialogShell(
    title: 'Configure PDF details',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _hasNativeFields
              ? 'Review the detected fields and their labels.'
              : 'Tap a blank space on the PDF to place a text field. Tap a blue field to edit its label or size.',
        ),
        const SizedBox(height: 8),
        Expanded(
          child: PdfViewer.data(
            widget.bytes,
            sourceName: 'field-mapping.pdf',
            params: PdfViewerParams(
              pageOverlaysBuilder: (context, rect, page) => [
                if (!_hasNativeFields)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        if (page.rotation != PdfPageRotation.none) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Rotate the original PDF upright before adding fields.',
                              ),
                            ),
                          );
                          return;
                        }
                        final x = (details.localPosition.dx / rect.width).clamp(
                          0.0,
                          .95,
                        );
                        final y = (details.localPosition.dy / rect.height)
                            .clamp(0.0, .96);
                        _edit(
                          PdfTemplateField(
                            name:
                                'sip_${DateTime.now().microsecondsSinceEpoch}',
                            label: '',
                            page: page.pageNumber,
                            x: x,
                            y: y,
                            width: (1 - x).clamp(.02, .35),
                            height: .035,
                          ),
                          add: true,
                        );
                      },
                    ),
                  ),
                for (final field in _fields.where(
                  (field) => field.page == page.pageNumber,
                ))
                  Positioned(
                    left: field.x * rect.width,
                    top: field.y * rect.height,
                    width: field.width * rect.width,
                    height: field.height * rect.height,
                    child: GestureDetector(
                      onTap: () => _edit(field),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceBlue,
                          border: Border.all(color: AppTheme.blue),
                        ),
                        child: Text(
                          field.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.deepBlue,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView(
            children: [
              for (final field in _fields)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${field.label}${field.required ? ' *' : ''}'),
                  subtitle: Text(
                    field.isPlaced ? 'Page ${field.page}' : field.type,
                  ),
                  onTap: () => _edit(field),
                  trailing: field.isPlaced
                      ? IconButton(
                          tooltip: 'Remove field',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              setState(() => _fields.remove(field)),
                        )
                      : const Icon(Icons.edit_outlined),
                ),
            ],
          ),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _fields),
              child: const Text('Use these fields'),
            ),
          ],
        ),
      ],
    ),
  );
}
