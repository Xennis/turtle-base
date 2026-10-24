/** How many bytes {@link sniffMimeType} looks at. */
export const sniffLength = 32;

interface Signature {
  readonly type: string;
  readonly offset?: number;
  readonly bytes: readonly number[];
}

const ascii = (text: string) => [...new TextEncoder().encode(text)];

const signatures: readonly Signature[] = [
  { type: 'application/pdf', bytes: ascii('%PDF-') },
  { type: 'image/png', bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] },
  { type: 'image/jpeg', bytes: [0xff, 0xd8, 0xff] },
  { type: 'image/gif', bytes: ascii('GIF87a') },
  { type: 'image/gif', bytes: ascii('GIF89a') },
  { type: 'image/bmp', bytes: ascii('BM') },
  { type: 'image/tiff', bytes: [0x49, 0x49, 0x2a, 0x00] },
  { type: 'image/tiff', bytes: [0x4d, 0x4d, 0x00, 0x2a] },
  { type: 'application/zip', bytes: [0x50, 0x4b, 0x03, 0x04] },
  { type: 'audio/flac', bytes: ascii('fLaC') },
  { type: 'audio/ogg', bytes: ascii('OggS') },
  { type: 'audio/mpeg', bytes: ascii('ID3') },
  { type: 'font/woff', bytes: ascii('wOFF') },
  { type: 'font/woff2', bytes: ascii('wOF2') },
];

/** ISO base media files (`ftyp` box) by their major brand. */
const ftypBrands: Readonly<Record<string, string>> = {
  heic: 'image/heic',
  heix: 'image/heic',
  mif1: 'image/heif',
  avif: 'image/avif',
  'qt  ': 'video/quicktime',
  isom: 'video/mp4',
  iso2: 'video/mp4',
  mp41: 'video/mp4',
  mp42: 'video/mp4',
  avc1: 'video/mp4',
  'M4A ': 'audio/mp4',
};

/**
 * The MIME type the content's first bytes ("magic number") reveal, undefined
 * when they reveal none - then the name's extension decides. From the content
 * first, so a renamed file can't pass for another type.
 */
export function sniffMimeType(head: Uint8Array): string | undefined {
  const matches = (bytes: readonly number[], offset = 0) => bytes.every((byte, i) => head[offset + i] === byte);
  const riff = matches(ascii('RIFF'));
  if (riff && matches(ascii('WEBP'), 8)) return 'image/webp';
  if (riff && matches(ascii('WAVE'), 8)) return 'audio/wav';
  if (matches(ascii('ftyp'), 4)) {
    const brand = String.fromCharCode(...head.slice(8, 12));
    return ftypBrands[brand];
  }
  return signatures.find((signature) => matches(signature.bytes, signature.offset))?.type;
}
