import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:floway/common/common.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/pages/editor.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/ui/navigator.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/motion.dart';
import '../../design/theme_scope.dart';
import '../../design/tokens.dart';
import '../../icons/flvp_icon.dart';
import '../../store/store_scope.dart';
import '../../widgets/controls.dart';
import '../../widgets/data_display.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/ripple.dart';

/// 脚本：本地/远程脚本的增删改、导入、排序与同步，读写上游 `scriptsProvider`
/// 与 `scriptsActionProvider`；编辑复用上游 `EditorPage` 与 JS 模板。
class FlvpScriptsPage extends ConsumerStatefulWidget {
  const FlvpScriptsPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpScriptsPage> createState() => _FlvpScriptsPageState();
}

class _FlvpScriptsPageState extends ConsumerState<FlvpScriptsPage> {
  late final ScriptsAction _action;

  @override
  void initState() {
    super.initState();
    _action = ref.read(scriptsActionProvider.notifier);
  }

  List<Script> get _scripts => ref.read(scriptsProvider).value ?? const [];

  void _toast(String message) => FlvpStoreScope.read(context).notify(message);

  Future<void> _delete(Script script) async {
    final ok = await showFlvpConfirm(
      context: context,
      platform: widget.platform,
      title: '删除脚本',
      message: '确定删除「${script.label}」吗？',
      confirmLabel: '删除',
      danger: true,
    );
    if (ok != true || !mounted) return;
    ref.read(scriptsProvider.notifier).del(script.id);
    unawaited(_clearEffect(script.id));
  }

  Future<void> _clearEffect(int id) async {
    final path = await appPath.getScriptPath(id.toString());
    await File(path).safeDelete();
  }

  Future<void> _sync(Script script) async {
    await globalState.safeRun(
      () => _action.updateScript(script),
      title: script.label,
    );
  }

  Future<void> _editUrl(Script script) async {
    final url = await showFlvpTextPrompt(
      context: context,
      platform: widget.platform,
      title: '脚本地址',
      subtitle: '远程脚本会从这个地址同步',
      value: script.url ?? '',
      placeholder: 'https://',
      validator: (value) {
        final uri = Uri.tryParse(value);
        if (value.isEmpty || uri == null || !uri.isAbsolute) {
          return '请输入有效的地址';
        }
        return null;
      },
    );
    if (url == null || url == script.url) return;
    await _sync(script.copyWith(url: url));
  }

  Future<String?> _promptName({Script? script}) async {
    return showFlvpTextPrompt(
      context: context,
      platform: widget.platform,
      title: '脚本名称',
      value: '',
      placeholder: '给脚本起个名字',
      validator: (value) {
        final label = value.trim();
        if (label.isEmpty) return '名称不能为空';
        if (_scripts.hasLabel(label, except: script)) return '这个名字已经存在';
        return null;
      },
    );
  }

  Future<void> _handleEditorSave(
    String title,
    EditorContent content, {
    Script? script,
  }) async {
    var label = title.trim();
    if (label.isEmpty) {
      final res = await _promptName(script: script);
      if (res == null) return;
      label = res.trim();
    }
    if (_scripts.hasLabel(label, except: script)) {
      _toast('这个名字已经存在');
      return;
    }
    final newScript = await (script?.copyWith(label: label) ?? Script.create(label: label))
        .save(await content.readText());
    _action.putScript(newScript);
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _handleEditorPop(
    String title,
    EditorContent content, {
    Script? script,
  }) async {
    final ok = await showFlvpConfirm(
      context: context,
      platform: widget.platform,
      title: '保存修改',
      message: '是否保存对这个脚本的修改？',
      confirmLabel: '保存',
      cancelLabel: '放弃',
    );
    if (ok == true && mounted) {
      unawaited(_handleEditorSave(title, content, script: script));
    }
    return ok != true;
  }

  void _openEditor([Script? script]) {
    unawaited(
      BaseNavigator.push(
        context,
        EditorPage(
          titleEditable: true,
          title: script?.label ?? '',
          onSave: (context, title, content) =>
              _handleEditorSave(title, content, script: script),
          onPop: (context, title, content) =>
              _handleEditorPop(title, content, script: script),
          language: Language.javaScript,
          load: () async => script == null
              ? CodeForgeDocument.fromText(scriptTemplate)
              : openEditorFile(await script.path, ifMissing: scriptTemplate),
        ),
      ),
    );
  }

  Future<void> _importFromUrl() async {
    final url = await showFlvpTextPrompt(
      context: context,
      platform: widget.platform,
      title: '从地址导入',
      placeholder: 'https://',
      validator: (value) {
        final uri = Uri.tryParse(value);
        return (value.isEmpty || uri == null || !uri.isAbsolute) ? '请输入有效的地址' : null;
      },
    );
    if (url == null || !mounted) return;
    final res = await globalState.safeRun(
      () => request.getTextResponseForUrl(url),
      title: '从地址导入',
    );
    if (res == null || !mounted) return;
    final fileName =
        Uri.tryParse(url)?.pathSegments.lastWhereOrNull((it) => it.isNotEmpty) ?? '';
    await _import(res.data ?? '', url: url, fileName: fileName);
  }

  Future<void> _importFromFile() async {
    final file = await globalState.safeRun(picker.pickerFile);
    if (file == null) return;
    final content = await globalState.safeRun(
      () async => utf8.decode(await file.readBytes()),
    );
    if (content == null || !mounted) return;
    await _import(content, fileName: file.name);
  }

  Future<void> _import(String content, {String? url, required String fileName}) async {
    final label = _scripts.uniqueLabel(fileName.fileStem, fallback: '脚本');
    final script = await Script.create(label: label, url: url).save(content);
    _action.putScript(script);
  }

  Future<void> _showAddMenu() async {
    final choice = await showFlvpOptionsPrompt<String>(
      context: context,
      platform: widget.platform,
      title: '添加脚本',
      value: 'scratch',
      options: const [
        FlvpRadioOption('scratch', '从空白创建'),
        FlvpRadioOption('url', '从地址导入'),
        FlvpRadioOption('file', '从文件导入'),
      ],
    );
    switch (choice) {
      case 'scratch':
        _openEditor();
      case 'url':
        await _importFromUrl();
      case 'file':
        await _importFromFile();
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    ref.read(scriptsProvider.notifier).order(oldIndex, newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final state = ref.watch(scriptsProvider);
    final scripts = state.value ?? const <Script>[];

    Widget body;
    if (state.isLoading && scripts.isEmpty) {
      body = const Center(child: FlvpSpinner(size: 22));
    } else if (scripts.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            FlvpIcon('Activity', size: 26, color: colors.ink3),
            Text('还没有脚本', style: flvpText(13.5, color: colors.ink3)),
            Text(
              '点右上角加号创建或导入',
              style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
            ),
          ],
        ),
      );
    } else {
      body = ReorderableListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        buildDefaultDragHandles: false,
        itemCount: scripts.length,
        onReorderItem: _reorder,
        proxyDecorator: (child, index, animation) => Material(
          color: const Color(0x00000000),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1, end: 1.02).animate(animation),
            child: child,
          ),
        ),
        itemBuilder: (_, index) => Padding(
          key: ValueKey(scripts[index].id),
          padding: const EdgeInsets.only(bottom: 8),
          child: _ScriptRow(
            script: scripts[index],
            indexWidget: ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FlvpIcon('MoreVertical', size: 18, color: colors.ink3),
              ),
            ),
            onEdit: () => _openEditor(scripts[index]),
            onEditUrl: scripts[index].url != null ? () => _editUrl(scripts[index]) : null,
            onSync: scripts[index].url != null ? () => _sync(scripts[index]) : null,
            onDelete: () => _delete(scripts[index]),
          ),
        ),
      );
    }

    return FlvpPageScaffold(
      title: '脚本',
      subtitle: '${scripts.length} 个 · 用于配置覆写与扩展',
      scrollable: false,
      actions: [
        FlvpIconButton(
          label: '添加脚本',
          dimension: 40,
          onPressed: _showAddMenu,
          icon: const FlvpIcon('Plus', size: 20),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: body,
      ),
    );
  }
}

class _ScriptRow extends ConsumerWidget {
  const _ScriptRow({
    required this.script,
    required this.onEdit,
    required this.onDelete,
    this.onEditUrl,
    this.onSync,
    this.indexWidget,
  });

  final Script script;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onEditUrl;
  final VoidCallback? onSync;
  final Widget? indexWidget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = FlvpThemeScope.colorsOf(context);
    final updating = ref.watch(isUpdatingProvider(script.updatingKey));
    return FlvpHover(
      builder: (context, hovered) => FlvpRipple(
        color: colors.ink,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: FlvpMotion.hover,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: hovered ? colors.surf2 : colors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: FlvpElevation.card,
          ),
          child: Row(
            children: [
              ?indexWidget,
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.pcontainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: FlvpIcon('Activity', size: 18, color: colors.onpcontainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: onEdit,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Text(
                        script.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: flvpText(13.5, color: colors.ink),
                      ),
                      Row(
                        spacing: 6,
                        children: [
                          _Mini(label: script.url != null ? '远程' : '本地', color: colors.ink3),
                          Flexible(
                            child: Text(
                              script.lastUpdateTime.getLastUpdateTimeDesc(context, compact: true),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: flvpText(11.5, weight: FontWeight.w400, color: colors.ink3),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (updating)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: FlvpSpinner(size: 18),
                )
              else ...[
                if (onEditUrl != null)
                  FlvpIconButton(
                    label: '脚本地址',
                    dimension: 34,
                    onPressed: onEditUrl,
                    icon: const FlvpIcon('Globe', size: 16),
                  ),
                if (onSync != null)
                  FlvpIconButton(
                    label: '同步',
                    dimension: 34,
                    onPressed: onSync,
                    icon: const FlvpIcon('RefreshCw', size: 16),
                  ),
                FlvpIconButton(
                  label: '编辑',
                  dimension: 34,
                  onPressed: onEdit,
                  icon: const FlvpIcon('Pencil', size: 16),
                ),
                FlvpIconButton(
                  label: '删除',
                  dimension: 34,
                  onPressed: onDelete,
                  icon: const FlvpIcon('Trash2', size: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, style: flvpText(10.5, weight: FontWeight.w600, color: color)),
    );
  }
}
