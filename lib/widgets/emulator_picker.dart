import 'package:flutter/material.dart';

import '../data/emulator_catalog.dart';
import '../models/emulator.dart';
import '../services/emulator_service.dart';
import '../theme.dart';

/// 选择结果：`config == null && removed == true` 表示清除该平台的默认模拟器。
class EmulatorPickResult {
  final EmulatorConfig? config;
  final bool removed;

  const EmulatorPickResult({this.config, this.removed = false});
}

/// 弹出模拟器选择框；用户取消时返回 null。
Future<EmulatorPickResult?> showEmulatorPicker(
  BuildContext context, {
  required String platformName,
  EmulatorConfig? initial,
}) {
  return showDialog<EmulatorPickResult>(
    context: context,
    builder: (context) => _EmulatorPickerDialog(
      platformName: platformName,
      initial: initial,
    ),
  );
}

class _EmulatorPickerDialog extends StatefulWidget {
  final String platformName;
  final EmulatorConfig? initial;

  const _EmulatorPickerDialog({
    required this.platformName,
    this.initial,
  });

  @override
  State<_EmulatorPickerDialog> createState() => _EmulatorPickerDialogState();
}

class _EmulatorPickerDialogState extends State<_EmulatorPickerDialog> {
  final EmulatorService _service = EmulatorService.instance;
  final TextEditingController _coreController = TextEditingController();

  EmulatorConfig? _selected;
  List<EmulatorCandidate> _candidates = <EmulatorCandidate>[];
  List<InstalledApp> _otherApps = <InstalledApp>[];
  bool _loading = true;
  bool _passRom = true;

  String get _platformKey => emulatorPlatformKey(widget.platformName);

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _coreController.text = widget.initial?.core ?? '';
    _load();
  }

  @override
  void dispose() {
    _coreController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final candidates = await _service.installedCandidates(widget.platformName);
    final apps = await _service.installedApps(refresh: true);
    if (!mounted) return;
    final presetPackages = emulatorCandidates(widget.platformName)
        .map((c) => c.packageName)
        .toSet();
    setState(() {
      _candidates = candidates;
      _otherApps = apps
          .where((app) => !presetPackages.contains(app.packageName))
          .toList();
      _loading = false;
    });
  }

  void _selectCandidate(EmulatorCandidate candidate) {
    setState(() {
      _selected = candidate.toConfig();
      _passRom = true;
      _coreController.text = candidate.core ?? '';
    });
  }

  void _selectApp(InstalledApp app) {
    setState(() {
      _selected = EmulatorConfig(
        label: app.label,
        packageName: app.packageName,
        mode: _passRom ? LaunchMode.view : LaunchMode.app,
      );
    });
  }

  void _applyCore(String core) {
    final selected = _selected;
    if (selected == null || selected.mode != LaunchMode.retroArch) return;
    setState(() => _selected = selected.copyWith(core: core));
  }

  bool _isSelectedPackage(String packageName) =>
      _selected?.packageName == packageName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('默认模拟器 · ${widget.platformName}',
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 17)),
          const SizedBox(height: 4),
          const Text('启动该平台游戏时使用的应用',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ],
      ),
      content: SizedBox(
        width: (MediaQuery.of(context).size.width * 0.92)
            .clamp(280.0, 440.0)
            .toDouble(),
        height: (MediaQuery.of(context).size.height * 0.58)
            .clamp(220.0, 420.0)
            .toDouble(),
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : ListView(
                children: [
                  if (_candidates.isNotEmpty) ...[
                    _sectionTitle('已安装的推荐模拟器'),
                    for (final candidate in _candidates)
                      _optionTile(
                        title: candidate.label,
                        subtitle: candidate.packageName,
                        selected: _isSelectedPackage(candidate.packageName),
                        trailing: candidate.mode == LaunchMode.retroArch
                            ? 'RetroArch'
                            : null,
                        onTap: () => _selectCandidate(candidate),
                      ),
                  ] else if (emulatorCandidates(widget.platformName).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                      child: Text(
                        '未检测到该平台的推荐模拟器，请先安装，'
                        '或从下方已安装应用中选择',
                        style: TextStyle(
                            color: AppTheme.warning.withOpacity(0.9),
                            fontSize: 11),
                      ),
                    ),
                  if (_selected?.mode == LaunchMode.retroArch) ...[
                    const SizedBox(height: 8),
                    _sectionTitle('RetroArch 核心'),
                    _coreSelector(),
                    const SizedBox(height: 8),
                  ],
                  _sectionTitle('其他已安装应用'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('把游戏文件传给所选应用',
                          style: TextStyle(
                              color: AppTheme.textPrimary, fontSize: 12)),
                      subtitle: const Text('关闭后仅打开应用主界面',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 10)),
                      value: _passRom,
                      onChanged: (value) {
                        setState(() {
                          _passRom = value;
                          final selected = _selected;
                          if (selected != null &&
                              selected.mode != LaunchMode.retroArch) {
                            _selected = selected.copyWith(
                                mode: value ? LaunchMode.view : LaunchMode.app);
                          }
                        });
                      },
                    ),
                  ),
                  if (_otherApps.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('未读取到其他应用',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11)),
                    )
                  else
                    for (final app in _otherApps)
                      _optionTile(
                        title: app.label,
                        subtitle: app.packageName,
                        selected: _isSelectedPackage(app.packageName),
                        onTap: () => _selectApp(app),
                      ),
                ],
              ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(
                context, const EmulatorPickResult(removed: true)),
            child: const Text('清除设置',
                style: TextStyle(color: AppTheme.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(
                  context, EmulatorPickResult(config: _normalizedSelection())),
          child: const Text('保存'),
        ),
      ],
    );
  }

  /// RetroArch 未指定核心时补上该平台的推荐核心，避免启动后停在菜单。
  EmulatorConfig _normalizedSelection() {
    final selected = _selected!;
    if (selected.mode != LaunchMode.retroArch) return selected;
    final core = (selected.core ?? '').trim();
    if (core.isNotEmpty) return selected;
    final cores = coresFor(_platformKey);
    return selected.copyWith(core: cores.isEmpty ? null : cores.first);
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(text,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );

  Widget _optionTile({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    String? trailing,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.border, width: 1),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? AppTheme.accent : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 10)),
                ],
              ),
            ),
            if (trailing != null)
              Text(trailing,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _coreSelector() {
    final cores = coresFor(_platformKey);
    final current = _selected?.core ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final core in cores)
              ChoiceChip(
                label: Text(core.replaceAll('_libretro_android.so', ''),
                    style: const TextStyle(fontSize: 11)),
                selected: current == core,
                onSelected: (_) {
                  _coreController.text = core;
                  _applyCore(core);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _coreController,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          decoration: const InputDecoration(
            isDense: true,
            labelText: '核心文件',
            hintText: '例如 mgba_libretro_android.so 或绝对路径',
          ),
          onSubmitted: _applyCore,
          onChanged: _applyCore,
        ),
      ],
    );
  }
}