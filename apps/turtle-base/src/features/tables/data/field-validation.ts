/** Value checks of the base field types (see base-field-type.ts). */

/** A number as typed in - JSON-like, so no empty text, no `NaN`. */
export function parseNumber(text: string): number | undefined {
  const trimmed = text.trim();
  if (trimmed.length === 0) return undefined;
  const value = Number(trimmed);
  return Number.isNaN(value) ? undefined : value;
}

export function isValidNumber(text: string): boolean {
  return parseNumber(text) !== undefined;
}

const isoDate =
  /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2})(?::(\d{2})(?::(\d{2})(?:[.,](\d{1,9}))?)?)?\s*(Z|[+-]\d{2}:?\d{2})?)?$/i;

/**
 * The canonical form of an ISO-8601 date as the date field stores it:
 * `yyyy-MM-dd` for a plain date (a time of midnight counts as none), else
 * `yyyy-MM-ddTHH:mm:ss.SSS` - with `Z` when the input had a zone, converted
 * to UTC. Undefined for anything else, including dates that don't exist.
 *
 * A string rather than a `Date`, which would read a plain date as UTC
 * midnight and shift it a day in some time zones.
 */
export function parseIsoDate(text: string): string | undefined {
  const match = isoDate.exec(text.trim());
  if (match === null) return undefined;
  const [, y = '', mo = '', d = '', h = '0', mi = '0', s = '0', fraction = '', zone] = match;
  const year = Number(y);
  const month = Number(mo);
  const day = Number(d);
  const hour = Number(h);
  const minute = Number(mi);
  const second = Number(s);
  const millis = Number(fraction.padEnd(3, '0').slice(0, 3));
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth || hour > 23 || minute > 59 || second > 59) {
    return undefined;
  }
  const date = `${y}-${mo}-${d}`;
  if (hour === 0 && minute === 0 && second === 0 && millis === 0) return date;
  const time = `${pad(hour)}:${pad(minute)}:${pad(second)}.${String(millis).padStart(3, '0')}`;
  if (zone === undefined) return `${date}T${time}`;
  return new Date(`${date}T${time}${zone.toUpperCase() === 'Z' ? 'Z' : normalizeOffset(zone)}`).toISOString();
}

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

function normalizeOffset(zone: string): string {
  return zone.includes(':') ? zone : `${zone.slice(0, 3)}:${zone.slice(3)}`;
}
