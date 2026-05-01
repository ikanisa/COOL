import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  root: '.',
  publicDir: 'public',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        privacy: resolve(__dirname, 'privacy.html'),
        terms: resolve(__dirname, 'terms.html'),
        'account-deletion': resolve(__dirname, 'account-deletion.html'),
      },
    },
  },
  server: {
    port: 4000,
    host: '0.0.0.0',
    open: true,
  },
});
