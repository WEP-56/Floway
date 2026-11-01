import 'dart:async';

import 'package:floway/common/common.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../design/tokens.dart';
import '../../icons/flvp_icon.dart';
import '../../widgets/controls.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';

/// 字体与字号：系统字体族与文字缩放，写上游 `themeSettingProvider`
/// （`ThemeProps.fontFamily` / `ThemeProps.textScale`）。替换上游 `FontFamilyView`。
class FlvpFontPage extends ConsumerStatefulWidget {
  const FlvpFontPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpFontPage> createState() => _FlvpFontPageState();
}

class _FlvpFontPageState extends ConsumerState<FlvpFontPage> {
  List<String>? _installed;

  static const _scalePresets = <double>[
    0.85,
    0.9,
    0.95,
    1.0,
    1.05,
    1.1,
    1.15,
    1.2,
    1.25,
    1.3,
    1.4,
    1.5,
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final families = await loadSystemFontFamilies();
    if (mounted) setState(() => _installed = families);
  }

  void _setTheme(ThemeProps Function(ThemeProps state) apply) {
    ref.read(themeSettingProvider.notifier).update(apply);
  }

  void _pickFont() {
    final host = FlvpModalHost.of(context);
    final installed = _installed ?? const <String>[];
    final current = ref.read(themeSettingProvider).fontFamily;
    var query = '';
    host.show(
      (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final colors = FlvpThemeScope.colorsOf(context);
          final keyword = query.trim().toLowerCase();
          final visible = [
            for (final family in installed)
              if (keyword.isEmpty || family.toLowerCase().contains(keyword))
                family,
          ];
          void choose(String? family) {
            _setTheme((state) => state.copyWith(fontFamily: family));
            host.close();
          }

          return FlvpModal(
            platform: widget.platform,
            title: '字体',
            subtitle: installed.isEmpty && _installed == null
                ? '正在读取系统字体…'
                : '选择界面使用的字体族',
            onClose: host.close,
            child: SizedBox(
              width: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: colors.surf2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        FlvpIcon('Search', size: 15, color: colors.ink3),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (value) =>
                                setModalState(() => query = value),
                            style: flvpText(13.5, color: colors.ink),
                            cursorColor: colors.primary,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: '搜索字体',
                              hintStyle: flvpText(13.5, color: colors.ink3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        _fontTile(
                          colors,
                          label: '系统默认',
                          selected: current == null,
                          onTap: () => choose(null),
                        ),
                        for (final family in visible)
                          _fontTile(
                            colors,
                            label: family,
                            family: family,
                            selected: current == family,
                            onTap: () => choose(family),
                          ),
                        if (visible.isEmpty && installed.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                '没有匹配的字体',
                                style: flvpText(13.5, color: colors.ink3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fontTile(
    FlvpColors colors, {
    required String label,
    String? family,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: flvpText(
                  14,
                  color: selected ? colors.primary : colors.ink,
                ).copyWith(fontFamily: family),
              ),
            ),
            if (selected)
              FlvpIcon('Check', size: 18, color: colors.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _pickScale(double current) async {
    final next = await showFlvpOptionsPrompt<double>(
      context: context,
      platform: widget.platform,
      title: '字号缩放',
      subtitle: '相对系统默认字号的缩放比例',
      value: current,
      options: [
        for (final value in _scalePresets)
          FlvpRadioOption(value, '${(value * 100).round()}%'),
      ],
    );
    if (next == null || next == current) return;
    _setTheme(
      (state) =>
          state.copyWith(textScale: state.textScale.copyWith(scale: next)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final theme = ref.watch(themeSettingProvider);
    final scale = theme.textScale;
    return FlvpPageScaffold(
      title: '字体与字号',
      subtitle: '界面字体族与文字缩放',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlvpSettingsSection(
            title: '字体',
            footer: '读取系统已安装的字体；选择后立即应用到界面文字。',
            children: [
              FlvpSettingsLink(
                icon: 'Palette',
                title: '字体族',
                subtitle: theme.fontFamily ?? '系统默认',
                onTap: _pickFont,
              ),
            ],
          ),
          FlvpSettingsSection(
            title: '字号',
            footer: '缩放仅影响界面文字，不改变内核与系统设置。',
            children: [
              FlvpSettingsToggle(
                icon: 'Gauge',
                title: '自定义字号',
                subtitle: '按下面的比例放大或缩小界面文字',
                value: scale.enable,
                onChanged: (value) => _setTheme(
                  (state) =>
                      state.copyWith(textScale: state.textScale.copyWith(enable: value)),
                ),
              ),
              if (scale.enable)
                FlvpSettingsRow(
                  icon: 'Gauge',
                  title: '缩放比例',
                  subtitle: '当前 ${(scale.scale * 100).round()}%',
                  onTap: () => _pickScale(scale.scale),
                  trailing: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 180,
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                          activeTrackColor: colors.primary,
                          inactiveTrackColor: colors.surf3,
                          thumbColor: colors.primary,
                        ),
                        child: Slider(
                          value: scale.scale.clamp(0.85, 1.5),
                          min: 0.85,
                          max: 1.5,
                          divisions: 26,
                          onChanged: (value) => _setTheme(
                            (state) => state.copyWith(
                              textScale: state.textScale.copyWith(
                                scale: (value * 20).round() / 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
