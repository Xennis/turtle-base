/**
 * Like Flutter's `ChangeNotifier`: state that tells listeners when it
 * changed. `subscribe` fits React's `useSyncExternalStore`, which reads the
 * state again after each notification.
 */
export class Notifier {
  readonly #listeners = new Set<() => void>();

  /** Returns the function that unsubscribes `listener` again. */
  readonly subscribe = (listener: () => void): (() => void) => {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  };

  protected notify(): void {
    for (const listener of this.#listeners) listener();
  }
}
