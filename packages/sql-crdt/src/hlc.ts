const maxCounter = 0xffff;
const maxDriftMs = 60_000;
const pattern = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)-([0-9A-F]{4})-(.+)$/;

/**
 * A hybrid logical clock timestamp: wall time plus a counter for events in
 * the same millisecond, plus the node that made it. Trades time precision
 * for a clock that never goes backwards across devices.
 * Inspiration: https://cse.buffalo.edu/tech-reports/2014-04.pdf
 *
 * Ported from Dart's `crdt` package, with millisecond instead of microsecond
 * precision. The string form has a fixed width, so comparing two strings
 * orders them like {@link Hlc.compare} - SQL relies on that for `modified > ?`
 * and `max(modified)`.
 */
export class Hlc {
  /** Wall time in milliseconds since the epoch. */
  readonly millis: number;
  readonly counter: number;
  readonly nodeId: string;

  constructor(millis: number, counter: number, nodeId: string) {
    if (!Number.isInteger(millis) || millis < 0) throw new RangeError(`Invalid HLC time: ${millis}`);
    if (!Number.isInteger(counter) || counter < 0 || counter > maxCounter) throw new OverflowError(counter);
    this.millis = millis;
    this.counter = counter;
    this.nodeId = nodeId;
  }

  /** The beginning of time and space: January 1, 1970. */
  static zero(nodeId: string): Hlc {
    return new Hlc(0, 0, nodeId);
  }

  static now(nodeId: string, wallTime = Date.now()): Hlc {
    return new Hlc(wallTime, 0, nodeId);
  }

  /** Parses the form {@link Hlc.toString} writes: `<ISO time>-<counter>-<node id>`. */
  static parse(timestamp: string): Hlc {
    const match = pattern.exec(timestamp);
    if (match === null) throw new SyntaxError(`Invalid HLC: ${timestamp}`);
    const [, iso = '', counter = '', nodeId = ''] = match;
    return new Hlc(Date.parse(iso), Number.parseInt(counter, 16), nodeId);
  }

  withNodeId(nodeId: string): Hlc {
    return new Hlc(this.millis, this.counter, nodeId);
  }

  /** The next timestamp of this node, for a local change. */
  increment(wallTime = Date.now()): Hlc {
    // The logical time never goes backwards; the counter tells apart events
    // within the same millisecond.
    const millis = Math.max(wallTime, this.millis);
    const counter = millis === this.millis ? this.counter + 1 : 0;
    if (millis - wallTime > maxDriftMs) throw new ClockDriftError(millis, wallTime);
    if (counter > maxCounter) throw new OverflowError(counter);
    return new Hlc(millis, counter, this.nodeId);
  }

  /**
   * Takes in a timestamp from another node, so this node's clock stays ahead
   * of everything it has seen.
   */
  merge(remote: Hlc, wallTime = Date.now()): Hlc {
    if (remote.millis < this.millis || (remote.millis === this.millis && remote.counter <= this.counter)) return this;
    if (remote.nodeId === this.nodeId) throw new DuplicateNodeError(this.nodeId);
    if (remote.millis - wallTime > maxDriftMs) throw new ClockDriftError(remote.millis, wallTime);
    return remote.withNodeId(this.nodeId);
  }

  compare(other: Hlc): number {
    if (this.millis !== other.millis) return this.millis - other.millis;
    if (this.counter !== other.counter) return this.counter - other.counter;
    if (this.nodeId === other.nodeId) return 0;
    return this.nodeId < other.nodeId ? -1 : 1;
  }

  equals(other: Hlc): boolean {
    return this.compare(other) === 0;
  }

  toString(): string {
    const counter = this.counter.toString(16).toUpperCase().padStart(4, '0');
    return `${new Date(this.millis).toISOString()}-${counter}-${this.nodeId}`;
  }

  toJSON(): string {
    return this.toString();
  }
}

export class ClockDriftError extends Error {
  override readonly name = 'ClockDriftError';

  constructor(millis: number, wallTime: number) {
    super(`Clock drift of ${millis - wallTime} ms exceeds maximum (${maxDriftMs} ms)`);
  }
}

export class OverflowError extends Error {
  override readonly name = 'OverflowError';

  constructor(counter: number) {
    super(`Timestamp counter overflow: ${counter}`);
  }
}

export class DuplicateNodeError extends Error {
  override readonly name = 'DuplicateNodeError';

  constructor(nodeId: string) {
    super(`Duplicate node: ${nodeId}`);
  }
}
