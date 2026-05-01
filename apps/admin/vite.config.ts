import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import {defineConfig} from 'vite';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    chunkSizeWarningLimit: 450,
    rollupOptions: {
      output: {
        manualChunks: {
          react: ['react', 'react-dom', 'react-router-dom'],
          supabase: ['@supabase/supabase-js'],
          charts: ['recharts'],
          radix: ['@radix-ui/react-dropdown-menu'],
          icons: ['lucide-react'],
          notifications: ['sonner'],
        },
      },
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@cool/shared-utils': path.resolve(
        __dirname,
        '../../packages/shared-utils/src',
      ),
    },
  },
  server: {
    hmr: true,
  },
});
