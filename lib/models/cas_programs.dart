const casCollegeName = 'College of Arts and Sciences';

const casPrograms = [
  'Bachelor of Science in Psychology',
  'Bachelor of Science in Information Technology',
  'Bachelor of Science in Information System',
  'Bachelor of Science in Statistics',
];

const casYearLevels = ['1st Year', '2nd Year', '3rd Year', '4th Year'];

String? canonicalCasYearLevel(String? value) {
  return switch (value?.trim().toLowerCase()) {
    '1' || '1st' || '1st year' || 'first year' => casYearLevels[0],
    '2' || '2nd' || '2nd year' || 'second year' => casYearLevels[1],
    '3' || '3rd' || '3rd year' || 'third year' => casYearLevels[2],
    '4' || '4th' || '4th year' || 'fourth year' => casYearLevels[3],
    _ => null,
  };
}

String? canonicalCasProgram(String? value) {
  final key = value?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return switch (key) {
    'bspsych' ||
    'bspsychology' ||
    'bsinpsychology' ||
    'psychology' ||
    'bachelorofscienceinpsychology' => casPrograms[0],
    'bsit' ||
    'bsinformationtechnology' ||
    'bsininformationtechnology' ||
    'informationtechnology' ||
    'bachelorofinformationtechnology' ||
    'bachelorofscienceininformationtechnology' => casPrograms[1],
    'bsis' ||
    'bsinformationsystem' ||
    'bsinformationsystems' ||
    'bsininformationsystem' ||
    'bsininformationsystems' ||
    'informationsystem' ||
    'informationsystems' ||
    'bachelorofinformationsystem' ||
    'bachelorofinformationsystems' ||
    'bachelorofscienceininformationsystem' ||
    'bachelorofscienceininformationsystems' => casPrograms[2],
    'bss' ||
    'bsstat' ||
    'bsstats' ||
    'bsstatistics' ||
    'bsinstatistics' ||
    'statistics' ||
    'bachelorofscienceinstatistics' => casPrograms[3],
    _ => null,
  };
}

bool programAppliesTo(String? targetProgram, String? studentProgram) {
  final target = targetProgram?.trim() ?? '';
  if (target.isEmpty || target == 'All Programs') return true;

  final canonicalTarget = canonicalCasProgram(target);
  return canonicalTarget != null
      ? canonicalTarget == canonicalCasProgram(studentProgram)
      : target == studentProgram?.trim();
}
