import type { Hlc } from './hlc.ts';

/**
 * This node's canonical time: the newest timestamp it has written or merged.
 * Every local write takes the next one, so timestamps only ever grow.
 */
export class CrdtClock {
  #canonicalTime: Hlc;

  constructor(canonicalTime: Hlc) {
    this.#canonicalTime = canonicalTime;
  }

  get canonicalTime(): Hlc {
    return this.#canonicalTime;
  }

  get nodeId(): string {
    return this.#canonicalTime.nodeId;
  }

  /** The timestamp for a local write. */
  next(): Hlc {
    this.#canonicalTime = this.#canonicalTime.increment();
    return this.#canonicalTime;
  }

  /** Moves the clock forward to `hlc` (e.g. after a merge) if it's newer. */
  observe(hlc: Hlc): void {
    if (hlc.compare(this.#canonicalTime) > 0) this.#canonicalTime = hlc.withNodeId(this.nodeId);
  }
}
