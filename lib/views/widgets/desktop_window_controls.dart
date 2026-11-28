import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../services/platform_utils.dart';

/// Renders native-styled minimize, maximize/restore, and close window buttons for desktop.
class DesktopWindowControls extends StatefulWidget {
  final Brightness? brightness;
  final double height;
  const DesktopWindowControls({
    super.key,
    this.brightness,
    this.height = kToolbarHeight,
  });

  @override
  State<DesktopWindowControls> createState() => _DesktopWindowControlsState();
}

class _DesktopWindowControlsState extends State<DesktopWindowControls>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (isDesktopPlatform) {
      windowManager.addListener(this);
      _checkMaximizedState();
    }
  }

  Future<void> _checkMaximizedState() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _isMaximized = maximized);
    } catch (_) {}
  }

  @override
  void dispose() {
    if (isDesktopPlatform) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!isWindowsOrLinuxDesktop) {
      return const SizedBox.shrink();
    }

    final brightness = widget.brightness ?? Theme.of(context).brightness;

    return SizedBox(
      height: widget.height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WindowCaptionButton.minimize(
            brightness: brightness,
            onPressed: () async {
              try {
                final isMinimized = await windowManager.isMinimized();
                if (isMinimized) {
                  await windowManager.restore();
                } else {
                  await windowManager.minimize();
                }
              } catch (_) {}
            },
          ),
          _isMaximized
              ? WindowCaptionButton.unmaximize(
                  brightness: brightness,
                  onPressed: () async {
                    try {
                      await windowManager.unmaximize();
                    } catch (_) {}
                  },
                )
              : WindowCaptionButton.maximize(
                  brightness: brightness,
                  onPressed: () async {
                    try {
                      await windowManager.maximize();
                    } catch (_) {}
                  },
                ),
          WindowCaptionButton.close(
            brightness: brightness,
            onPressed: () async {
              try {
                await windowManager.close();
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}

/// A cross-platform drag area: enables window dragging and double-click maximize/restore
/// on desktop platforms, while behaving as a transparent pass-through on mobile and web.
class PlatformWindowDragArea extends StatelessWidget {
  final Widget child;
  const PlatformWindowDragArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) {
      return DragToMoveArea(child: child);
    }
    return child;
  }
}
