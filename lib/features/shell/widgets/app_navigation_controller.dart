import 'package:flutter/foundation.dart';

/// What the main content area currently shows. Selecting a collection
/// or page clears the other and leaves edit mode. Page-View doesn't
/// exist yet (later phases) - the shell only tracks the selection for
/// that case.
class AppNavigationController extends ChangeNotifier {
  String? _selectedCollectionId;
  String? _selectedPageId;
  bool _isEditingCollection = false;

  String? get selectedCollectionId => _selectedCollectionId;
  String? get selectedPageId => _selectedPageId;
  bool get isEditingCollection => _isEditingCollection;

  void selectCollection(String id) {
    _selectedCollectionId = id;
    _selectedPageId = null;
    _isEditingCollection = false;
    notifyListeners();
  }

  void selectPage(String id) {
    _selectedPageId = id;
    _selectedCollectionId = null;
    _isEditingCollection = false;
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
}
