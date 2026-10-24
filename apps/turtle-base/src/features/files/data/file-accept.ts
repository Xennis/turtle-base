import mime from 'mime';

const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tif', 'tiff', 'svg'];

/**
 * Which files a files field takes, in the syntax of HTML's `accept`
 * attribute: MIME types (`application/pdf`), MIME wildcards (`image/*`) and
 * extensions (`.xml`). Empty takes any file.
 */
export class FileAccept {
  static readonly any = new FileAccept([]);
  static readonly images = new FileAccept(['image/*']);
  static readonly pdf = new FileAccept(['application/pdf']);

  readonly patterns: readonly string[];

  constructor(patterns: readonly string[]) {
    this.patterns = patterns;
  }

  /** Parses a comma-separated list, as typed into the field settings. */
  static parse(text: string): FileAccept {
    return new FileAccept(
      text
        .split(',')
        .map((part) => part.trim().toLowerCase())
        .filter((pattern) => pattern.length > 0),
    );
  }

  get isAny(): boolean {
    return this.patterns.length === 0;
  }

  /** Whether a file of `mimeType` named `fileName` fits. */
  accepts(file: { mimeType: string; fileName: string }): boolean {
    if (this.isAny) return true;
    const type = file.mimeType.toLowerCase();
    const extension = extensionOf(file.fileName);
    return this.patterns.some((pattern) => {
      if (pattern.startsWith('.')) return extension === pattern;
      if (pattern.endsWith('/*')) return type.startsWith(pattern.slice(0, -1));
      return type === pattern;
    });
  }

  /**
   * Only image types - so the file dialog can offer the platform's image
   * picker (e.g. the gallery on Android).
   */
  get isImagesOnly(): boolean {
    return !this.isAny && this.patterns.every((pattern) => pattern.startsWith('image/'));
  }

  /**
   * Extensions (without dot) for the file dialog's filter, undefined for no
   * filter - when {@link isAny}, or when a wildcard other than image/* can't
   * be listed as extensions.
   */
  get dialogExtensions(): string[] | undefined {
    if (this.isAny) return undefined;
    const extensions = new Set<string>();
    for (const pattern of this.patterns) {
      if (pattern.startsWith('.')) {
        extensions.add(pattern.slice(1));
      } else if (pattern === 'image/*') {
        for (const extension of imageExtensions) extensions.add(extension);
      } else if (pattern.endsWith('/*')) {
        return undefined;
      } else {
        const extension = mime.getExtension(pattern);
        if (extension !== null) extensions.add(extension);
      }
    }
    return extensions.size === 0 ? undefined : [...extensions];
  }

  toText(): string {
    return this.patterns.join(', ');
  }

  equals(other: FileAccept): boolean {
    return other.patterns.length === this.patterns.length && other.patterns.every((p) => this.patterns.includes(p));
  }
}

/** The lowercased extension with its dot, e.g. `.pdf` - empty if there is none. */
function extensionOf(fileName: string): string {
  const name = fileName.slice(fileName.lastIndexOf('/') + 1);
  const dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.slice(dot).toLowerCase();
}
