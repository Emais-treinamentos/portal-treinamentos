import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  base: '/portal-treinamentos/',
  plugins: [react()],
  build: { chunkSizeWarningLimit: 900 },
});
