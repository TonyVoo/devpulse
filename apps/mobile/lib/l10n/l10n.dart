import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

/// Languages the app ships (English is the source and the fallback).
const supportedAppLocales = AppLocalizations.supportedLocales;

AppLocalizations _current = lookupAppLocalizations(const Locale('en'));

/// Strings for code without a BuildContext (domain labels, failures, sync notices).
/// Kept in step with the app's active locale by [syncL10nLocale].
AppLocalizations get l10n => _current;

/// Called from `MaterialApp.builder` whenever the resolved locale changes.
void syncL10nLocale(Locale locale) {
  final supported = AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode);
  _current = lookupAppLocalizations(supported ? Locale(locale.languageCode) : const Locale('en'));
}

extension L10nContext on BuildContext {
  /// Strings in the widget tree's language; English where no localizations are installed
  /// (bare widget tests).
  AppLocalizations get l10n => AppLocalizations.of(this) ?? _current;
}
