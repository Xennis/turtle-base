import { Notifier } from '../../../core/notifier.ts';

export interface NavigationState {
  readonly selectedSpaceId: string | undefined;
  readonly selectedCollectionId: string | undefined;
  readonly selectedPageId: string | undefined;
  readonly isEditingCollection: boolean;
  readonly isShowingSettings: boolean;
  readonly isShowingPlugins: boolean;
}

const initial: NavigationState = {
  selectedSpaceId: undefined,
  selectedCollectionId: undefined,
  selectedPageId: undefined,
  isEditingCollection: false,
  isShowingSettings: false,
  isShowingPlugins: false,
};

/**
 * What the sidebar and main content area currently show. Selecting a space
 * clears the content selection (a different area, different content).
 * Selecting a collection or page clears the other and leaves edit mode.
 *
 * Each change replaces {@link state} with a new object, so React reads it as
 * a snapshot (`useSyncExternalStore(navigation.subscribe, () => navigation.state)`).
 */
export class AppNavigationController extends Notifier {
  #state = initial;

  get state(): NavigationState {
    return this.#state;
  }

  /** Settings or Plugins - pages shown on top of the selection. */
  get isShowingOverlayPage(): boolean {
    return this.#state.isShowingSettings || this.#state.isShowingPlugins;
  }

  selectSpace(id: string): void {
    if (id === this.#state.selectedSpaceId) return;
    this.#set({ ...initial, selectedSpaceId: id });
  }

  selectCollection(id: string): void {
    this.#set({ ...initial, selectedSpaceId: this.#state.selectedSpaceId, selectedCollectionId: id });
  }

  selectPage(id: string): void {
    this.#set({ ...initial, selectedSpaceId: this.#state.selectedSpaceId, selectedPageId: id });
  }

  /** Shows a space even if it's already the selected one - leaving any overlay page, e.g. after adding a plugin. */
  openSpace(id: string): void {
    if (id === this.#state.selectedSpaceId) {
      this.#set({ ...this.#state, isShowingSettings: false, isShowingPlugins: false });
    } else {
      this.selectSpace(id);
    }
  }

  /**
   * Shows the Settings page in the content area - an overlay on top of
   * whatever was selected, not a replacement for it, so closing it returns to
   * exactly where you were.
   */
  showSettings(): void {
    this.#set({ ...this.#state, isShowingSettings: true, isShowingPlugins: false });
  }

  hideSettings(): void {
    this.#set({ ...this.#state, isShowingSettings: false });
  }

  /** Shows the Plugins page - an overlay like {@link showSettings}. */
  showPlugins(): void {
    this.#set({ ...this.#state, isShowingPlugins: true, isShowingSettings: false });
  }

  hidePlugins(): void {
    this.#set({ ...this.#state, isShowingPlugins: false });
  }

  /** Shows the collection's edit page instead of its view, in the same content area. */
  startEditingCollection(): void {
    if (this.#state.selectedCollectionId === undefined) return;
    this.#set({ ...this.#state, isEditingCollection: true });
  }

  stopEditingCollection(): void {
    this.#set({ ...this.#state, isEditingCollection: false });
  }

  /**
   * Clears the content-area selection, leaving the space selected - e.g. when
   * the open collection or page has just been deleted.
   */
  clearSelection(): void {
    this.#set({
      ...this.#state,
      selectedCollectionId: undefined,
      selectedPageId: undefined,
      isEditingCollection: false,
    });
  }

  #set(state: NavigationState): void {
    this.#state = state;
    this.notify();
  }
}
