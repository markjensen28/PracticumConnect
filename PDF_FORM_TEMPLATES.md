# Reusable SIP PDF templates

The first integration is **Requirement Setup → edit/new requirement → PDF forms**.
Upload the blank official PDF and an optional completed sample. Students see
**Official form**, **View sample form**, and **Fill & download** when fields are
configured. Official and sample PDFs open in an in-app preview with a download
button. Existing URL-based requirements remain compatible until replaced.

## Coordinator workflow

1. Upload a blank PDF (maximum 5 MB, 100 pages).
2. Existing text, checkbox, dropdown, and radio fields are detected automatically.
3. Select **Configure fields** to set useful labels and required fields.
4. For a regular PDF, tap the page where text should appear. Set the label,
   field width/height, required status, and whether it accepts multiple lines.
   Tap an existing blue field to edit it; remove placed fields from the list.
5. Upload a separate pre-filled sample if needed, then save the host requirement.

Students enter their details, review the generated PDF, and download a separate
personal copy. Saving a copy does not submit a requirement or alter the original.
Names and contact information are suggested only for recognizable labels and
can be edited before generation. PDF processing runs in the browser; completed
copies and entered values are never sent to the template storage service.

## Deployment

Run the updated `supabase_storage_policies.sql` in the connected Supabase SQL
editor before enabling shared templates. It allows signed-in users to read
`<staff UID>/form_templates/<file>` and restricts creation/replacement in that
folder to staff. Personal submissions retain their existing access rules.
The existing `/api/staff-claims` endpoint verifies approved staff before upload.
No additional Firestore rules or indexes are required for the requirement
integration; its metadata is saved on the existing requirement definition.

The browser PDF dependencies and font are bundled under `web/vendor/`, so a
deployed app needs no PDF CDN or extra API service. Bundle versions are pdf-lib
1.17.1 and @pdf-lib/fontkit 1.1.1. Noto Sans Regular comes from the Noto fonts
project. Licenses accompany the assets. Flutter copies these files into its web
build automatically. The Node verification command needs no npm installation:

```powershell
node --test tools/pdf_template_test.mjs
```

## Reusing it in MOA, evaluations, or another SIP module

These components do not depend on requirement records:

- `PdfFormTemplate` / `PdfTemplateField` in `lib/models/pdf_form_template.dart`.
  Store `template.toMap()` as metadata on the host record and restore it with
  `PdfFormTemplate.fromMap(...)`.
- `PdfTemplateEditorController(template: existingTemplate)` and
  `PdfTemplateEditor(controller: controller, repository: repository)` provide
  staff upload/preview/field setup. Keep the controller for the lifetime of the
  host editor. On save, await `controller.persist(repository, actor)` and save
  the returned template metadata with the host record.
- `PdfTemplateActions(template: template, repository: repository, user: user)`
  provides preview and personal fill/download actions.
- `showPdfTemplatePreview(...)` previews already-loaded PDF bytes.
- `PdfTemplateEngine.inspect(...)` and `.fill(...)` can also be called directly.

The host module owns its visibility, authorization, and submission process.
Adding this widget does not change MOA approval or evaluation submission rules.
The repository keeps previous uploaded objects when replacing/removing metadata,
so another host record referencing a template is not broken. If saving a host
record fails, the controller retains uploaded paths for retry. Unreferenced
uploads from abandoned edits can be removed later by a storage retention task;
there is no automatic deletion of potentially referenced files.

## Supported forms and limits

- Filling and field configuration currently target Flutter **web**. Native apps
  can upload/download/preview and show guidance to open the web app for filling.
- Regular PDFs use coordinator-placed text fields. Printed text or scanned
  blank lines are not inferred automatically. For these files, the coordinator
  verifies that the original is blank; detected interactive values are checked.
- Placed fields require upright pages. Rotate the source PDF first if needed.
  Interactive fields already embedded in rotated PDFs retain their positions.
- Digital signatures are not generated. Signed, encrypted, XFA, multi-select,
  and unsupported interactive fields are rejected rather than silently changed.
- Generated copies remain editable PDFs with canonical field data and visible
  appearance streams. They are not flattened. Long fields can be made wider or
  multiline in setup. The bundled font supports Latin names and common symbols;
  unsupported characters receive a specific error instead of missing glyphs.
- Templates support at most 200 fields. A required checkbox must be checked.
