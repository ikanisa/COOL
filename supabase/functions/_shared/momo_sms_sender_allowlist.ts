export function normalizeMomoSmsSenderToken(value: string): string {
  return value.toLowerCase().trim().replaceAll(/[^a-z0-9]/g, "");
}

export type ApprovedMomoSmsSenderRow = {
  sender_token?: string | null;
  sender_display?: string | null;
};

export async function loadApprovedMomoSmsSenderTokens(
  queryApprovedSenders: () => Promise<{
    data: ApprovedMomoSmsSenderRow[] | null;
    error: { message?: string } | null;
  }>,
): Promise<Set<string>> {
  const { data, error } = await queryApprovedSenders();
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
