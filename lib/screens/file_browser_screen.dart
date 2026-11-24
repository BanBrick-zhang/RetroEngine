import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/library_service.dart';
import '../theme.dart';

enum FileBrowserMode { directory, file }

/// 应用内文件浏览器，依赖“所有文件访问权限”直接访问共享存储。
class FileBrowserScreen extends StatefulWidget {
  final String initialPath;
  final FileBrowserMode mode;
  final String title;
  final List<String>? extensions;

  const FileBrowserScreen({
    super.key,
    required this.initialPath,
    this.mode = FileBrowserMode.directory,
    this.title = '选择目录',
    this.extensions,
  });

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  late String _currentPath;
  late final TextEditingController _pathController;
  List<FileSystemEntity> _items = <FileSystemEntity>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _pathController = TextEditingController(text: _currentPath);
    _load();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _load({String? path}) async {
    if (path != null) {
      _currentPath = path;
      _pathController.text = path;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dir = Directory(_currentPath);
      if (!await dir.exists()) {
        throw const FileSystemException('目录不存在');
      }
      var items = await LibraryService.listDirectory(_currentPath);
      if (widget.mode == FileBrowserMode.directory) {
        items = items.whereType<Directory>().toList();
      } else if (widget.extensions != null) {
        items = items.where((e) {
          if (e is Directory) return true;
          final ext = p.extension(e.path).toLowerCase().replaceFirst('.', '');
          return widget.extensions!.contains(ext);
        }).toList();
      }
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goUp() {
    final parent = p.dirname(_currentPath);
    if (parent != _currentPath) _load(path: parent);
  }

  void _open(FileSystemEntity entity) {
    if (entity is Directory) {
      _load(path: entity.path);
    } else if (widget.mode == FileBrowserMode.file) {
      Navigator.of(context).pop(entity.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_upward_rounded),
          tooltip: '上一级',
          onPressed: _goUp,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_location_alt_outlined),
            tooltip: '手动输入路径',
            onPressed: _showPathDialog,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
            child: Text(
              _currentPath,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Text('这里没有可显示的内容',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final entity = _items[index];
                        final isDir = entity is Directory;
                        final name = p.basename(entity.path);
                        return GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          radius: 12,
                          onTap: () => _open(entity),
                          child: Row(
                            children: [
                              Icon(
                                isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                                color: isDir ? AppTheme.accent : AppTheme.textSecondary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                      color: AppTheme.textPrimary, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isDir)
                                const Icon(Icons.chevron_right,
                                    size: 18, color: AppTheme.textSecondary),
                            ],
                          ),
                        );
                      },
                    ),
      bottomNavigationBar: widget.mode == FileBrowserMode.directory
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_currentPath),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('选择当前目录'),
              ),
            )
          : null,
    );
  }

  void _showPathDialog() {
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('输入路径',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        content: TextField(
          controller: _pathController,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: '/storage/emulated/0/...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _pathController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((value) {
      if (value != null && value.isNotEmpty) _load(path: value);
    });
  }
}
