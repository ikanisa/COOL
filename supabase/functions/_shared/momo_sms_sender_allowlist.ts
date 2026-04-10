export function normalizeMomoSmsSenderToken(value: string): string {
  return value.toLowerCase().trim().replaceAll(/[^a-z0-9]/g, "");
}

export async function loadApprovedMomoSmsSenderTokens(
  adminClient: {
    from: (table: string) => {
      select: (columns: string) => {
        eq: (column: string, value: boolean) => {
          order: (column: string, options?: { ascending?: boolean }) => Promise<{
            data: Array<{ sender_token?: string | null; sender_display?: string | null }> | null;
            error: { message?: string } | null;
          }>;
        };
      };
    };
  },
): Promise<Set<string>> {
  const { data, error } = await adminClient
    .from("momo_sms_sender_allowlist")
    .select("sender_token, sender_display")
    .eq("active", true)
    .order("sort_order", { ascending: true });
  if (error) {
    throw error;
  }

  const tokens = new Set<string>();
  for (const row of data ?? []) {
    const rawToken = row.sender_token ?? row.sender_display ?? "";
    const normalizedToken = normalizeMomoSmsSenderToken(rawToken);
    if (normalizedToken.length > 0) {
      tokens.add(normalizedToken);
    }
  }
  return tokens;
}
