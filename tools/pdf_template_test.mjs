import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { test } from 'node:test';

// Exercise the actual browser assets, including the bundled Unicode font.
globalThis.self = globalThis;
await import('../web/vendor/pdf-lib.min.js');
await import('../web/vendor/fontkit.umd.min.js');
globalThis.document = { baseURI: new URL('../web/', import.meta.url).href };
globalThis.fetch = async (url) => ({ ok: true, arrayBuffer: async () => readFile(url) });
await import('../web/pdf_templates.js');
const { PDFDocument, PDFName, PDFDict, PDFTextField, degrees } = globalThis.PDFLib;
const engine = globalThis.sipPdfTemplates;

async function fixture() {
  const doc = await PDFDocument.create();
  const page = doc.addPage([612, 792]);
  page.drawText('SIP application - blank original', { x: 40, y: 750, size: 16 });
  page.drawText('Student name:', { x: 40, y: 700, size: 12 });
  const form = doc.getForm();
  const name = form.createTextField('student_name');
  name.enableRequired();
  name.addToPage(page, { x: 140, y: 680, width: 350, height: 30 });
  const box = form.createCheckBox('consent');
  box.addToPage(page, { x: 40, y: 630, width: 16, height: 16 });
  const choice = form.createDropdown('program');
  choice.addOptions(['', 'BS Psychology', 'BA Communication']);
  choice.addToPage(page, { x: 40, y: 570, width: 350, height: 25 });
  const second = doc.addPage([612, 792]);
  const radio = form.createRadioGroup('placement');
  radio.addOptionToPage('On site', second, { x: 40, y: 680, width: 18, height: 18 });
  radio.addOptionToPage('Remote', second, { x: 140, y: 680, width: 18, height: 18 });
  return doc.save();
}

async function inspect(bytes) { return JSON.parse(await engine.inspect(bytes)); }
async function fill(bytes, fields, values) { return engine.fill(bytes, JSON.stringify(fields), JSON.stringify(values)); }

test('detects fields; personal copies retain logical values and widget appearances on every page', async () => {
  const original = await fixture();
  const fields = await inspect(original);
  assert.deepEqual(fields.map((field) => field.type), ['text', 'checkbox', 'choice', 'choice']);
  assert.deepEqual(fields[2].options, ['BS Psychology', 'BA Communication']);
  const output = await fill(original, fields, {
    student_name: 'María Peña – Student', consent: true, program: 'BS Psychology', placement: 'Remote',
  });
  const doc = await PDFDocument.load(output);
  assert.equal(doc.getPageCount(), 2);
  const form = doc.getForm();
  assert.equal(form.getTextField('student_name').getText(), 'María Peña – Student');
  assert.equal(form.getCheckBox('consent').isChecked(), true);
  assert.deepEqual(form.getDropdown('program').getSelected(), ['BS Psychology']);
  assert.equal(form.getRadioGroup('placement').getSelected(), 'Remote');
  for (const field of form.getFields()) {
    for (const widget of field.acroField.getWidgets()) {
      assert.ok(widget.getAppearances()?.normal, `${field.getName()} needs an appearance`);
      const parent = widget.dict.lookupMaybe(PDFName.of('Parent'), PDFDict);
      assert.ok(parent, 'Each widget must link to its canonical field');
    }
  }
  assert.equal((await PDFDocument.load(original)).getForm().getTextField('student_name').getText(), undefined);
  assert.equal((await inspect(original)).length, 4);
  // A second student's copy starts from the blank original again.
  const other = await fill(original, fields, { student_name: 'Another student', consent: false });
  const otherForm = (await PDFDocument.load(other)).getForm();
  assert.equal(otherForm.getCheckBox('consent').isChecked(), false);
  assert.deepEqual(otherForm.getDropdown('program').getSelected(), []);
  assert.equal(otherForm.getRadioGroup('placement').getSelected(), undefined);
  if (process.env.PDF_TEMPLATE_FIXTURES) {
    await mkdir(new URL('../tmp/pdf-template-review/', import.meta.url), { recursive: true });
    await writeFile(new URL('../tmp/pdf-template-review/official.pdf', import.meta.url), original);
    await writeFile(new URL('../tmp/pdf-template-review/filled.pdf', import.meta.url), output);
  }
});

test('regular PDFs get reusable text fields at the configured page and crop-box position', async () => {
  const doc = await PDFDocument.create();
  doc.addPage([612, 792]);
  const page = doc.addPage([612, 792]);
  page.setCropBox(20, 30, 500, 700);
  page.drawText('A regular SIP form', { x: 40, y: 700, size: 16 });
  const source = await doc.save();
  assert.deepEqual(await inspect(source), []);
  const fields = [{ name: 'student', label: 'Student name', type: 'text', required: true,
    page: 2, x: .1, y: .2, width: .5, height: .05 }];
  const filled = await PDFDocument.load(await fill(source, fields, { student: 'Juan Dela Cruz' }));
  const field = filled.getForm().getTextField('student');
  assert.ok(field instanceof PDFTextField);
  assert.equal(field.getText(), 'Juan Dela Cruz');
  assert.deepEqual(field.acroField.getWidgets()[0].getRectangle(), { x: 70, y: 555, width: 250, height: 35 });
  assert.equal(filled.getPage(0).node.Annots(), undefined);
  assert.equal(filled.getPage(1).node.Annots().size(), 1);
  assert.equal((await PDFDocument.load(source)).getForm().getFields().length, 0);
});

test('required fields, invalid choices, field lengths, duplicate names and bad placement fail clearly', async () => {
  const source = await fixture();
  const fields = await inspect(source);
  await assert.rejects(fill(source, fields, {}), /Complete student_name/);
  await assert.rejects(fill(source, fields.map((field) => ({ ...field, required: field.name === 'consent' })),
    { student_name: 'Student', consent: false }), /Complete consent/);
  await assert.rejects(fill(source, fields, { student_name: 'Student', program: 'Invalid' }), /valid option/);
  await assert.rejects(fill(source, [...fields, fields[0]], { student_name: 'Student' }), /unique name/);
  const short = await PDFDocument.load(source);
  short.getForm().getTextField('student_name').setMaxLength(5);
  await assert.rejects(fill(await short.save(), fields, { student_name: 'Too long' }), /at most 5/);
  const flat = await PDFDocument.create(); flat.addPage();
  const field = { name: 'f', label: 'Detail', page: 1, x: .9, y: .1, width: .3, height: .03 };
  await assert.rejects(fill(await flat.save(), [field], { f: 'value' }), /within the PDF page/);
  await assert.rejects(fill(await flat.save(), [{ ...field, page: 3 }], { f: 'value' }), /missing page/);
});

test('rejects pre-filled official forms, malformed files, XFA and signed originals', async () => {
  const source = await fixture();
  const completed = await PDFDocument.load(source);
  completed.getForm().getTextField('student_name').setText('Example student');
  await assert.rejects(inspect(await completed.save()), /must be blank/);
  await assert.rejects(inspect(new Uint8Array(6 * 1024 * 1024)), /at most 5 MB/);
  await assert.rejects(inspect(new Uint8Array([1, 2, 3])), /Failed to parse PDF/);
  const xfa = await PDFDocument.load(source);
  xfa.getForm().acroForm.dict.set(PDFName.of('XFA'), xfa.context.obj('unsupported'));
  await assert.rejects(inspect(await xfa.save({ updateFieldAppearances: false })), /XFA/);
  const signed = await PDFDocument.load(source);
  const field = signed.getForm().getTextField('student_name');
  field.acroField.dict.set(PDFName.of('FT'), PDFName.of('Sig'));
  field.acroField.dict.set(PDFName.of('V'), signed.context.obj({ Type: 'Sig' }));
  await assert.rejects(inspect(await signed.save()), /digitally signed/);
  field.acroField.dict.set(PDFName.of('V'), globalThis.PDFLib.PDFNull);
  assert.ok(await inspect(await signed.save({ updateFieldAppearances: false })), 'Unsigned signature placeholders are allowed');
});

test('rotated PDFs cannot silently place overlay text at the wrong coordinates', async () => {
  const doc = await PDFDocument.create();
  doc.addPage().setRotation(degrees(90));
  await assert.rejects(fill(await doc.save(), [{ name: 'f', label: 'Detail', page: 1,
    x: .1, y: .1, width: .4, height: .03 }], { f: 'Text' }), /upright/);
});
