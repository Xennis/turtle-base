import 'package:shadcn_ui/shadcn_ui.dart';

/// Which of shadcn_ui's built-in [ShadColorScheme] presets the app uses -
/// lets the user pick an accent color instead of the hardcoded green.
enum ThemePreset {
  blue,
  gray,
  green,
  neutral,
  orange,
  red,
  rose,
  slate,
  stone,
  violet,
  yellow,
  zinc;

  String get label => switch (this) {
    ThemePreset.blue => 'Blue',
    ThemePreset.gray => 'Gray',
    ThemePreset.green => 'Green',
    ThemePreset.neutral => 'Neutral',
    ThemePreset.orange => 'Orange',
    ThemePreset.red => 'Red',
    ThemePreset.rose => 'Rose',
    ThemePreset.slate => 'Slate',
    ThemePreset.stone => 'Stone',
    ThemePreset.violet => 'Violet',
    ThemePreset.yellow => 'Yellow',
    ThemePreset.zinc => 'Zinc',
  };

  ShadColorScheme light() => switch (this) {
    ThemePreset.blue => const ShadBlueColorScheme.light(),
    ThemePreset.gray => const ShadGrayColorScheme.light(),
    ThemePreset.green => const ShadGreenColorScheme.light(),
    ThemePreset.neutral => const ShadNeutralColorScheme.light(),
    ThemePreset.orange => const ShadOrangeColorScheme.light(),
    ThemePreset.red => const ShadRedColorScheme.light(),
    ThemePreset.rose => const ShadRoseColorScheme.light(),
    ThemePreset.slate => const ShadSlateColorScheme.light(),
    ThemePreset.stone => const ShadStoneColorScheme.light(),
    ThemePreset.violet => const ShadVioletColorScheme.light(),
    ThemePreset.yellow => const ShadYellowColorScheme.light(),
    ThemePreset.zinc => const ShadZincColorScheme.light(),
  };

  ShadColorScheme dark() => switch (this) {
    ThemePreset.blue => const ShadBlueColorScheme.dark(),
    ThemePreset.gray => const ShadGrayColorScheme.dark(),
    ThemePreset.green => const ShadGreenColorScheme.dark(),
    ThemePreset.neutral => const ShadNeutralColorScheme.dark(),
    ThemePreset.orange => const ShadOrangeColorScheme.dark(),
    ThemePreset.red => const ShadRedColorScheme.dark(),
    ThemePreset.rose => const ShadRoseColorScheme.dark(),
    ThemePreset.slate => const ShadSlateColorScheme.dark(),
    ThemePreset.stone => const ShadStoneColorScheme.dark(),
    ThemePreset.violet => const ShadVioletColorScheme.dark(),
    ThemePreset.yellow => const ShadYellowColorScheme.dark(),
    ThemePreset.zinc => const ShadZincColorScheme.dark(),
  };
}
