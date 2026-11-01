import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../icons/flvp_icon.dart';
import '../../store/store_scope.dart';
import '../../widgets/controls.dart';
import '../../widgets/data_display.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';

/// 运行配置：展示上游 `setupAction.getProfileWithId` 解析合并后的最终配置文本。
/// 只读预览 + 复制，内容与内核实际吃到的完全一致。
class FlvpPreviewPage extends ConsumerStatefulWidget {
  const FlvpPreviewPage({super.key, required this.platform, required this.profile});

  final FlvpPlatform platform;
  final Profile profile;

  @override
  ConsumerState<FlvpPreviewPage> createState() => _FlvpPreviewPageState();
}

class _FlvpPreviewPageState extends ConsumerState<FlvpPreviewPage> {
  String? _text;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await ref
          .read(setupActionProvider.notifier)
          .getProfileWithId(widget.profile.id);
      if (!mounted) return;
      setState(() {
        _text = text;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _copy() async {
    final text = _text;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) FlvpStoreScope.read(context).notify('已复制运行配置');
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final lines = _text?.split('\n').length ?? 0;

    Widget body;
    if (_loading) {
      body = const Center(child: FlvpSpinner(size: 22));
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              FlvpIcon('TriangleAlert', size: 26, color: colors.warn),
              Text(
                '读取运行配置失败',
                style: flvpText(13.5, color: colors.ink),
              ),
              Text(
                '$_error',
                textAlign: TextAlign.center,
                style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
              ),
              FlvpButton(
                variant: FlvpButtonVariant.tonal,
                label: '重试',
                icon: const FlvpIcon('RefreshCw', size: 16),
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    } else {
      body = Container(
        decoration: BoxDecoration(
          color: colors.surf2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: FlvpThinScrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              _text ?? '',
              style: flvpText(12, weight: FontWeight.w400, height: 1.55, color: colors.ink, mono: true),
            ),
          ),
        ),
      );
    }

    return FlvpPageScaffold(
      title: '运行配置',
      subtitle: _loading
          ? widget.profile.realLabel
          : '${widget.profile.realLabel} · $lines 行',
      scrollable: false,
      actions: [
        FlvpIconButton(
          label: '重新生成',
          dimension: 40,
          onPressed: _loading ? null : _load,
          icon: const FlvpIcon('RefreshCw', size: 19),
        ),
        FlvpIconButton(
          label: '复制',
          dimension: 40,
          onPressed: _text == null ? null : _copy,
          icon: const FlvpIcon('Copy', size: 19),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: body,
      ),
    );
  }
}
