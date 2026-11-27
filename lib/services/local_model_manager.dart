import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_recipe_ai_service.dart';

class LocalModelCandidate {
  const LocalModelCandidate({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.lastModified,
    required this.directory,
  });

  final String path;
  final String fileName;
  final int sizeBytes;
  final DateTime lastModified;
  final String directory;

  String get formattedSize {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }

  bool get isGemma {
    final lower = fileName.toLowerCase();
    return lower.contains('gemma') || lower.contains('litert');
  }
}

class LinkedModelInfo {
  const LinkedModelInfo({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.isAvailable,
    required this.linkedAt,
  });

  final String path;
  final String fileName;
  final int sizeBytes;
  final bool isAvailable;
  final DateTime? linkedAt;

  String get formattedSize {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}

class LocalModelManager {
  LocalModelManager._();
  static final instance = LocalModelManager._();

  static const linkedModelPathKey = 'local_ai_linked_model_path_v1';
  static const linkedModelDateKey = 'local_ai_linked_model_date_v1';

  static const _supportedExtensions = {
    'litertlm',
    'task',
    'bin',
    'tflite',
    'onnx',
  };

  static const _excludedDirNames = {
    '.git',
    '.dart_tool',
    'node_modules',
    'build',
    'windows',
    'android',
    'ios',
    'linux',
    'macos',
    'appdata',
    'program files',
    'program files (x86)',
    'windows.old',
  };

  // In-memory cache for fast O(1) reads
  LinkedModelInfo? _cachedLinkedInfo;
  bool _linkedInfoLoaded = false;
  List<LocalModelCandidate>? _cachedCandidates;
  DateTime? _lastScanTime;

  List<String> getSearchDirectories() {
    if (kIsWeb) return const [];
    final dirs = <String>[];

    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';

    if (home.isNotEmpty) {
      final sep = Platform.pathSeparator;
      dirs.add('$home${sep}Downloads');
      dirs.add('$home${sep}Documents');
      dirs.add('$home${sep}Desktop');
      dirs.add('$home${sep}models');
      dirs.add('$home${sep}.cache${sep}huggingface');
      dirs.add('$home${sep}.ollama${sep}models');
    }

    try {
      dirs.add(Directory.current.path);
      dirs.add('${Directory.current.path}${Platform.pathSeparator}models');
      dirs.add('${Directory.current.path}${Platform.pathSeparator}assets${Platform.pathSeparator}models');
    } catch (_) {}

    return dirs
        .where((d) => d.trim().isNotEmpty && Directory(d).existsSync())
        .toSet()
        .toList();
  }

  Future<List<LocalModelCandidate>> scanForModels({
    List<String>? customPaths,
    int maxDepth = 3,
    bool forceRefresh = false,
    void Function(LocalModelCandidate candidate)? onCandidateFound,
  }) async {
    if (kIsWeb) return const [];

    // Return cached scan if performed within last 30 seconds and not forced
    if (!forceRefresh &&
        _cachedCandidates != null &&
        _lastScanTime != null &&
        DateTime.now().difference(_lastScanTime!).inSeconds < 30) {
      if (onCandidateFound != null) {
        for (final c in _cachedCandidates!) {
          onCandidateFound(c);
        }
      }
      return _cachedCandidates!;
    }

    final searchRoots = <String>{
      ...getSearchDirectories(),
      if (customPaths != null) ...customPaths.where((p) => Directory(p).existsSync()),
    };

    final results = <LocalModelCandidate>[];
    final visitedDirs = <String>{};

    // Concurrently scan all search roots for maximum search speed
    await Future.wait(
      searchRoots.map(
        (root) => _scanDirectory(
          Directory(root),
          currentDepth: 0,
          maxDepth: maxDepth,
          visited: visitedDirs,
          results: results,
          onCandidateFound: onCandidateFound,
        ),
      ),
    );

    results.sort((a, b) {
      if (a.fileName == 'gemma-4-E2B-it.litertlm' &&
          b.fileName != 'gemma-4-E2B-it.litertlm') {
        return -1;
      }
      if (b.fileName == 'gemma-4-E2B-it.litertlm' &&
          a.fileName != 'gemma-4-E2B-it.litertlm') {
        return 1;
      }
      if (a.isGemma && !b.isGemma) return -1;
      if (!a.isGemma && b.isGemma) return 1;
      return b.sizeBytes.compareTo(a.sizeBytes);
    });

    _cachedCandidates = results;
    _lastScanTime = DateTime.now();

    return results;
  }

  Future<void> _scanDirectory(
    Directory dir, {
    required int currentDepth,
    required int maxDepth,
    required Set<String> visited,
    required List<LocalModelCandidate> results,
    required void Function(LocalModelCandidate)? onCandidateFound,
  }) async {
    if (currentDepth > maxDepth) return;
    final dirPath = dir.path.toLowerCase();
    if (!visited.add(dirPath)) return;

    try {
      final subDirs = <Directory>[];

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final segments = entity.uri.pathSegments;
          final name = segments.length >= 2 ? segments[segments.length - 2] : '';
          if (_excludedDirNames.contains(name.toLowerCase())) continue;
          subDirs.add(entity);
        } else if (entity is File) {
          final pathStr = entity.path;
          final dotIndex = pathStr.lastIndexOf('.');
          if (dotIndex == -1 || dotIndex == pathStr.length - 1) continue;
          final ext = pathStr.substring(dotIndex + 1).toLowerCase();
          if (!_supportedExtensions.contains(ext)) continue;

          try {
            final stat = await entity.stat();
            if (stat.size < 10 * 1024 * 1024) continue; // Minimum 10MB to avoid stubs
            final name = entity.uri.pathSegments.last;
            final candidate = LocalModelCandidate(
              path: entity.path,
              fileName: name,
              sizeBytes: stat.size,
              lastModified: stat.modified,
              directory: dir.path,
            );
            results.add(candidate);
            onCandidateFound?.call(candidate);
          } catch (_) {}
        }
      }

      // Recurse into child directories
      if (currentDepth < maxDepth && subDirs.isNotEmpty) {
        await Future.wait(
          subDirs.map(
            (sub) => _scanDirectory(
              sub,
              currentDepth: currentDepth + 1,
              maxDepth: maxDepth,
              visited: visited,
              results: results,
              onCandidateFound: onCandidateFound,
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<LinkedModelInfo?> getLinkedModelInfo({bool forceRefresh = false}) async {
    if (_linkedInfoLoaded && !forceRefresh) {
      return _cachedLinkedInfo;
    }

    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(linkedModelPathKey)?.trim();
    if (path == null || path.isEmpty) {
      _cachedLinkedInfo = null;
      _linkedInfoLoaded = true;
      return null;
    }

    final file = File(path);
    final exists = file.existsSync();
    final size = exists ? file.lengthSync() : 0;
    final dateStr = prefs.getString(linkedModelDateKey);
    final date = dateStr != null ? DateTime.tryParse(dateStr) : null;

    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : path.split(RegExp(r'[/\\]')).last;

    _cachedLinkedInfo = LinkedModelInfo(
      path: path,
      fileName: name,
      sizeBytes: size,
      isAvailable: exists,
      linkedAt: date,
    );
    _linkedInfoLoaded = true;
    return _cachedLinkedInfo;
  }

  Future<void> linkModel(String filePath) async {
    if (kIsWeb) {
      throw UnsupportedError('Vinculação de modelo local indisponível no navegador.');
    }
    final file = File(filePath.trim());
    if (!file.existsSync()) {
      throw FileSystemException('Arquivo do modelo não encontrado.', filePath);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(linkedModelPathKey, file.path);
    final now = DateTime.now();
    await prefs.setString(linkedModelDateKey, now.toIso8601String());

    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : file.path.split(RegExp(r'[/\\]')).last;

    _cachedLinkedInfo = LinkedModelInfo(
      path: file.path,
      fileName: name,
      sizeBytes: file.lengthSync(),
      isAvailable: true,
      linkedAt: now,
    );
    _linkedInfoLoaded = true;

    await LocalRecipeAiService.instance.linkCustomModel(file.path);
  }

  Future<void> unlinkModel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(linkedModelPathKey);
    await prefs.remove(linkedModelDateKey);
    _cachedLinkedInfo = null;
    _linkedInfoLoaded = true;
    await LocalRecipeAiService.instance.unlinkCustomModel();
  }
}
