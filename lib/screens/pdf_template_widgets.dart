import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../models/pdf_form_template.dart';
import '../services/pdf_template_engine.dart';
import '../services/practicum_repository.dart';
import 'workflow_shared.dart';
import 'workspace_select_field.dart';

Future<void> showDefaultPdfTemplateSettings(
  BuildContext context, {
  required PracticumRepository repository,
  required AppUser actor,
  required SchoolTemplateKind kind,
}) async {
  final name = kind == SchoolTemplateKind.moa ? 'MOA' : 'evaluation';
  DefaultPdfTemplate? current;
  try {
    current = await repository.readDefaultPdfTemplate(actor, kind);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load the default template settings.'),
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  var automatic = true;
  PlatformFile? replacement;
  await showWorkspaceEditorDialog(
    context,
    title: 'Default $name template',
    saveLabel: 'Save default',
    width: 460,
    fields: (context, update) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Attach automatically'),
          subtitle: Text(
            kind == SchoolTemplateKind.moa
                ? 'New MOAs will start with this PDF.'
                : 'New supervisor evaluation links will start with this PDF.',
          ),
          value: automatic,
          onChanged: (value) => update(() => automatic = value),
        ),
        if (automatic)
          OutlinedButton.icon(
            onPressed: () async {
              final selected = await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: ['pdf'],
              );
              if (selected != null && context.mounted) {
                update(() => replacement = selected);
              }
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(
              replacement?.name ?? current?.name ?? 'Choose default PDF',
            ),
          ),
      ],
    ),
    onSave: () async {
      if (!automatic) {
        if (current != null)
          await repository.setDefaultPdfTemplate(actor, kind, null);
        return;
      }
      final file = replacement;
      if (file == null) {
        if (current == null) throw ArgumentError('Choose the default PDF.');
        return;
      }
      if (kind == SchoolTemplateKind.evaluation &&
          PdfTemplateEngine.available) {
        final fields = await PdfTemplateEngine.inspect(
          await file.readAsBytes(),
        );
        if (fields.isEmpty)
          throw ArgumentError('Choose an evaluation PDF with editable fields.');
      }
      await repository.setDefaultPdfTemplate(actor, kind, file);
    },
  );
}

Future<DefaultPdfTemplate?> loadDefaultPdfTemplate(
  BuildContext context,
  PracticumRepository repository,
  AppUser actor,
  SchoolTemplateKind kind,
) async {
  try {
    return await repository.readDefaultPdfTemplate(actor, kind);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not load the default template. You can attach a file for this record.',
          ),
        ),
      );
    }
    return null;
  }
}

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
      var bytes = await widget.repository.loadPdfTemplateFile(path);
      if (!sample && !fill && template.hasCustomEntries) {
        bytes = await PdfTemplateEngine.fill(
          bytes,
          template.fields,
          const {},
          templateOnly: true,
        );
      }
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
          title: sample
              ? 'Completed sample'
              : template.hasCustomEntries
              ? 'Official form'
              : 'Blank official form',
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
            onPressed:
                _busy ||
                    (widget.template.hasCustomEntries &&
                        !PdfTemplateEngine.available)
                ? null
                : () => _open(),
            icon: const Icon(Icons.description_outlined, size: 17),
            label: const Text('Official form'),
          ),
          if (widget.template.samplePath != null)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _open(sample: true),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('View sample form'),
            ),
          if (widget.template.hasStudentFields && PdfTemplateEngine.available)
            FilledButton.icon(
              onPressed: _busy ? null : () => _open(fill: true),
              icon: const Icon(Icons.edit_note_outlined, size: 18),
              label: const Text('Fill & download'),
            ),
        ],
      ),
      if (widget.template.fields.isNotEmpty && !PdfTemplateEngine.available)
        Text(
          widget.template.hasCustomEntries
              ? 'Open the web app to use this configured PDF.'
              : 'Open the web app to fill this PDF automatically.',
        ),
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
  final _viewer = PdfViewerController();
  late final _visibleFields = widget.template.fields
      .where((field) => field.entry != PdfFieldEntry.hidden)
      .toList();
  Map<String, List<PdfFieldLocation>> _locations = const {};
  PdfTemplateField? _selectedField;
  int _page = 1;
  int _pageCount = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLocations();
    for (final field in widget.template.fields.where(
      (field) => field.entry.studentEditable,
    )) {
      if (field.entry == PdfFieldEntry.prefilled) {
        _values[field.name] = field.type == 'checkbox'
            ? field.presetValue == true
            : field.presetText;
      } else {
        final key = field.label.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
        _values[field.name] = field.type == 'checkbox'
            ? false
            : switch (key) {
                'studentname' || 'fullname' => widget.user.displayName,
                'studentnumber' ||
                'studentid' => widget.user.studentNumber ?? '',
                'email' || 'emailaddress' => widget.user.email,
                'program' || 'course' => widget.user.program ?? '',
                'academicyear' => widget.user.academicYear ?? '',
                'phonenumber' || 'contactnumber' => widget.user.phone ?? '',
                _ => '',
              };
      }
      if (field.type == 'choice' &&
          !field.options.contains(_values[field.name])) {
        _values[field.name] = '';
      }
    }
  }

  Future<void> _loadLocations() async {
    if (!_visibleFields.any((field) => !field.isPlaced)) return;
    try {
      final locations = await PdfTemplateEngine.locate(widget.bytes);
      if (!mounted) return;
      setState(() => _locations = locations);
      _revealSelected();
    } catch (_) {
      // A PDF can still be filled when its preview positions are unavailable.
    }
  }

  void _revealSelected() {
    final field = _selectedField;
    if (field == null || _pageCount == 0) return;
    _revealPdfPosition(_viewer, _fieldLocations(field, _locations), _page);
  }

  void _selectField(PdfTemplateField field) {
    if (_selectedField == field) return;
    setState(() => _selectedField = field);
    _revealSelected();
  }

  void _changeValue(PdfTemplateField field, Object? value) {
    final shouldReveal = _selectedField != field;
    setState(() {
      _selectedField = field;
      _values[field.name] = value;
    });
    if (shouldReveal) _revealSelected();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: 1360,
      height: 900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Fill your PDF copy',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Text(
                  'Select a field to find it in the PDF. Your entries appear as you type.',
                  style: TextStyle(color: AppTheme.muted),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final preview = _livePreview();
                final form = _studentForm();
                if (bounds.maxWidth < 790) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: preview),
                      const Divider(height: 1),
                      Expanded(flex: 6, child: form),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: preview),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 390, child: form),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
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
                      label: Text(
                        _busy ? 'Preparing PDF…' : 'Preview filled copy',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _studentForm() => Form(
    key: _formKey,
    child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _visibleFields.length,
      itemBuilder: (context, index) {
        final field = _visibleFields[index];
        return Padding(
          key: ValueKey(field.name),
          padding: const EdgeInsets.only(bottom: 16),
          child: field.entry == PdfFieldEntry.locked
              ? InkWell(
                  onTap: () => _selectField(field),
                  child: _lockedValue(field),
                )
              : Focus(
                  onFocusChange: (focused) {
                    if (focused) _selectField(field);
                  },
                  child: _input(field),
                ),
        );
      },
    ),
  );

  Widget _livePreview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'PDF preview',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: 'Previous page',
              onPressed: _page > 1
                  ? () => _viewer.goToPage(pageNumber: _page - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text(_pageCount == 0 ? 'Page' : 'Page $_page of $_pageCount'),
            IconButton(
              tooltip: 'Next page',
              onPressed: _page < _pageCount
                  ? () => _viewer.goToPage(pageNumber: _page + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: PdfViewer.data(
          widget.bytes,
          sourceName: 'student-form-preview.pdf',
          controller: _viewer,
          params: PdfViewerParams(
            backgroundColor: AppTheme.background,
            margin: 12,
            onViewerReady: (document, controller) {
              if (!mounted) return;
              setState(() => _pageCount = document.pages.length);
              _revealSelected();
            },
            onPageChanged: (page) {
              if (mounted && page != null && page != _page) {
                setState(() => _page = page);
              }
            },
            pageOverlaysBuilder: _previewOverlays,
          ),
        ),
      ),
    ],
  );

  List<Widget> _previewOverlays(BuildContext context, Rect rect, PdfPage page) {
    return [
      for (final field in _visibleFields)
        ..._previewField(field, rect.size, page.pageNumber),
    ];
  }

  Iterable<Widget> _previewField(
    PdfTemplateField field,
    Size pageSize,
    int page,
  ) sync* {
    final value = field.entry == PdfFieldEntry.locked
        ? field.presetValue
        : _values[field.name];
    final isCheck = field.type == 'checkbox';
    final content = isCheck ? '' : value?.toString() ?? '';
    final selected = field == _selectedField;
    if (!selected && content.isEmpty && value != true) return;
    for (final position in _fieldLocations(field, _locations)) {
      if (position.page != page) continue;
      final bounds = _pdfFieldBounds(position, pageSize);
      final fontSize = (bounds.height * .65).clamp(1.0, 22.0);
      final text = Text(
        content,
        maxLines: field.multiline ? null : 1,
        overflow: TextOverflow.clip,
        style: TextStyle(fontSize: fontSize, height: 1, color: Colors.black),
      );
      yield Positioned.fromRect(
        rect: bounds,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? AppTheme.blue.withValues(alpha: .14) : null,
              border: selected
                  ? Border.all(color: AppTheme.blue, width: 1.5)
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: isCheck
                  ? (value == true
                        ? Center(
                            child: Icon(
                              Icons.check,
                              size: fontSize,
                              color: Colors.black,
                            ),
                          )
                        : null)
                  : field.multiline
                  ? Align(alignment: Alignment.topLeft, child: text)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: text,
                    ),
            ),
          ),
        ),
      );
    }
  }

  Widget _lockedValue(PdfTemplateField field) => InputDecorator(
    decoration: InputDecoration(
      labelText: field.label,
      prefixIcon: const Icon(Icons.lock_outline, size: 18),
      helperText: 'Set by staff',
    ),
    child: Text(
      field.type == 'checkbox'
          ? (field.presetValue == true ? 'Checked' : 'Unchecked')
          : field.presetText,
    ),
  );

  Widget _input(PdfTemplateField field) {
    final label = '${field.label}${field.required ? ' *' : ''}';
    if (field.type == 'checkbox') {
      return FormField<bool>(
        initialValue: _values[field.name] == true,
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
                      _changeValue(field, value);
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
      return WorkspaceSelectField<String>(
        label: label,
        initialValue: _values[field.name] as String,
        options: [
          '',
          ...field.options.where((option) => option.isNotEmpty).toSet(),
        ],
        optionLabel: (value) => value.isEmpty ? 'No selection' : value,
        enabled: !_busy,
        onChanged: (value) => _changeValue(field, value),
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
      onChanged: (value) => _changeValue(field, value),
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
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message : error.toString(),
        );
      }
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
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: SizedBox(
        width: 1000,
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
    ),
  );
}

List<PdfFieldLocation> _fieldLocations(
  PdfTemplateField field,
  Map<String, List<PdfFieldLocation>> native,
) => field.page == null
    ? native[field.name] ?? const []
    : [
        (
          page: field.page!,
          x: field.x,
          y: field.y,
          width: field.width,
          height: field.height,
        ),
      ];

Rect _pdfFieldBounds(PdfFieldLocation position, Size page) => Rect.fromLTWH(
  position.x * page.width,
  position.y * page.height,
  position.width * page.width,
  position.height * page.height,
);

void _revealPdfPosition(
  PdfViewerController viewer,
  List<PdfFieldLocation> positions,
  int currentPage,
) {
  if (!viewer.isReady) return;
  final location =
      positions.where((position) => position.page == currentPage).firstOrNull ??
      positions.firstOrNull;
  if (location == null || location.page < 1 || location.page > viewer.pageCount)
    return;
  final page = viewer.layout.pageLayouts[location.page - 1];
  final target = _pdfFieldBounds(location, page.size).shift(page.topLeft);
  final visible = viewer.visibleRect.deflate(8 / viewer.currentZoom);
  if (visible.contains(target.topLeft) && visible.contains(target.bottomRight))
    return;
  viewer.goTo(viewer.calcMatrixFor(target.center, zoom: viewer.currentZoom));
}

class _PdfFieldMapper extends StatefulWidget {
  const _PdfFieldMapper({required this.bytes, required this.fields});
  final Uint8List bytes;
  final List<PdfTemplateField> fields;

  @override
  State<_PdfFieldMapper> createState() => _PdfFieldMapperState();
}

class _PdfFieldMapperState extends State<_PdfFieldMapper> {
  static const _entryLabels = {
    PdfFieldEntry.student: 'Student fills',
    PdfFieldEntry.prefilled: 'Prefill and allow edits',
    PdfFieldEntry.locked: 'Prefill and lock',
    PdfFieldEntry.hidden: 'Hide and leave blank',
  };

  final _viewer = PdfViewerController();
  late final List<PdfTemplateField> _fields = List.of(widget.fields);
  late final bool _hasNativeFields = _fields.any((field) => !field.isPlaced);
  Map<String, List<PdfFieldLocation>> _locations = const {};
  String? _selectedName;
  int _page = 1;
  int _pageCount = 0;
  bool _locating = false;
  bool _showFieldErrors = false;

  PdfTemplateField? get _selected =>
      _fields.where((field) => field.name == _selectedName).firstOrNull;

  @override
  void initState() {
    super.initState();
    if (_hasNativeFields) _loadLocations();
  }

  Future<void> _loadLocations() async {
    _locating = true;
    var locations = const <String, List<PdfFieldLocation>>{};
    try {
      locations = await PdfTemplateEngine.locate(widget.bytes);
    } catch (_) {
      // Keep the editor usable if a PDF's field positions cannot be read.
    }
    if (!mounted) return;
    setState(() {
      _locations = locations;
      _locating = false;
    });
    final selected = _selected;
    if (selected != null) _reveal(selected);
  }

  List<PdfFieldLocation> _positions(PdfTemplateField field) =>
      _fieldLocations(field, _locations);

  void _select(PdfTemplateField field, {bool reveal = true}) {
    setState(() => _selectedName = field.name);
    if (reveal) _reveal(field);
  }

  void _reveal(PdfTemplateField field) {
    if (_pageCount == 0) return;
    _revealPdfPosition(_viewer, _positions(field), _page);
  }

  void _update(PdfTemplateField field) {
    final index = _fields.indexWhere((item) => item.name == field.name);
    setState(() => _fields[index] = field);
  }

  void _place(PdfPage page, Rect rect, Offset point) {
    if (page.rotation != PdfPageRotation.none) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rotate the PDF upright before placing fields.'),
        ),
      );
      return;
    }
    final x = (point.dx / rect.width).clamp(0.0, .95);
    final y = (point.dy / rect.height).clamp(0.0, .96);
    final field = PdfTemplateField(
      name: 'sip_${DateTime.now().microsecondsSinceEpoch}',
      label: '',
      page: page.pageNumber,
      x: x,
      y: y,
      width: (1 - x).clamp(.02, .35),
    );
    setState(() {
      _fields.add(field);
      _selectedName = field.name;
    });
  }

  void _save() {
    final invalid = _fields
        .where(
          (field) => field.label.trim().isEmpty || field.presetError != null,
        )
        .firstOrNull;
    if (invalid != null) {
      setState(() {
        _showFieldErrors = true;
        _selectedName = invalid.name;
      });
      _reveal(invalid);
      return;
    }
    Navigator.pop(context, [
      for (final field in _fields) field.copyWith(label: field.label.trim()),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 1360,
        height: 940,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Configure PDF fields',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    _hasNativeFields
                        ? 'Select a field in the list or on the PDF to see where it appears and edit its label.'
                        : 'Tap a blank space on the PDF to place a text field.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final preview = _preview();
                  if (constraints.maxWidth < 790) {
                    final showMorePreview =
                        _selected?.isPlaced == false &&
                        constraints.maxHeight > 500;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: showMorePreview ? 7 : 5, child: preview),
                        const Divider(height: 1),
                        Expanded(flex: 6, child: _fieldPanel(compact: true)),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: preview),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 376, child: _fieldPanel(compact: false)),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Use these fields'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'PDF preview',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: 'Previous page',
              onPressed: _page > 1
                  ? () => _viewer.goToPage(pageNumber: _page - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                _pageCount == 0 ? 'Page' : 'Page $_page of $_pageCount',
              ),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: _page < _pageCount
                  ? () => _viewer.goToPage(pageNumber: _page + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: PdfViewer.data(
          widget.bytes,
          sourceName: 'field-mapping.pdf',
          controller: _viewer,
          params: PdfViewerParams(
            backgroundColor: AppTheme.background,
            margin: 12,
            onViewerReady: (document, controller) {
              if (!mounted) return;
              setState(() => _pageCount = document.pages.length);
              final selected = _selected;
              if (selected != null) _reveal(selected);
            },
            onPageChanged: (page) {
              if (mounted && page != null && page != _page) {
                setState(() => _page = page);
              }
            },
            pageOverlaysBuilder: _pageOverlays,
          ),
        ),
      ),
    ],
  );

  List<Widget> _pageOverlays(BuildContext context, Rect rect, PdfPage page) {
    final selected = _selected;
    return [
      if (!_hasNativeFields && _fields.length < maxPdfTemplateFields)
        Positioned.fill(
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _place(page, rect, details.localPosition),
            ),
          ),
        ),
      for (final field in _fields.where((field) => field != selected))
        ..._fieldMarkers(field, page, rect.size),
      if (selected != null) ..._fieldMarkers(selected, page, rect.size),
    ];
  }

  Iterable<Widget> _fieldMarkers(
    PdfTemplateField field,
    PdfPage page,
    Size pageSize,
  ) sync* {
    final selected = field.name == _selectedName;
    for (final position in _positions(field)) {
      if (position.page != page.pageNumber) continue;
      yield Positioned.fromRect(
        rect: _pdfFieldBounds(position, pageSize),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: () => _select(field, reveal: false),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.blue.withValues(alpha: selected ? .22 : .07),
                border: Border.all(
                  color: selected
                      ? AppTheme.blue
                      : AppTheme.deepBlue.withValues(alpha: .50),
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? const [BoxShadow(color: Colors.white, spreadRadius: 1)]
                    : null,
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _fieldPanel({required bool compact}) => LayoutBuilder(
    builder: (context, constraints) =>
        _fieldPanelContents(compact, constraints.maxHeight),
  );

  Widget _fieldPanelContents(bool compact, double height) {
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (compact && selected != null)
                TextButton.icon(
                  onPressed: () => setState(() => _selectedName = null),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('All fields'),
                )
              else
                Expanded(
                  child: Text(
                    'Fields (${_fields.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (!compact || selected == null)
          Expanded(
            child: _fields.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No fields yet. Select a blank space on the PDF to add one.',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _fields.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) => _fieldRow(_fields[index]),
                  ),
          ),
        if (selected != null)
          if (compact)
            Expanded(child: _fieldSettings(selected))
          else ...[
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: height * .55),
              child: _fieldSettings(selected),
            ),
          ],
      ],
    );
  }

  Widget _fieldRow(PdfTemplateField field) {
    final positions = _positions(field);
    final type = switch (field.type) {
      'checkbox' => 'Checkbox',
      'choice' => 'Choice',
      _ => 'Text',
    };
    final location = _locating && !field.isPlaced
        ? 'Locating'
        : positions.isEmpty
        ? 'Location unavailable'
        : positions.length == 1
        ? 'Page ${positions.first.page}'
        : '${positions.length} locations';
    final access = switch (field.entry) {
      PdfFieldEntry.student => null,
      PdfFieldEntry.prefilled => 'Prefilled',
      PdfFieldEntry.locked => 'Locked',
      PdfFieldEntry.hidden => 'Hidden',
    };
    return ListTile(
      selected: field.name == _selectedName,
      selectedTileColor: AppTheme.surfaceBlue,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        field.label.trim().isEmpty ? 'Unnamed field' : field.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [type, location, if (access != null) access].join('  •  '),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _select(field),
    );
  }

  Widget _fieldSettings(PdfTemplateField field) => ColoredBox(
    color: AppTheme.surfaceSoft,
    child: SingleChildScrollView(
      key: ValueKey(field.name),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Field settings',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Locate field on PDF',
                onPressed: _positions(field).isEmpty
                    ? null
                    : () => _reveal(field),
                icon: const Icon(Icons.my_location_outlined, size: 20),
              ),
              if (field.isPlaced)
                IconButton(
                  tooltip: 'Remove field',
                  onPressed: () => setState(() {
                    _fields.remove(field);
                    _selectedName = null;
                  }),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
            ],
          ),
          TextFormField(
            initialValue: field.label,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: 'Field label',
              hintText: 'For example, Student name',
              counterText: '',
              errorText: _showFieldErrors && field.label.trim().isEmpty
                  ? 'Enter a field label.'
                  : null,
            ),
            onChanged: (value) => _update(field.copyWith(label: value)),
          ),
          WorkspaceSelectField<PdfFieldEntry>(
            label: 'Student access',
            initialValue: field.entry,
            options: PdfFieldEntry.values,
            optionLabel: (entry) => _entryLabels[entry]!,
            onChanged: (entry) => _update(field.copyWith(entry: entry)),
          ),
          if (field.entry.usesPreset) _presetInput(field),
          if (field.entry == PdfFieldEntry.hidden)
            const Text(
              'Students won’t see this field. It stays blank in their PDF copy.',
              style: TextStyle(color: AppTheme.muted),
            ),
          Wrap(
            spacing: 16,
            children: [
              if (field.entry.studentEditable)
                _fieldOption(
                  'Required',
                  field.required,
                  (value) => _update(field.copyWith(required: value)),
                ),
              if (field.type == 'text' && field.entry != PdfFieldEntry.hidden)
                _fieldOption(
                  'Multiple lines',
                  field.multiline,
                  (value) => _update(field.copyWith(multiline: value)),
                ),
            ],
          ),
          if (field.isPlaced && field.entry != PdfFieldEntry.hidden)
            Row(
              children: [
                Expanded(
                  child: _sizeSlider(
                    'Width',
                    field.width,
                    .02,
                    (1 - field.x).clamp(.02, 1),
                    (value) => _update(field.copyWith(width: value)),
                  ),
                ),
                Expanded(
                  child: _sizeSlider(
                    'Height',
                    field.height,
                    .015,
                    (1 - field.y).clamp(.015, .4),
                    (value) => _update(field.copyWith(height: value)),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _presetInput(PdfTemplateField field) {
    final error = _showFieldErrors ? field.presetError : null;
    if (field.type == 'text') {
      return TextFormField(
        initialValue: field.presetText,
        maxLength: field.maxLength ?? 4000,
        minLines: field.multiline ? 2 : 1,
        maxLines: field.multiline ? 4 : 1,
        decoration: InputDecoration(
          labelText: 'Prefilled value',
          counterText: '',
          errorText: error,
        ),
        onChanged: (value) => _update(field.copyWith(presetValue: value)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (field.type == 'checkbox')
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _fieldOption(
              'Prefill as checked',
              field.presetValue == true,
              (value) => _update(field.copyWith(presetValue: value)),
            ),
          )
        else
          WorkspaceSelectField<String>(
            label: 'Prefilled option',
            hint: 'Select an option',
            initialValue: field.presetText,
            options: field.options,
            onChanged: (value) => _update(field.copyWith(presetValue: value)),
          ),
        if (error != null)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  Widget _fieldOption(
    String label,
    bool checked,
    ValueChanged<bool> onChanged,
  ) => InkWell(
    canRequestFocus: false,
    excludeFromSemantics: true,
    onTap: () => onChanged(!checked),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          semanticLabel: label,
          value: checked,
          onChanged: (value) => onChanged(value!),
        ),
        ExcludeSemantics(child: Text(label)),
      ],
    ),
  );

  Widget _sizeSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Column(
    children: [
      Text('$label ${(value * 100).round()}%'),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
        semanticFormatterCallback: (value) =>
            '$label ${(value * 100).round()} percent',
      ),
    ],
  );
}
