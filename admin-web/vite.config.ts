import { configDefaults, defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

const assetBase = process.env.ADMIN_ASSET_BASE || '/';
if (assetBase !== './' && !/^\/(?:[A-Za-z0-9._~-]+\/)*$/.test(assetBase)) {
  throw new Error('ADMIN_ASSET_BASE must be ./ or an absolute, same-origin directory path');
}

export default defineConfig({
  base: assetBase,
  envDir: false,
  plugins: [react()],
  // The content-addressed _build directory provides immutable versioning.
  // A fixed entry name lets the Admin host safely identify missing entry files.
  build: {rolldownOptions: {output: {entryFileNames: 'assets/admin-entry.js'}}},
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/foundation/setup.ts'],
    include: ['tests/**/*.test.{ts,tsx}'],
    exclude: [...configDefaults.exclude, '**/._*'],
    restoreMocks: true,
  },
});
