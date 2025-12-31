import axios from 'axios';
import Cookies from 'js-cookie';
import { useAuthStore } from '@/store/auth-store';

const apiClient = axios.create({
  baseURL: process.env.NEXT_PUBLIC_API_URL 
    ? (process.env.NEXT_PUBLIC_API_URL.endsWith('/api') ? process.env.NEXT_PUBLIC_API_URL : `${process.env.NEXT_PUBLIC_API_URL}/api`)
    : 'http://localhost:8000/api',
  headers: {
    'Content-Type': 'application/json',
  },
});

apiClient.interceptors.request.use((config) => {
  const token = Cookies.get('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

apiClient.interceptors.response.use(
  (response) => response,
  async (error) => {
    if (error.response?.status === 401) {
      // Используем состояние напрямую для вызова logout, если возможно, 
      // но в axios.ts (не React компонент) лучше вызвать logout из стора
      useAuthStore.getState().logout();
      if (typeof window !== 'undefined') {
        window.location.href = '/auth/signin';
      }
    }
    return Promise.reject(error);
  }
);

export default apiClient;
