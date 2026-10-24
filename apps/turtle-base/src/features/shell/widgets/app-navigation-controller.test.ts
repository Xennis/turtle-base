import { beforeEach, expect, test } from 'vite-plus/test';

import { AppNavigationController } from './app-navigation-controller.ts';

let navigation: AppNavigationController;

beforeEach(() => {
  navigation = new AppNavigationController();
});

test('selecting a space clears the content selection', () => {
  navigation.selectSpace('s1');
  navigation.selectCollection('c1');
  navigation.showSettings();

  navigation.selectSpace('s2');

  expect(navigation.state).toMatchObject({
    selectedSpaceId: 's2',
    selectedCollectionId: undefined,
    isShowingSettings: false,
  });
});

test('a collection and a page replace each other and leave edit mode', () => {
  navigation.selectSpace('s1');
  navigation.selectCollection('c1');
  navigation.startEditingCollection();

  navigation.selectPage('p1');

  expect(navigation.state).toMatchObject({
    selectedSpaceId: 's1',
    selectedCollectionId: undefined,
    selectedPageId: 'p1',
    isEditingCollection: false,
  });
});

test('overlay pages keep the selection underneath', () => {
  navigation.selectSpace('s1');
  navigation.selectPage('p1');

  navigation.showPlugins();
  expect(navigation.isShowingOverlayPage).toBe(true);
  navigation.showSettings();
  expect(navigation.state).toMatchObject({ isShowingSettings: true, isShowingPlugins: false });

  navigation.hideSettings();
  expect(navigation.isShowingOverlayPage).toBe(false);
  expect(navigation.state.selectedPageId).toBe('p1');
});

test('openSpace leaves an overlay page also for the selected space', () => {
  navigation.selectSpace('s1');
  navigation.showPlugins();

  navigation.openSpace('s1');

  expect(navigation.isShowingOverlayPage).toBe(false);
});

test('edit mode needs a collection', () => {
  navigation.startEditingCollection();

  expect(navigation.state.isEditingCollection).toBe(false);
});

test('each change is a new snapshot and notifies', () => {
  let notified = 0;
  navigation.subscribe(() => notified++);
  const before = navigation.state;

  navigation.selectSpace('s1');
  navigation.selectSpace('s1');

  expect(navigation.state).not.toBe(before);
  expect(notified).toBe(1);
});
