import type { NextConfig } from 'next';
const config: NextConfig = {
  output: 'standalone',
  poweredByHeader: false,
  async rewrites() {
    const base = process.env.API_INTERNAL_URL || 'http://127.0.0.1:8188';
    return [{source: '/api/:path*', destination: `${base}/:path*`}, {source: '/ws/:path*', destination: `${base}/ws/:path*`}];
  },
};
export default config;
