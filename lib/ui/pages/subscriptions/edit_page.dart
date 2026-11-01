import 'dart:async';
import 'dart:typed_data';

import 'package:floway/common/common.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/pages/editor.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/ui/metrics.dart';
import 'package:floway/ui/navigator.dart';
import 'package:floway/views/profiles/edit.dart' show validateProfileName;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../icons/flvp_icon.dart';
import '../../widgets/controls.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/surfaces.dart';

/// 配置编辑：名称 / 订阅地址 / age 密钥 / 自动更新与间隔 / 源文件编辑与上传。
///
/// 校验与落盘全部沿用上游 `EditProfileView` 的规则：`validateProfileName`、
/// `Profile.copyWith`、`profilesActionProvider.putProfile` /
/// `updateProfile`、`Profile.saveFile`（先交给内核校验），这里只把呈现换成
/// Floway 的表单与行。
class FlvpProfileEditPage extends ConsumerStatefulWidget {
  const FlvpProfileEditPage({
    super.key,
    required this.profile,
    required this.platform,
  });

  final Profile profile;
  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpProfileEditPage> createState() =>
      _FlvpProfileEditPageState();
}

class _FlvpProfileEditPageState extends ConsumerState<FlvpProfileEditPage> {
  late String _label;
  late String _url;
  late String _ageSecretKey;
  late String _interval;
  late bool _autoUpdate;
  late SetupAction _setupAction;

  FileInfo? _fileInfo;
  Uint8List? _fileData;
  String? _error;
  var _saving = false;

  Profile get _profile => widget.profile;

  bool get _isUrl => _profile.type == ProfileType.url;

  @override
  void initState() {
    super.initState();
    _label = _profile.label;
    _url = _profile.url;
    _ageSecretKey = _profile.ageSecretKey;
    _interval = '${_profile.autoUpdateDuration.inMinutes}';
    _autoUpdate = _profile.autoUpdate;
    _setupAction = ref.read(setupActionProvider.notifier);
    unawaited(_loadFileInfo());
  }

  @override
  void dispose() {
    super.dispose();
    // 与上游一致：离开编辑页后重新应用一次当前配置。
    _setupAction.autoApplyProfile();
  }

  Future<void> _loadFileInfo() async {
    FileInfo? info;
    try {
      final file = await _profile.file;
      info = await file.getFileInfo();
    } catch (_) {
      info = null;
    }
    if (!mounted) return;
    setState(() => _fileInfo = info);
  }

  String? _validate() {
    final l = currentAppLocalizations;
    final nameError = validateProfileName(l, _label.trim());
    if (nameError != null) return nameError;
    if (!_isUrl) return null;
    final url = _url.trim();
    if (url.isEmpty) return l.profileUrlNullValidationDesc;
    if (!url.isUrl) return l.profileUrlInvalidValidationDesc;
    if (!_autoUpdate) return null;
    final interval = int.tryParse(_interval.trim());
    if (interval == null) return l.profileAutoUpdateIntervalNullValidationDesc;
    if (interval <= 0) return l.profileAutoUpdateIntervalInvalidValidationDesc;
    return null;
  }

  void _changed(String _) {
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  Future<void> _pickInterval() async {
    final minutes = await showFlvpNumberPrompt(
      context: context,
      platform: widget.platform,
      title: '更新间隔',
      subtitle: '每隔多少分钟从订阅地址同步一次',
      value: int.tryParse(_interval.trim()) ?? 60,
      min: 1,
      max: 100000,
      suffix: '分钟',
    );
    if (minutes == null || !mounted) return;
    setState(() => _interval = '$minutes');
  }

  Future<void> _save() async {
    if (_saving) return;
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final current =
          ref.read(profilesProvider).getProfile(_profile.id) ?? _profile;
      final interval = int.tryParse(_interval.trim());
      var profile = current.copyWith(
        url: _url.trim(),
        ageSecretKey: _ageSecretKey.trim(),
        label: _label.trim(),
        autoUpdate: _autoUpdate,
        autoUpdateDuration: interval != null && interval > 0
            ? Duration(minutes: interval)
            : current.autoUpdateDuration,
      );
      final action = ref.read(profilesActionProvider.notifier);
      final l = currentAppLocalizations;
      final hasUpdate =
          current.url != profile.url ||
          current.ageSecretKey != profile.ageSecretKey;
      final data = _fileData;
      if (data != null) {
        if (profile.type == ProfileType.url && _autoUpdate) {
          final confirmed = await showFlvpConfirm(
            context: context,
            platform: widget.platform,
            title: '配置内容已修改',
            message: l.profileHasUpdate,
            confirmLabel: '关闭自动更新',
            cancelLabel: '保留自动更新',
          );
          if (confirmed == true) {
            profile = profile.copyWith(autoUpdate: false);
          }
        }
        final saved = await globalState.safeRun(
          () => profile.saveFile(
            data,
            validate: (path, key) =>
                ref.read(coreHandlerProvider).validateProfile(path, key),
          ),
        );
        if (saved == null) return;
        action.putProfile(saved);
      } else if (!hasUpdate) {
        action.putProfile(profile);
      } else {
        unawaited(
          globalState.safeRun(() async {
            await Future.delayed(commonDuration);
            if (hasUpdate) {
              await action.updateProfile(profile);
            }
          }),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLeave() async {
    if (_saving) return;
    final ok = await showFlvpConfirm(
      context: context,
      platform: widget.platform,
      title: '保存修改',
      message: '配置文件有未保存的改动，是否先保存？',
      confirmLabel: '保存',
      cancelLabel: '放弃',
    );
    if (!mounted) return;
    if (ok == true) {
      await _save();
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _openEditor() async {
    final data = _fileData;
    final title = _profile.realLabel;
    final page = EditorPage(
      title: title,
      load: () async => data != null
          ? CodeForgeDocument.fromUtf8(data)
          : openEditorFile(await appPath.getProfilePath('${_profile.id}')),
      onSave: (context, _, content) async {
        final bytes = await content.readBytes();
        if (!context.mounted) return;
        await _applyEdited(bytes);
      },
      onPop: (context, _, content) async {
        final ok = await showFlvpConfirm(
          context: context,
          platform: widget.platform,
          title: '保存修改',
          message: '源文件有未保存的修改，是否保存？',
          confirmLabel: '保存',
          cancelLabel: '放弃',
        );
        if (ok != true || !mounted) return true;
        final bytes = await content.readBytes();
        if (!mounted) return true;
        await _applyEdited(bytes);
        return true;
      },
    );
    final edited = await BaseNavigator.push<Uint8List>(context, page);
    if (edited == null || !mounted) return;
    await _applyEdited(edited);
  }

  Future<void> _applyEdited(Uint8List bytes) async {
    final message = await globalState.safeRun<String>(() async {
      return ref
          .read(profilesActionProvider.notifier)
          .validateConfigWithData(bytes);
    }, silence: false);
    if (message != null && message.isNotEmpty) {
      if (!mounted) return;
      setState(() => _error = message);
      return;
    }
    if (!mounted) return;
    setState(() {
      _fileData = bytes;
      _error = null;
    });
  }

  Future<void> _upload() async {
    final file = await globalState.safeRun(picker.pickerFile);
    if (file == null || !mounted) return;
    final bytes = await globalState.safeRun(file.readBytes);
    if (bytes == null || !mounted) return;
    await _applyEdited(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final l = currentAppLocalizations;
    final label = _label.trim();
    return PopScope(
      canPop: _fileData == null && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_confirmLeave());
      },
      child: FlvpPageScaffold(
        title: '编辑配置',
        subtitle:
            '${label.isEmpty ? _profile.realLabel : label} · ${_typeLabel(_profile.type)}',
        actions: [
          FlvpButton(
            size: FlvpControlSize.sm,
            label: _saving ? '保存中…' : '保存',
            onPressed: _saving ? null : _save,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              _ErrorBanner(message: _error!),
              const SizedBox(height: 16),
            ],
            FlvpSettingsSection(
              title: '基本信息',
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: FlvpField(
                    label: '名称',
                    value: _label,
                    placeholder: l.required,
                    onChanged: (value) {
                      _changed(value);
                      setState(() => _label = value);
                    },
                  ),
                ),
                if (_isUrl)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: FlvpField(
                      label: '订阅地址',
                      value: _url,
                      placeholder: 'https://',
                      mono: true,
                      onChanged: (value) {
                        _changed(value);
                        setState(() => _url = value);
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: FlvpField(
                    label: 'age 密钥',
                    value: _ageSecretKey,
                    placeholder: l.optional,
                    mono: true,
                    onChanged: (value) {
                      _changed(value);
                      setState(() => _ageSecretKey = value);
                    },
                  ),
                ),
              ],
            ),
            if (_isUrl)
              FlvpSettingsSection(
                title: '同步设置',
                footer: '开启后按间隔从订阅地址同步；间隔单位为分钟。',
                children: [
                  FlvpSettingsToggle(
                    icon: 'RefreshCw',
                    title: '自动更新',
                    subtitle: '按间隔同步这份订阅',
                    value: _autoUpdate,
                    onChanged: (value) => setState(() => _autoUpdate = value),
                  ),
                  if (_autoUpdate)
                    FlvpSettingsValue(
                      icon: 'Timer',
                      title: '更新间隔',
                      value: '${_interval.trim()} 分钟',
                      onTap: _pickInterval,
                    ),
                ],
              ),
            FlvpSettingsSection(
              title: '配置文件',
              footer: '编辑或上传后会先交给内核校验，校验不通过不会写入；保存本页时才真正落盘。',
              children: [
                _FileRow(
                  info: _fileInfo,
                  pendingBytes: _fileData?.length,
                  onEdit: _openEditor,
                  onUpload: _upload,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Text(
                '保存后若订阅地址或 age 密钥有变化，会立即重新拉取一次订阅。',
                style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.info,
    required this.pendingBytes,
    required this.onEdit,
    required this.onUpload,
  });

  final FileInfo? info;
  final int? pendingBytes;
  final VoidCallback onEdit;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final pending = pendingBytes;
    final subtitle = pending != null
        ? '${_sizeText(pending)} · 待保存'
        : info == null
        ? '还没有本地内容，先同步或上传一份'
        : '${_sizeText(info!.size)} · ${_stampText(info!.lastModified)}';
    return FlvpRow(
      icon: const FlvpIcon('Archive', size: 19),
      title: '源文件',
      subtitle: subtitle,
      onTap: onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          FlvpIconButton(
            label: '编辑',
            dimension: 34,
            onPressed: onEdit,
            icon: FlvpIcon('Pencil', size: 16, color: colors.ink2),
          ),
          FlvpIconButton(
            label: '上传',
            dimension: 34,
            onPressed: onUpload,
            icon: FlvpIcon('Upload', size: 16, color: colors.ink2),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        spacing: 10,
        children: [
          FlvpIcon('TriangleAlert', size: 18, color: colors.warn),
          Expanded(
            child: Text(
              message,
              style: flvpText(12.5, weight: FontWeight.w400, color: colors.warn),
            ),
          ),
        ],
      ),
    );
  }
}

String _typeLabel(ProfileType type) => switch (type) {
  ProfileType.url => '远程订阅',
  ProfileType.file => '本地文件',
  ProfileType.custom => '自定义配置',
};

String _sizeText(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100 || unit == 0 || value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _stampText(DateTime? value) => value == null
    ? '未更新'
    : '${_two(value.month)}-${_two(value.day)} ${_two(value.hour)}:${_two(value.minute)}';
