import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A warm terracotta accent, used for primary actions, focus rings, and
/// selected sidebar rows in both themes, so the UI isn't purely
/// grayscale.
const _accent = Color(0xffcc785c);

/// Our own Zinc-derived color schemes (see main.dart) rather than the
/// package defaults - dark's default background (0xff09090b) reads as
/// near-black, and neither theme has any color beyond gray otherwise.
const appLightColorScheme = ShadZincColorScheme.light(
  primary: _accent,
  primaryForeground: Color(0xffffffff),
  ring: _accent,
  accent: Color(0xfff7ece7),
  accentForeground: Color(0xff7a4a38),
);

const appDarkColorScheme = ShadZincColorScheme.dark(
  // A lighter dark gray instead of near-black, with card/popover a
  // shade lighter again so surfaces have visible depth against it.
  background: Color(0xff1e1e20),
  card: Color(0xff26262a),
  popover: Color(0xff26262a),
  primary: _accent,
  primaryForeground: Color(0xff2a2320),
  ring: _accent,
  accent: Color(0xff3a2e28),
  accentForeground: Color(0xfff5ede8),
);
