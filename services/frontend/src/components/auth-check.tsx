'use client';

import { useEffect } from 'react';
import { useAuthStore } from '@/store/auth-store';
import apiClient from '@/lib/axios';
import Cookies from 'js-cookie';

export function AuthCheck({ children }: { children: React.ReactNode }) {
  const setAuth = useAuthStore((state) => state.setAuth);

  useEffect(() => {
    const checkAuth = async () => {
      const token = Cookies.get('token');
      if (!token) {
        setAuth(null);
        return;
      }

      try {
        const response = await apiClient.get('/auth/me');
        setAuth(response.data);
      } catch (error) {
        setAuth(null);
      }
    };

    checkAuth();
  }, [setAuth]);

  return <>{children}</>;
}
