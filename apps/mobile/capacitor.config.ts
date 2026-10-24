import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  // The Flutter app's id, so this installs as its update - see .local/TYPESCRIPT_MIGRATION.md.
  appId: 'org.xennis.apps.turtlebase',
  appName: 'turtle-base',
  // The same renderer build as the desktop shell's - the platform is picked at startup.
  webDir: '../turtle-base/dist',
  plugins: {
    // Edge to edge: the page lies behind the system bars and pads itself by their insets (see styles.css).
    SystemBars: { insetsHandling: 'native', initialViewportFitValueHint: 'cover' },
  },
};

export default config;
