// The archive workflow keys records by two consecutive calendar years.
export function validAcademicYear(value) {
  const years = typeof value === 'string' && /^(\d{4})-(\d{4})$/.exec(value);
  return Boolean(years && Number(years[2]) === Number(years[1]) + 1);
}

﻿// The date is the UTC instant of midnight in the placement's local zone.
export function creditedHours(record) {
  const start = record.timeIn?.toMillis?.();
  const end = record.timeOut?.toMillis?.();
  const midnight = record.date?.toMillis?.();
  const next = record.workDayEnd?.toMillis?.() ?? midnight + 86400000;
  const pause = record.breakMinutes;
  const elapsed = Math.floor((end - start) / 60000);
  if (
    next - midnight > 25 * 3600000 ||
    !(midnight <= start && start < end && end < next && end <= Date.now()) ||
    record.attendanceState === 'in_progress' ||
    !record.academicYear?.trim() ||
    !Number.isInteger(pause) ||
    pause < 0 ||
    pause >= elapsed
  )
    return 0;
  return (elapsed - pause) / 60;
}
