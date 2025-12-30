import { create } from 'zustand';
import Cookies from 'js-cookie';

interface User {
  id: string;
  email: string;
  username: string;
  role: string;
  role_id?: number;
  role_obj?: {
    id: number;
    name: string;
    description?: string;
  };
}

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  setAuth: (user: User | null) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  isAuthenticated: false,
  isLoading: true,
  setAuth: (user) => set({ user, isAuthenticated: !!user, isLoading: false }),
  logout: () => {
    Cookies.remove('token');
    set({ user: null, isAuthenticated: false, isLoading: false });
  },
}));
