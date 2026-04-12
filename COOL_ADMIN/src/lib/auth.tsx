import {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
  type ReactNode,
} from "react";
import { supabase } from "@/lib/supabase";
import type { Session, User } from "@supabase/supabase-js";

/* ── Types ────────────────────────────────────────────────────────────── */

export interface AdminCapabilities {
  manage_platform: boolean;
  manage_users: boolean;
  manage_roles: boolean;
  manage_config: boolean;
  view_analytics: boolean;
  view_audit_log: boolean;
  view_groups: boolean;
  view_savings: boolean;
}

export interface AdminAccess {
  has_platform_access: boolean;
  has_bank_access: boolean;
  has_partner_access: boolean;
  has_legacy_admin_flag: boolean;
  bank_partner_ids: string[];
  partner_admin_ids: string[];
  role_assignments: Array<{
    id: string;
    role: string;
    partner_scope_id: string | null;
    partner_name: string | null;
    granted_at: string;
    is_active: boolean;
  }>;
  capabilities: AdminCapabilities;
}

interface AuthContextValue {
  user: User | null;
  session: Session | null;
  adminAccess: AdminAccess | null;
  loading: boolean;
  error: string | null;
  signOut: () => Promise<void>;
  refreshAdminAccess: () => Promise<void>;
}

const DEFAULT_CAPABILITIES: AdminCapabilities = {
  manage_platform: false,
  manage_users: false,
  manage_roles: false,
  manage_config: false,
  view_analytics: false,
  view_audit_log: false,
  view_groups: false,
  view_savings: false,
};

const DEFAULT_ACCESS: AdminAccess = {
  has_platform_access: false,
  has_bank_access: false,
  has_partner_access: false,
  has_legacy_admin_flag: false,
  bank_partner_ids: [],
  partner_admin_ids: [],
  role_assignments: [],
  capabilities: DEFAULT_CAPABILITIES,
};

/* ── Context ──────────────────────────────────────────────────────────── */

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [adminAccess, setAdminAccess] = useState<AdminAccess | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchAdminAccess = useCallback(async () => {
    try {
      const { data, error: rpcError } = await supabase.rpc(
        "get_admin_access_for_user"
      );
      if (rpcError) {
        console.error("Admin access RPC error:", rpcError.message);
        setAdminAccess(DEFAULT_ACCESS);
        return;
      }
      setAdminAccess(data as AdminAccess);
    } catch {
      console.error("Failed to fetch admin access");
      setAdminAccess(DEFAULT_ACCESS);
    }
  }, []);

  const refreshAdminAccess = useCallback(async () => {
    await fetchAdminAccess();
  }, [fetchAdminAccess]);

  useEffect(() => {
    // 1. Get initial session
    supabase.auth.getSession().then(({ data: { session: initialSession } }) => {
      setSession(initialSession);
      setUser(initialSession?.user ?? null);
      if (initialSession?.user) {
        fetchAdminAccess().finally(() => setLoading(false));
      } else {
        setLoading(false);
      }
    });

    // 2. Listen for auth changes
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
      setUser(newSession?.user ?? null);
      if (newSession?.user) {
        fetchAdminAccess();
      } else {
        setAdminAccess(null);
      }
    });

    return () => subscription.unsubscribe();
  }, [fetchAdminAccess]);

  const signOut = useCallback(async () => {
    setError(null);
    try {
      await supabase.auth.signOut();
      setUser(null);
      setSession(null);
      setAdminAccess(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Sign out failed");
    }
  }, []);

  return (
    <AuthContext.Provider
      value={{
        user,
        session,
        adminAccess,
        loading,
        error,
        signOut,
        refreshAdminAccess,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error("useAuth must be used inside <AuthProvider>");
  }
  return ctx;
}
