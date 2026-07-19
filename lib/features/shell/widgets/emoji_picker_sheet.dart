import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// The emoji picker bottom sheet used for page and collection icons.
///
/// EmojiPicker doesn't follow the ambient theme on its own - its config
/// defaults are hardcoded light-gray/blue, which clashed with dark mode.
/// The view backgrounds stay transparent so the sheet's themed surface
/// (see materialThemeFrom's bottomSheetTheme) shows through; only the
/// accents are mapped to shadcn tokens. Calls [onSelected] with the
/// picked emoji, then closes the sheet.
Future<void> showEmojiPickerSheet(
  BuildContext context, {
  required ValueChanged<String> onSelected,
}) async {
  final colors = ShadTheme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SizedBox(
      height: 320,
      child: EmojiPicker(
        config: Config(
          emojiViewConfig: const EmojiViewConfig(
            backgroundColor: Colors.transparent,
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: Colors.transparent,
            indicatorColor: colors.primary,
            iconColor: colors.mutedForeground,
            iconColorSelected: colors.primary,
            backspaceColor: colors.primary,
          ),
          bottomActionBarConfig: BottomActionBarConfig(
            backgroundColor: colors.muted,
            buttonColor: colors.muted,
            buttonIconColor: colors.mutedForeground,
          ),
          searchViewConfig: SearchViewConfig(
            backgroundColor: colors.popover,
            buttonIconColor: colors.mutedForeground,
          ),
        ),
        onEmojiSelected: (category, emoji) {
          onSelected(emoji.emoji);
          Navigator.of(sheetContext).pop();
        },
      ),
    ),
  );
}
