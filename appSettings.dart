import 'package:flutter/material.dart';
import 'package:nbt_app/utilities/secure_storage/secure_storage.dart';

class AppSettings with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light; // Set default value
  Locale _locale = const Locale('fa'); // Set default value

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;

  // Async initialization method
  Future<void> initialize() async {
    _themeMode = await getSavedThemeMode(); // Assign value fetched from storage
    _locale = await getSavedLocale(); // Assign value fetched from storage
    notifyListeners(); // Notify listeners after initialization
  }

  void toggleThemeMode() {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    SecureStorageMethods.saveToStorage('theme_mode', _themeMode == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  void changeLocale(Locale locale) {
    _locale = locale;
    SecureStorageMethods.saveToStorage('locale', locale.languageCode);
    notifyListeners();
  }
}

Future<Locale> getSavedLocale() async {
  var savedLocale = await SecureStorageMethods.getFromStorage('locale');
  if (savedLocale != null) {
    return savedLocale == 'fa' ? const Locale('fa') : const Locale('en');
  } else {
    return const Locale('fa'); // Default value
  }
}

Future<ThemeMode> getSavedThemeMode() async {
  var savedThemeMode = await SecureStorageMethods.getFromStorage('theme_mode');
  if (savedThemeMode != null) {
    return savedThemeMode == 'light' ? ThemeMode.light : ThemeMode.dark;
  } else {
    return ThemeMode.light; // Default value
  }
}
