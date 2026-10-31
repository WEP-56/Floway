import 'package:floway/enum/enum.dart';
import 'package:floway/l10n/l10n.dart';
import 'package:floway/manager/status_manager.dart';
import 'package:floway/models/state.dart';
import 'package:material_ui/material_ui.dart';

extension AppContextExtension on BuildContext {
  void showNotifier(
    String text, {
    MessageLevel level = MessageLevel.info,
    MessageActionState? actionState,
  }) {
    return findAncestorStateOfType<StatusManagerState>()?.message(
      text,
      level: level,
      actionState: actionState,
    );
  }

  AppLocalizations get appLocalizations => AppLocalizations.of(this);
}
