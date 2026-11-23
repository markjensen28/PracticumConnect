import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import * as PDFLib from 'pdf-lib';

const fontkit = { exports: {} };
const vendor = new URL('../web/vendor/', import.meta.url);
const fontkitSource = await readFile(new URL('fontkit.umd.min.js', vendor), 'utf8');
new Function('module', 'exports', fontkitSource)(fontkit, fontkit.exports);
globalThis.PDFLib = PDFLib;
globalThis.fontkit = fontkit.exports;
globalThis.document = { baseURI: new URL('../web/index.html', import.meta.url) };
globalThis.fetch = async (url) => ({
  ok: true,
  arrayBuffer: async () => new Uint8Array(await readFile(url)).buffer,
});
await import('../web/pdf_templates.js');

const { PDFDocument, PDFName } = PDFLib;
const configs = [
  { name: 'student', type: 'text', required: true },
  { name: 'editable', type: 'text', entry: 'prefilled', presetValue: 'Main campus' },
  { name: 'locked', type: 'text', entry: 'locked', presetValue: 'COORDINATOR' },
  { name: 'hidden', type: 'text', entry: 'hidden', required: true },
  { name: 'approved', type: 'checkbox', entry: 'locked', presetValue: true },
  { name: 'campus', type: 'choice', entry: 'prefilled', presetValue: 'Main' },
  { name: 'hiddenRadio', type: 'choice', entry: 'hidden' },
  {
    name: 'hiddenPlacement', type: 'text', entry: 'hidden',
    page: 1, x: .2, y: .6, width: .2, height: .04,
  },
  {
    name: 'lockedPlacement', type: 'text', entry: 'locked',
    presetValue: 'Staff text on a static area',
    page: 1, x: .5, y: .7, width: .3, height: .035,
  },
];

async function makeTemplate() {
  const document = await PDFDocument.create();
  const page = document.addPage([600, 800]);
  const form = document.getForm();
  for (const [index, name] of ['student', 'editable', 'locked', 'hidden', 'fixedSource'].entries()) {
    const field = form.createTextField(name);
    field.addToPage(page, { x: 40, y: 710 - index * 55, width: 250, height: 28 });
  }
  const hidden = form.getTextField('hidden');
  hidden.setText('Old value');
  hidden.acroField.dict.set(
    PDFName.of('DV'),
    hidden.acroField.dict.get(PDFName.of('V')),
  );
  const originalLock = form.getTextField('fixedSource');
  originalLock.setText('Printed template information');
  originalLock.enableReadOnly();
  const checkbox = form.createCheckBox('approved');
  checkbox.addToPage(page, { x: 40, y: 430, width: 20, height: 20 });
  const choice = form.createDropdown('campus');
  choice.addOptions(['Main', 'Other']);
  choice.addToPage(page, { x: 40, y: 370, width: 180, height: 28 });
  const radio = form.createRadioGroup('hiddenRadio');
  radio.addOptionToPage('A', page, { x: 40, y: 320, width: 20, height: 20 });
  radio.select('A');
  return document.save();
}

async function filledForm(bytes, values, templateOnly = false) {
  const output = await sipPdfTemplates.fill(
    bytes,
    JSON.stringify(configs),
    JSON.stringify(values),
    templateOnly,
  );
  return (await PDFDocument.load(output)).getForm();
}

test('staff values are locked while editable prefills can be changed or cleared', async () => {
  const bytes = await makeTemplate();
  const generated = await filledForm(bytes, {
    student: 'Sample Student',
    editable: '',
    locked: 'Student override',
    hidden: 'Will not print',
    approved: false,
    campus: 'Other',
    hiddenRadio: 'A',
    hiddenPlacement: 'Will not create a widget',
  });
  const locked = generated.getTextField('locked');
  assert.equal(locked.getText(), 'COORDINATOR');
  assert(locked.isReadOnly());
  assert.equal(locked.acroField.dict.get(PDFName.of('DV')).decodeText(), 'COORDINATOR');
  assert.equal(generated.getTextField('student').getText(), 'Sample Student');
  assert(!generated.getTextField('editable').getText());
  assert(!generated.getTextField('editable').isReadOnly());
  assert.deepEqual(generated.getDropdown('campus').getSelected(), ['Other']);
  assert(generated.getCheckBox('approved').isChecked());
  assert(generated.getCheckBox('approved').isReadOnly());
  const hiddenText = generated.getTextField('hidden');
  assert(!hiddenText.getText());
  assert(!hiddenText.acroField.dict.has(PDFName.of('DV')));
  assert(!hiddenText.isRequired());
  assert(hiddenText.isReadOnly());
  assert(!generated.getRadioGroup('hiddenRadio').getSelected());
  assert(generated.getRadioGroup('hiddenRadio').isReadOnly());
  assert.equal(generated.getFieldMaybe('hiddenPlacement'), undefined);
  const lockedPlacement = generated.getTextField('lockedPlacement');
  assert.equal(lockedPlacement.getText(), 'Staff text on a static area');
  assert(lockedPlacement.isReadOnly());
  assert.equal(generated.getTextField('fixedSource').getText(), 'Printed template information');
  const source = (await PDFDocument.load(bytes)).getForm();
  assert.equal(source.getTextField('hidden').getText(), 'Old value');
  assert(!source.getTextField('locked').isReadOnly());
});

test('official form applies the configuration without requiring student answers', async () => {
  const bytes = await makeTemplate();
  const official = await filledForm(bytes, {}, true);
  assert(!official.getTextField('student').getText());
  assert.equal(official.getTextField('editable').getText(), 'Main campus');
  assert.equal(official.getTextField('locked').getText(), 'COORDINATOR');
  assert(official.getTextField('locked').isReadOnly());
  assert(!official.getTextField('hidden').getText());
  assert.deepEqual(official.getDropdown('campus').getSelected(), ['Main']);
  assert.equal(official.getFieldMaybe('hiddenPlacement'), undefined);
  await assert.rejects(filledForm(bytes, {}), /Complete student/);
});
