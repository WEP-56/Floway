import 'package:floway/models/profile.dart';
import 'package:floway/pages/editor.dart';
import 'package:floway/providers/action.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PreviewProfileView extends ConsumerWidget {
  final Profile profile;

  const PreviewProfileView({super.key, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EditorPage(
      title: profile.realLabel,
      load: () async => CodeForgeDocument.fromText(
        await ref
            .read(setupActionProvider.notifier)
            .getProfileWithId(profile.id),
      ),
    );
  }
}
