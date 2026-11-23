export const casCollegeName = 'College of Arts and Sciences';

export const casPrograms = [
  'Bachelor of Science in Psychology',
  'Bachelor of Science in Information Technology',
  'Bachelor of Science in Information System',
  'Bachelor of Science in Statistics',
];

export function canonicalCasProgram(value) {
  if (typeof value !== 'string') return null;
  switch (value.toLowerCase().replace(/[^a-z0-9]/g, '')) {
    case 'bspsych':
    case 'bspsychology':
    case 'bsinpsychology':
    case 'psychology':
    case 'bachelorofscienceinpsychology':
      return casPrograms[0];
    case 'bsit':
    case 'bsinformationtechnology':
    case 'bsininformationtechnology':
    case 'informationtechnology':
    case 'bachelorofinformationtechnology':
    case 'bachelorofscienceininformationtechnology':
      return casPrograms[1];
    case 'bsis':
    case 'bsinformationsystem':
    case 'bsinformationsystems':
    case 'bsininformationsystem':
    case 'bsininformationsystems':
    case 'informationsystem':
    case 'informationsystems':
    case 'bachelorofinformationsystem':
    case 'bachelorofinformationsystems':
    case 'bachelorofscienceininformationsystem':
    case 'bachelorofscienceininformationsystems':
      return casPrograms[2];
    case 'bss':
    case 'bsstat':
    case 'bsstats':
    case 'bsstatistics':
    case 'bsinstatistics':
    case 'statistics':
    case 'bachelorofscienceinstatistics':
      return casPrograms[3];
    default:
      return null;
  }
}

export function programAppliesTo(targetProgram, studentProgram) {
  const target = String(targetProgram ?? '').trim();
  if (!target || target === 'All Programs') return true;
  const canonicalTarget = canonicalCasProgram(target);
  return canonicalTarget !== null
    ? canonicalTarget === canonicalCasProgram(studentProgram)
    : typeof studentProgram === 'string' && target === studentProgram.trim();
}
