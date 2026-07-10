import 'package:flutter/foundation.dart';

/// What the main content area currently shows. Selecting a collection
/// clears any selected page and vice versa. Neither Collection-View nor
/// Page-View exist yet (later phases) - the shell only tracks the
/// selection for now.
class AppNavigationController extends ChangeNotifier {
  String? _selectedCollectionId;
  String? _selectedPageId;

  String? get selectedCollectionId => _selectedCollectionId;
  String? get selectedPageId => _selectedPageId;

  void selectCollection(String id) {
    _selectedCollectionId = id;
    _selectedPageId = null;
    notifyListeners();
  }

  void selectPage(String id) {
    _selectedPageId = id;
    _selectedCollectionId = null;
    notifyListeners();
  }
}
