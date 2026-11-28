import 'dart:io';
import 'package:flutter/foundation.dart';

/// True if running natively on a desktop operating system (Windows, macOS, or Linux).
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// True if running on Windows or Linux desktop where custom window control buttons are rendered.
bool get isWindowsOrLinuxDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux);

/// True if running on Windows.
bool get isWindowsDesktop => !kIsWeb && Platform.isWindows;

/// True if running on macOS where native traffic lights are at top-left.
bool get isMacOSDesktop => !kIsWeb && Platform.isMacOS;

/// True if running on Linux.
bool get isLinuxDesktop => !kIsWeb && Platform.isLinux;
