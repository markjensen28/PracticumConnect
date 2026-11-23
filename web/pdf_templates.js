/* Runs locally in the browser. Never writes into the uploaded blank template. */
(function (root) {
  'use strict';
  const maxBytes = 5 * 1024 * 1024;
  const maxFields = 400;
  let fontBytes;

  function library() {
    if (!root.PDFLib) throw new Error('PDF tools did not load. Refresh the page and try again.');
    return root.PDFLib;
  }

  async function open(bytes) {
    if (!bytes?.length || bytes.length > maxBytes) throw new Error('Choose a PDF of at most 5 MB.');
    const doc = await library().PDFDocument.load(bytes);
    if (doc.getPageCount() > 100) throw new Error('Templates may contain at most 100 pages.');
    // getForm() removes XFA, so inspect the source dictionary first.
    const acroForm = doc.catalog.lookupMaybe(library().PDFName.of('AcroForm'), library().PDFDict);
    if (acroForm?.has(library().PDFName.of('XFA'))) {
      throw new Error('XFA forms are unsupported. Export a standard PDF first.');
    }
    const form = doc.getForm();
    const signed = form.getFields().some((field) => {
      if (!(field instanceof library().PDFSignature)) return false;
      const value = field.acroField.dict.lookup(library().PDFName.of('V'));
      return value !== undefined && value !== library().PDFNull;
    });
    if (signed) throw new Error('This PDF is digitally signed. Upload an unsigned blank original.');
    return doc;
  }

  function describe(field) {
    const lib = library();
    if (field.isReadOnly() || field instanceof lib.PDFSignature || field instanceof lib.PDFButton) return null;
    const tooltip = field.acroField.dict.lookup(lib.PDFName.of('TU'));
    const alternate = tooltip instanceof lib.PDFString || tooltip instanceof lib.PDFHexString
      ? tooltip.decodeText().trim()
      : '';
    const base = { name: field.getName(), label: alternate || field.getName(), required: field.isRequired() };
    if (field instanceof lib.PDFTextField) {
      if (field.getText()?.trim()) throw new Error('The official form must be blank. Upload completed examples as the sample.');
      return { ...base, type: 'text', maxLength: field.getMaxLength(), multiline: field.isMultiline() };
    }
    if (field instanceof lib.PDFCheckBox) {
      if (field.isChecked()) throw new Error('The official form must have unchecked boxes.');
      return { ...base, type: 'checkbox' };
    }
    if (field instanceof lib.PDFDropdown || field instanceof lib.PDFRadioGroup) {
      const selected = field.getSelected();
      if (selected && (Array.isArray(selected) ? selected.some(Boolean) : selected)) {
        throw new Error('The official form must have empty selections.');
      }
      if (field instanceof lib.PDFDropdown && field.isMultiselect()) {
        throw new Error('Multiple-selection fields are unsupported. Use single-choice fields.');
      }
      return { ...base, type: 'choice', options: [...new Set(field.getOptions().filter(Boolean))] };
    }
    throw new Error(`Unsupported field: ${field.getName()}. Use text, checkbox, or single-choice fields.`);
  }

  function visibleWidgetBounds(widget, page) {
    const { AnnotationFlags } = library();
    if (widget.getFlags() & (AnnotationFlags.Invisible | AnnotationFlags.Hidden | AnnotationFlags.NoView)) return null;
    const media = page.getMediaBox();
    const crop = page.getCropBox();
    const originX = Math.max(media.x, crop.x);
    const originY = Math.max(media.y, crop.y);
    const width = Math.min(media.x + media.width, crop.x + crop.width) - originX;
    const height = Math.min(media.y + media.height, crop.y + crop.height) - originY;
    const rect = widget.getRectangle();
    const clamp = value => Math.max(0, Math.min(1, value));
    const left = clamp((rect.x - originX) / width);
    const right = clamp((rect.x + rect.width - originX) / width);
    const bottom = clamp((rect.y - originY) / height);
    const top = clamp((rect.y + rect.height - originY) / height);
    if (!(width > 0 && height > 0 && right > left && top > bottom)) return null;
    const w = right - left;
    const h = top - bottom;
    // PDF rectangles use bottom-left coordinates before the page is rotated.
    switch ((page.getRotation().angle % 360 + 360) % 360) {
      case 90: return { x: bottom, y: left, width: h, height: w };
      case 180: return { x: 1 - right, y: bottom, width: w, height: h };
      case 270: return { x: 1 - top, y: 1 - right, width: h, height: w };
      default: return { x: left, y: 1 - top, width: w, height: h };
    }
  }

  async function getFont(doc) {
    if (!root.fontkit) throw new Error('PDF fonts did not load. Refresh the page.');
    doc.registerFontkit(root.fontkit);
    fontBytes ??= fetch(new URL('vendor/NotoSans-Regular.ttf', document.baseURI)).then(async (response) => {
      if (!response.ok) throw new Error('The PDF font could not be loaded. Try again.');
      return new Uint8Array(await response.arrayBuffer());
    }).catch((error) => { fontBytes = undefined; throw error; });
    return doc.embedFont(await fontBytes, { subset: true });
  }

  function lockValue(field) {
    const { PDFName } = library();
    const dict = field.acroField.dict;
    const value = dict.get(PDFName.of('V'));
    const defaultValue = PDFName.of('DV');
    if (value === undefined) dict.delete(defaultValue);
    else dict.set(defaultValue, value);
    field.disableRequired();
    field.enableReadOnly();
  }

  function leaveFieldBlank(field) {
    const { PDFTextField, PDFCheckBox, PDFDropdown, PDFRadioGroup } = library();
    if (field instanceof PDFTextField) {
      if (field.getText()) field.setText(undefined);
    } else if (field instanceof PDFCheckBox) {
      if (field.isChecked()) field.uncheck();
    } else if (field instanceof PDFDropdown) {
      if (field.getSelected().length) field.clear();
    } else if (field instanceof PDFRadioGroup) {
      if (field.getSelected()) field.clear();
    } else {
      return;
    }
    lockValue(field);
  }

  function autoSizeText(field) {
    const appearance = field.acroField.getDefaultAppearance() ?? '';
    if (/\/[^\s\0]+[\s\0]*(?:\d*\.\d+|\d+)?[\s\0]+Tf/.test(appearance)) {
      field.setFontSize(0);
    } else {
      // Some PDF producers define a font on the widget but omit it on the field.
      field.acroField.setDefaultAppearance('0 g /Helv 0 Tf');
    }
  }

  root.sipPdfTemplates = {
    async inspect(bytes) {
      const doc = await open(bytes);
      const fields = doc.getForm().getFields().map(describe).filter(Boolean);
      if (fields.length > maxFields) throw new Error(`Templates may contain at most ${maxFields} fields.`);
      return JSON.stringify(fields);
    },

    async locate(bytes) {
      const doc = await open(bytes);
      const annotations = new Map();
      for (const [index, page] of doc.getPages().entries()) {
        for (const reference of page.node.Annots()?.asArray() ?? []) {
          annotations.set(doc.context.lookup(reference), { page, index });
        }
      }
      const fields = Object.create(null);
      for (const field of doc.getForm().getFields()) {
        fields[field.getName()] = field.acroField.getWidgets().flatMap(widget => {
          const target = annotations.get(widget.dict);
          if (!target) return [];
          try {
            const bounds = visibleWidgetBounds(widget, target.page);
            return bounds ? [{ page: target.index + 1, ...bounds }] : [];
          } catch {
            return [];
          }
        }).sort((a, b) => a.page - b.page || a.y - b.y || a.x - b.x);
      }
      return JSON.stringify(fields);
    },

    async fill(bytes, fieldsJson, valuesJson, templateOnly = false) {
      const doc = await open(bytes);
      const form = doc.getForm();
      const fields = JSON.parse(fieldsJson);
      const values = JSON.parse(valuesJson);
      if (!fields.length || fields.length > maxFields) throw new Error(`Configure between 1 and ${maxFields} fields.`);
      const names = new Set();
      const font = await getFont(doc);
      const supportedCharacters = new Set(font.getCharacterSet());
      for (const config of fields) {
        if (!config.name || names.has(config.name)) throw new Error('Every field must have a unique name.');
        names.add(config.name);
        const placed = Number.isInteger(config.page);
        if (config.entry === 'hidden') {
          if (!placed) leaveFieldBlank(form.getFieldMaybe(config.name));
          continue;
        }
        const locked = config.entry === 'locked';
        const prefilled = config.entry === 'prefilled';
        if (templateOnly && !locked && !prefilled) continue;

        const usePreset = locked || (prefilled && (templateOnly || !Object.hasOwn(values, config.name)));
        const value = usePreset ? config.presetValue : values[config.name];
        const required = !locked && config.required;
        if (!templateOnly && required && (config.type === 'checkbox' ? value !== true : !String(value ?? '').trim())) {
          throw new Error(`Complete ${config.label || config.name}.`);
        }
        let field;
        if (placed) {
          const page = doc.getPages()[config.page - 1];
          if (!page) throw new Error('A mapped field refers to a missing page.');
          const { x, y, width, height } = config;
          if (![x, y, width, height].every(Number.isFinite) || x < 0 || y < 0 ||
              width <= 0 || height <= 0 || x + width > 1.001 || y + height > 1.001) {
            throw new Error('Place all fields within the PDF page.');
          }
          if (page.getRotation().angle !== 0) throw new Error('Rotate this PDF to upright pages before mapping fields.');
          field = form.createTextField(config.name);
          const box = page.getCropBox();
          field.addToPage(page, {
            x: box.x + x * box.width, y: box.y + (1 - y - height) * box.height,
            width: width * box.width, height: height * box.height,
            borderWidth: 0, backgroundColor: undefined, font,
          });
        } else {
          field = form.getField(config.name);
        }
        required ? field.enableRequired() : field.disableRequired();
        if (field instanceof library().PDFTextField) {
          const text = String(value ?? '');
          const limit = field.getMaxLength() ?? config.maxLength ?? 4000;
          if (text.length > limit) throw new Error(`${config.label} must have at most ${limit} characters.`);
          if ([...text].some((char) => !['\n', '\r', '\t'].includes(char) && !supportedCharacters.has(char.codePointAt(0)))) {
            throw new Error(`${config.label} contains a character this PDF font cannot display.`);
          }
          config.multiline ? field.enableMultiline() : field.disableMultiline();
          autoSizeText(field);
          field.setText(text);
        } else if (field instanceof library().PDFCheckBox) {
          value === true ? field.check() : field.uncheck();
        } else if (field instanceof library().PDFDropdown || field instanceof library().PDFRadioGroup) {
          if (value) {
            if (!field.getOptions().includes(value)) throw new Error(`Choose a valid option for ${config.label}.`);
            field.select(value);
          } else field.clear();
        } else throw new Error(`Unsupported field: ${config.name}.`);
        if (locked) lockValue(field);
      }
      form.updateFieldAppearances(font);
      const { PDFName, PDFRef } = library();
      const treeKey = PDFName.of('StructTreeRoot');
      const structureTree = doc.catalog.get(treeKey);
      if (structureTree instanceof PDFRef && !doc.context.lookup(structureTree)) {
        // Some exports keep a dangling pointer to a deleted accessibility tree.
        doc.catalog.delete(treeKey);
        doc.catalog.delete(PDFName.of('MarkInfo'));
      }
      return doc.save();
    },
  };
})(globalThis);
