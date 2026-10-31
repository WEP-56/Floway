import 'package:floway/common/common.dart';
import 'package:floway/ui/icons/icons.dart';
import 'package:floway/ui/ui.dart';
import 'package:floway/views/config/filters.dart';
import 'package:floway/views/config/icon_sets.dart';
import 'package:floway/views/config/providers.dart';
import 'package:floway/views/profiles/custom/custom_proxies.dart';
import 'package:material_ui/material_ui.dart';

class CustomResourcesView extends StatelessWidget {
  const CustomResourcesView({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final items = [
      ListItem.open(
        title: Text(appLocalizations.proxies),
        leading: const GlyphIcon(AppGlyphs.proxies),
        widget: const CustomProxiesView(),
      ),
      ListItem.open(
        title: Text(appLocalizations.ruleProviders),
        leading: const GlyphIcon(AppGlyphs.resources),
        widget: const ClashProvidersView(),
      ),
      ListItem.open(
        title: Text(appLocalizations.filters),
        leading: const GlyphIcon(AppGlyphs.filter),
        widget: const FiltersView(),
      ),
      ListItem.open(
        title: Text(appLocalizations.iconSets),
        leading: const GlyphIcon(AppGlyphs.photos),
        widget: const IconSetsView(),
      ),
    ];
    return BaseScaffold(
      title: appLocalizations.customProfileResources,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: [generateSection(items: items)],
      ),
    );
  }
}
