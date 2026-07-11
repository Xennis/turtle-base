import 'package:flutter/foundation.dart';

/// What the sidebar and main content area currently show. Selecting a
/// space clears the content selection (a different area, different
/// content). Selecting a collection or page clears the other and
/// leaves edit mode. Page-View doesn't exist yet (later phases) - the
/// shell only tracks the selection for that case.
class AppNavigationController extends ChangeNotifier {
  String? _selectedSpaceId;
  String? _selectedCollectionId;
  String? _selectedPageId;
  bool _isEditingCollection = false;
  bool _isShowingSettings = false;

  String? get selectedSpaceId => _selectedSpaceId;
  String? get selectedCollectionId => _selectedCollectionId;
  String? get selectedPageId => _selectedPageId;
  bool get isEditingCollection => _isEditingCollection;
  bool get isShowingSettings => _isShowingSettings;

  void selectSpace(String id) {
    if (id == _selectedSpaceId) return;
    _selectedSpaceId = id;
    _selectedCollectionId = null;
    _selectedPageId = null;
    _isEditingCollection = false;
    _isShowingSettings = false;
    notifyListeners();
  }

  void selectCollection(String id) {
    _selectedCollectionId = id;
    _selectedPageId = null;
    _isEditingCollection = false;
    _isShowingSettings = false;
    notifyListeners();
  }

  void selectPage(String id) {
    _selectedPageId = id;
    _selectedCollectionId = null;
    _isEditingCollection = false;
    _isShowingSettings = false;
    notifyListeners();
  }

  /// Shows SettingsPage in the same content area (see
  /// AppShell/_MainContent), like [startEditingCollection] - an overlay
  /// on top of whatever was selected, not a replacement for it, so
  /// closing Settings returns to exactly where you were.
  void showSettings() {
    _isShowingSettings = true;
    notifyListeners();
  }

  void hideSettings() {
    _isShowingSettings = false;
    notifyListeners();
  }

  /// Shows CollectionEditPage instead of CollectionView for the
  /// currently selected collection, in the same content area (so the
  /// sidebar stays visible) rather than a pushed route.
  void startEditingCollection() {
    if (_selectedCollectionId == null) return;
    _isEditingCollection = true;
    notifyListeners();
  }

  void stopEditingCollection() {
    _isEditingCollection = false;
    notifyListeners();
  }

  /// Clears the content-area selection, leaving the space selection
  /// untouched - used when the currently open collection/page has just
  /// been deleted, since nothing in the sidebar disappearing on its own
  /// clears this (Collections-/PagesRepository.watchById aren't
  /// filtered by deletedAt, unlike the sidebar's list streams).
  void clearSelection() {
    _selectedCollectionId = null;
    _selectedPageId = null;
    _isEditingCollection = false;
    notifyListeners();
  }
}
