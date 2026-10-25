// Set by vite.config.ts from the build's environment.

/** The Drive sync's "Desktop app" OAuth client - empty when the build had none. */
declare const bundledDriveClientId: string;
declare const bundledDriveClientSecret: string;

/** Whether this is the smoke test's build, which lets the test answer requests and dialogs (see e2e-hooks.ts). */
declare const e2eBuild: boolean;
