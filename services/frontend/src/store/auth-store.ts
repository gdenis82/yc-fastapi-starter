import { create, StateCreator } from 'zustand';
import Cookies from 'js-cookie';

export interface User {
  id: string;
  email: string;
  username: string;
  name?: string;
  role: string;
  role_id?: number;
  role_obj?: {
    id: number;
    name: string;
    description?: string;
  };
}

export interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  setAuth: (user: User | null) => void;
  setLoading: (loading: boolean) => void;
  logout: () => void;
}

const authStoreCreator: StateCreator<AuthState> = (set) => ({
  user: null,
  isAuthenticated: false,
  isLoading: true,
  setAuth: (user) => set({ user, isAuthenticated: !!user, isLoading: false }),
  setLoading: (loading) => set({ isLoading: loading }),
  logout: () => {
    Cookies.remove('token');
    set({ user: null, isAuthenticated: false, isLoading: false });
  },
});

export const useAuthStore = create<AuthState>(authStoreCreator);
