import 'dart:async';

import 'package:floway/common/common.dart';
import 'package:floway/common/dav_client.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/views/backup_and_restore.dart' show WebDAVForm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../icons/flvp_icon.dart';
import '../../store/store_scope.dart';
import '../../widgets/controls.dart';
import '../../widgets/data_display.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../../sheet.dart';

/// 备份与恢复：WebDAV 与本地两条链路，动作、进度与恢复策略全部沿用上游
/// `backupActionProvider` / `davSettingProvider` / `appSettingProvider`。
class FlvpBackupPage extends ConsumerStatefulWidget {
  const FlvpBackupPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpBackupPage> createState() => _FlvpBackupPageState();
}

class _FlvpBackupPageState extends ConsumerState<FlvpBackupPage> {
  final _davConnection = DAVConnectionController();

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      davSettingProvider,
      (_, _) => unawaited(_davConnection.update(ref.read(davSettingProvider))),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _davConnection.dispose();
    super.dispose();
  }

  void _toast(String message) => FlvpStoreScope.read(context).notify(message);

  Future<void> _run({
    required String title,
    required String successMessage,
    required Future<bool> Function() task,
  }) async {
    final ok = await globalState.loadingRun<bool>(
      task,
      tag: LoadingTag.backup_restore,
      title: title,
    );
    if (ok == true && mounted) _toast(successMessage);
  }

  Future<RestoreOption?> _pickRestoreOption() {
    return showFlvpOptionsPrompt<RestoreOption>(
      context: context,
      platform: widget.platform,
      title: '恢复内容',
      value: RestoreOption.all,
      options: const [
        FlvpRadioOption(RestoreOption.all, '全部数据'),
        FlvpRadioOption(RestoreOption.onlyProfiles, '仅配置文件'),
      ],
    );
  }

  Future<void> _showDavForm() async {
    await showFormSheet<void>(
      context: context,
      builder: (_) => WebDAVForm(dav: ref.read(davSettingProvider)?.copyWith()),
    );
  }

  Future<void> _backupLocal() => _run(
    title: '备份',
    successMessage: '备份已保存',
    task: () => ref.read(backupActionProvider.notifier).backup((archivePath) async {
      final saved = await picker.saveFileWithPath(getBackupFileName(), archivePath);
      return saved != null;
    }),
  );

  Future<void> _restoreLocal() async {
    final option = await _pickRestoreOption();
    if (option == null || !mounted) return;
    final file = await picker.pickerFile();
    final path = file?.path;
    if (path == null || !mounted) return;
    await _run(
      title: '恢复',
      successMessage: '恢复完成',
      task: () => ref.read(backupActionProvider.notifier).restore(
        option,
        (_) async => path,
      ),
    );
  }

  Future<void> _backupWebDav() async {
    final client = _davConnection.client;
    if (client == null) return;
    await _run(
      title: '备份到 WebDAV',
      successMessage: '已上传到 WebDAV',
      task: () => ref.read(backupActionProvider.notifier).backup((path) async {
        await client.upload(path);
        return true;
      }),
    );
  }

  Future<void> _restoreWebDav() async {
    final client = _davConnection.client;
    if (client == null) return;
    final option = await _pickRestoreOption();
    if (option == null || !mounted) return;
    await _run(
      title: '从 WebDAV 恢复',
      successMessage: '恢复完成',
      task: () => ref.read(backupActionProvider.notifier).restore(
        option,
        (path) async {
          await client.download(path);
          return path;
        },
      ),
    );
  }

  Future<void> _editFileName() async {
    final dav = ref.read(davSettingProvider);
    if (dav == null) return;
    final next = await showFlvpTextPrompt(
      context: context,
      platform: widget.platform,
      title: '文件名',
      subtitle: '备份在 WebDAV 上的文件名',
      value: dav.fileName,
      placeholder: defaultDavFileName,
      validator: (value) => value.trim().isEmpty ? '不能为空' : null,
    );
    if (next == null || next == dav.fileName) return;
    ref
        .read(davSettingProvider.notifier)
        .update((state) => state?.copyWith(fileName: next.trim()));
  }

  Future<void> _editStrategy() async {
    final current = ref.read(appSettingProvider).restoreStrategy;
    final next = await showFlvpOptionsPrompt<RestoreStrategy>(
      context: context,
      platform: widget.platform,
      title: '恢复策略',
      value: current,
      options: [
        for (final strategy in RestoreStrategy.values)
          FlvpRadioOption(strategy, strategy.label),
      ],
    );
    if (next == null || next == current) return;
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(restoreStrategy: next));
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final dav = ref.watch(davSettingProvider);
    final strategy = ref.watch(
      appSettingProvider.select((state) => state.restoreStrategy),
    );
    final busy = ref.watch(loadingProvider(LoadingTag.backup_restore));

    return FlvpPageScaffold(
      title: '备份与恢复',
      subtitle: dav == null ? '仅本地' : 'WebDAV + 本地',
      actions: [
        if (busy) const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Center(child: FlvpSpinner(size: 18)),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlvpSettingsSection(
            title: '远程（WebDAV）',
            footer: dav == null ? '绑定后可以把备份放到自己的网盘' : null,
            children: [
              if (dav == null)
                FlvpSettingsRow(
                  icon: 'Globe2',
                  title: '还没有绑定 WebDAV',
                  subtitle: '绑定后可在远端备份与恢复',
                  onTap: _showDavForm,
                  trailing: FlvpButton(
                    variant: FlvpButtonVariant.tonal,
                    label: '绑定',
                    onPressed: _showDavForm,
                  ),
                )
              else ...[
                FlvpSettingsRow(
                  icon: 'Globe2',
                  title: dav.user,
                  subtitle: dav.uri,
                  onTap: _showDavForm,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      _ConnectionDot(connection: _davConnection),
                      FlvpIcon('ChevronRight', size: 14, color: colors.ink3),
                    ],
                  ),
                ),
                FlvpSettingsValue(
                  icon: 'Archive',
                  title: '文件名',
                  value: dav.fileName,
                  onTap: _editFileName,
                ),
                FlvpSettingsRow(
                  icon: 'Upload',
                  title: '备份到 WebDAV',
                  onTap: busy ? null : _backupWebDav,
                ),
                FlvpSettingsRow(
                  icon: 'Download',
                  title: '从 WebDAV 恢复',
                  onTap: busy ? null : _restoreWebDav,
                ),
              ],
            ],
          ),
          FlvpSettingsSection(
            title: '本地',
            children: [
              FlvpSettingsRow(
                icon: 'Upload',
                title: '导出备份文件',
                onTap: busy ? null : _backupLocal,
              ),
              FlvpSettingsRow(
                icon: 'Download',
                title: '从文件恢复',
                onTap: busy ? null : _restoreLocal,
              ),
            ],
          ),
          FlvpSettingsSection(
            title: '选项',
            children: [
              FlvpSettingsValue(
                icon: 'SlidersHorizontal',
                title: '恢复策略',
                value: strategy.label,
                onTap: _editStrategy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// WebDAV 连通性：null 表示还没探测，绿点已连通，红点失败。
class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.connection});

  final ValueNotifier<bool?> connection;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return ValueListenableBuilder<bool?>(
      valueListenable: connection,
      builder: (context, connected, _) {
        final color = switch (connected) {
          true => colors.ok,
          false => colors.err,
          null => colors.ink3,
        };
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Text(
              switch (connected) {
                true => '已连通',
                false => '连接失败',
                null => '未探测',
              },
              style: flvpText(11.5, weight: FontWeight.w400, color: colors.ink3),
            ),
          ],
        );
      },
    );
  }
}
