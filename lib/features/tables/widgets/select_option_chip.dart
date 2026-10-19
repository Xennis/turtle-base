import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';

/// Muted tints per palette color, as (background, foreground) - soft
/// enough to sit next to the warm neutrals of the softened shadcn
/// schemes (see app_color_scheme.dart) without competing with the
/// preset's accent color.
(Color, Color) optionColors(OptionColor color, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (color) {
    OptionColor.gray =>
      dark
          ? (const Color(0xFF3F3E3B), const Color(0xFFCFCCC6))
          : (const Color(0xFFE9E8E4), const Color(0xFF55534E)),
    OptionColor.brown =>
      dark
          ? (const Color(0xFF4A3A30), const Color(0xFFE0C2AE))
          : (const Color(0xFFF0E4DC), const Color(0xFF6B4A36)),
    OptionColor.orange =>
      dark
          ? (const Color(0xFF553A22), const Color(0xFFF2BF8C))
          : (const Color(0xFFFBE6D4), const Color(0xFF8A4B14)),
    OptionColor.yellow =>
      dark
          ? (const Color(0xFF4F4422), const Color(0xFFEBD48A))
          : (const Color(0xFFF8EECB), const Color(0xFF7A5D0C)),
    OptionColor.green =>
      dark
          ? (const Color(0xFF2A4434), const Color(0xFF9DD3AE))
          : (const Color(0xFFDDEFE3), const Color(0xFF2B6B43)),
    OptionColor.blue =>
      dark
          ? (const Color(0xFF22384D), const Color(0xFF9CC7EE))
          : (const Color(0xFFDCEBF7), const Color(0xFF1F5F99)),
    OptionColor.purple =>
      dark
          ? (const Color(0xFF3D3150), const Color(0xFFCDB6EC))
          : (const Color(0xFFECE3F5), const Color(0xFF5E3E8A)),
    OptionColor.pink =>
      dark
          ? (const Color(0xFF4D2C3E), const Color(0xFFEDB0CF))
          : (const Color(0xFFF6E1EC), const Color(0xFF8A3463)),
    OptionColor.red =>
      dark
          ? (const Color(0xFF542C28), const Color(0xFFF2AAA2))
          : (const Color(0xFFFBE0DD), const Color(0xFF9A2F25)),
  };
}

extension OptionColorLabel on OptionColor {
  String get label => switch (this) {
    OptionColor.gray => 'Gray',
    OptionColor.brown => 'Brown',
    OptionColor.orange => 'Orange',
    OptionColor.yellow => 'Yellow',
    OptionColor.green => 'Green',
    OptionColor.blue => 'Blue',
    OptionColor.purple => 'Purple',
    OptionColor.pink => 'Pink',
    OptionColor.red => 'Red',
  };
}

/// A select option value, shown as a colored shadcn badge. [onRemove]
/// adds a small × (e.g. for a multi-select's values), [onPressed] makes
/// the whole badge tappable.
class SelectOptionChip extends StatelessWidget {
  const SelectOptionChip({
    super.key,
    required this.option,
    this.onPressed,
    this.onRemove,
  });

  final SelectOption option;
  final VoidCallback? onPressed;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final (background, foreground) = optionColors(
      option.color,
      theme.brightness,
    );
    final label = Text(
      option.name,
      overflow: TextOverflow.ellipsis,
      // The badge's own style is w600 - lighter reads calmer when a
      // grid column is full of them.
      style: const TextStyle(fontWeight: FontWeight.w500),
    );
    return ShadBadge.raw(
      variant: ShadBadgeVariant.secondary,
      backgroundColor: background,
      hoverBackgroundColor: onPressed == null
          ? background
          : Color.alphaBlend(foreground.withValues(alpha: 0.1), background),
      foregroundColor: foreground,
      shape: const StadiumBorder(),
      padding: EdgeInsets.fromLTRB(8, 2, onRemove == null ? 8 : 4, 2),
      onPressed: onPressed,
      child: onRemove == null
          ? label
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: label),
                const SizedBox(width: 2),
                Semantics(
                  button: true,
                  label: 'Remove ${option.name}',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onRemove,
                      child: Icon(Icons.close, size: 12, color: foreground),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A filled circle in an option color's foreground tone - the more
/// saturated one, so the palette's colors are easy to tell apart in
/// the color picker (see SelectOptionsEditor).
class OptionColorDot extends StatelessWidget {
  const OptionColorDot({super.key, required this.color, this.size = 14});

  final OptionColor color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (_, foreground) = optionColors(
      color,
      ShadTheme.of(context).brightness,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
    );
  }
}
