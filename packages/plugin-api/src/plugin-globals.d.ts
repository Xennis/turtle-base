// The globals a plugin may use beyond ECMAScript - what a sandbox will
// provide, nothing of the DOM. A plugin's tsconfig names this file in
// `types` (with `lib: ["ES2024"]`), the app never loads it.

interface URLSearchParams {
  append(name: string, value: string): void;
  delete(name: string): void;
  get(name: string): string | null;
  getAll(name: string): string[];
  has(name: string): boolean;
  set(name: string, value: string): void;
  toString(): string;
  [Symbol.iterator](): IterableIterator<[string, string]>;
}

declare var URLSearchParams: {
  prototype: URLSearchParams;
  new (init?: string | Readonly<Record<string, string>> | readonly (readonly [string, string])[]): URLSearchParams;
};

interface URL {
  hash: string;
  host: string;
  hostname: string;
  href: string;
  readonly origin: string;
  password: string;
  pathname: string;
  port: string;
  protocol: string;
  search: string;
  readonly searchParams: URLSearchParams;
  username: string;
  toString(): string;
  toJSON(): string;
}

declare var URL: {
  prototype: URL;
  new (url: string | URL, base?: string | URL): URL;
  canParse(url: string | URL, base?: string | URL): boolean;
  parse(url: string | URL, base?: string | URL): URL | null;
};

interface AbortSignal {
  readonly aborted: boolean;
  readonly reason: unknown;
  throwIfAborted(): void;
}

declare var AbortSignal: {
  prototype: AbortSignal;
  abort(reason?: unknown): AbortSignal;
  any(signals: readonly AbortSignal[]): AbortSignal;
  timeout(milliseconds: number): AbortSignal;
};

interface AbortController {
  readonly signal: AbortSignal;
  abort(reason?: unknown): void;
}

declare var AbortController: { prototype: AbortController; new (): AbortController };

interface TextEncoder {
  encode(input?: string): Uint8Array;
}

declare var TextEncoder: { prototype: TextEncoder; new (): TextEncoder };

interface TextDecoder {
  decode(input?: Uint8Array): string;
}

declare var TextDecoder: { prototype: TextDecoder; new (label?: string): TextDecoder };

declare function setTimeout(handler: () => void, timeout?: number): number;
declare function clearTimeout(id: number | undefined): void;

declare var console: {
  debug(...data: unknown[]): void;
  info(...data: unknown[]): void;
  log(...data: unknown[]): void;
  warn(...data: unknown[]): void;
  error(...data: unknown[]): void;
};
