import { defineConfig } from 'vite-plus';

// Root config of the TypeScript workspace: lint and format settings apply
// to every member (Vite+ ignores lint/fmt blocks in member configs), tests
// run per member through `test.projects`.
export default defineConfig({
  lint: {
    plugins: ['typescript', 'unicorn', 'import', 'vitest'],
    categories: {
      correctness: 'error',
      suspicious: 'error',
    },
    options: {
      typeAware: true,
      typeCheck: true,
    },
    ignorePatterns: ['**/dist/**', 'apps/turtle_base/**', 'packages/*_*/**'],
    rules: {
      'typescript/no-explicit-any': 'error',
      'typescript/no-non-null-assertion': 'error',
      'typescript/no-floating-promises': 'error',
      'typescript/no-misused-promises': 'error',
      'typescript/no-unsafe-argument': 'error',
      'typescript/no-unsafe-assignment': 'error',
      'typescript/no-unsafe-call': 'error',
      'typescript/no-unsafe-member-access': 'error',
      'typescript/no-unsafe-return': 'error',
      // A `default` branch is an explicit "everything else", not a forgotten case.
      'typescript/switch-exhaustiveness-check': ['error', { considerDefaultExhaustiveForUnions: true }],
      'typescript/strict-boolean-expressions': 'error',
      'typescript/consistent-type-imports': 'error',
      'typescript/require-await': 'error',
      'import/no-cycle': 'error',
    },
  },
  fmt: {
    printWidth: 120,
    singleQuote: true,
    semi: true,
    sortPackageJson: true,
    // Docs outside the TypeScript members keep their own hand formatting.
    ignorePatterns: ['**/dist/**', 'apps/turtle_base/**', 'packages/*_*/**', 'ops/**', '*.md', 'pnpm-lock.yaml'],
  },
  test: {
    projects: ['packages/*/vite.config.ts', 'apps/*/vite.config.ts'],
  },
});
