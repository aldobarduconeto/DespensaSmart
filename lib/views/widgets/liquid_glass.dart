import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/app_settings_service.dart';

/// Ambient background with soft glowing orbs that create depth and color
/// refraction behind Liquid Glass surfaces.
class LiquidGlassBackground extends StatelessWidget {
  final Widget child;
  const LiquidGlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A1410),
              Color(0xFF0E1D17),
              Color(0xFF13261E),
              Color(0xFF0B1612),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFEAF4EE),
              Color(0xFFF5F7F2),
              Color(0xFFE5F0EA),
              Color(0xFFF7F4EB),
            ],
          );

    return ListenableBuilder(
      listenable: AppSettingsService.instance,
      builder: (context, _) {
        final showOrbs = AppSettingsService.instance.ambientOrbsEnabled;
        return DecoratedBox(
          decoration: BoxDecoration(gradient: baseGradient),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showOrbs) ...[
                Positioned(
                  top: -110,
                  left: -70,
                  child: _AmbientOrb(
                    size: 320,
                    color: isDark
                        ? const Color(0xFF1E7E5C).withValues(alpha: 0.30)
                        : const Color(0xFF43B58B).withValues(alpha: 0.24),
                  ),
                ),
                Positioned(
                  top: 140,
                  right: -90,
                  child: _AmbientOrb(
                    size: 290,
                    color: isDark
                        ? const Color(0xFFD9A33E).withValues(alpha: 0.16)
                        : const Color(0xFFF3C86A).withValues(alpha: 0.26),
                  ),
                ),
                Positioned(
                  bottom: -100,
                  left: -40,
                  child: _AmbientOrb(
                    size: 300,
                    color: isDark
                        ? const Color(0xFF288B7B).withValues(alpha: 0.20)
                        : const Color(0xFF5DC4AE).withValues(alpha: 0.20),
                  ),
                ),
              ],
              child,
            ],
          ),
        );
      },
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _AmbientOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Core Liquid Glass container with frosted blur, specular top-left highlight,
/// and subtle refractive border.
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double? blur;
  final Color? tint;
  final VoidCallback? onTap;
  final bool prominent;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 24,
    this.blur,
    this.tint,
    this.onTap,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettingsService.instance,
      builder: (context, _) {
        final effectiveBlur =
            blur ?? AppSettingsService.instance.glassBlurSigma;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final radius = BorderRadius.circular(borderRadius);
        final baseTint =
            tint ?? (isDark ? const Color(0xFF1D3128) : Colors.white);

        final topAlpha = prominent
            ? (isDark ? 0.72 : 0.85)
            : (isDark ? 0.56 : 0.72);
        final bottomAlpha = prominent
            ? (isDark ? 0.52 : 0.68)
            : (isDark ? 0.36 : 0.52);

        final borderColor = isDark
            ? Colors.white.withValues(alpha: prominent ? 0.22 : 0.14)
            : Colors.white.withValues(alpha: prominent ? 0.88 : 0.72);

        Widget content = ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: effectiveBlur, sigmaY: effectiveBlur),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    baseTint.withValues(alpha: topAlpha),
                    baseTint.withValues(alpha: bottomAlpha),
                  ],
                ),
                border: Border.all(color: borderColor, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.28)
                        : const Color(0xFF175B45).withValues(alpha: 0.07),
                    blurRadius: prominent ? 28 : 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: onTap != null
                    ? InkWell(
                        borderRadius: radius,
                        onTap: onTap,
                        child: Padding(
                          padding: padding ?? EdgeInsets.zero,
                          child: child,
                        ),
                      )
                    : Padding(
                        padding: padding ?? EdgeInsets.zero,
                        child: child,
                      ),
              ),
            ),
          ),
        );

        if (margin != null) {
          content = Padding(padding: margin!, child: content);
        }
        return content;
      },
    );
  }
}

/// Frosted Liquid Glass AppBar with translucent blur and bottom specular line.
class LiquidGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;
  final double height;

  const LiquidGlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.height = kToolbarHeight + 6,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: AppSettingsService.instance,
      builder: (context, _) {
        final blur = AppSettingsService.instance.glassBlurSigma;
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          const Color(0xFF0F1E18).withValues(alpha: 0.80),
                          const Color(0xFF0F1E18).withValues(alpha: 0.58),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.82),
                          Colors.white.withValues(alpha: 0.62),
                        ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.white.withValues(alpha: 0.75),
                    width: 1,
                  ),
                ),
              ),
              child: AppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: leading,
                title: title,
                actions: actions,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Floating capsule Liquid Glass Bottom Navigation Bar.
class LiquidGlassBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<({IconData icon, IconData selectedIcon, String label, int? badge})>
      destinations;

  const LiquidGlassBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF1B2E25).withValues(alpha: 0.82),
                          const Color(0xFF12211A).withValues(alpha: 0.68),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.86),
                          Colors.white.withValues(alpha: 0.68),
                        ],
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.90),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.40)
                        : const Color(0xFF175B45).withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _NavPillItem(
                        icon: destinations[i].icon,
                        selectedIcon: destinations[i].selectedIcon,
                        label: destinations[i].label,
                        badge: destinations[i].badge,
                        selected: selectedIndex == i,
                        scheme: scheme,
                        isDark: isDark,
                        onTap: () => onDestinationSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavPillItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? badge;
  final bool selected;
  final ColorScheme scheme;
  final bool isDark;
  final VoidCallback onTap;

  const _NavPillItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge,
    required this.selected,
    required this.scheme,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? (isDark ? const Color(0xFF94D6B8) : const Color(0xFF175B45))
        : scheme.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          scheme.primary.withValues(alpha: 0.26),
                          scheme.primary.withValues(alpha: 0.12),
                        ]
                      : [
                          scheme.primary.withValues(alpha: 0.18),
                          scheme.primary.withValues(alpha: 0.08),
                        ],
                )
              : null,
          border: selected
              ? Border.all(
                  color: scheme.primary.withValues(alpha: isDark ? 0.38 : 0.25),
                )
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selectedIcon : icon, color: fg, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
            if (badge != null && badge! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.tertiary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    color: scheme.onTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact frosted pill badge used in headers, cards, and feature tags.
class LiquidGlassPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const LiquidGlassPill({
    super.key,
    this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = color ?? scheme.primary;

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: tone),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: pill,
    );
  }
}
