export type BuriMunsiReceiptSnapshot = {
  amount_rwf: number;
  member_balance_rwf: number;
  group_balance_rwf: number;
  reference: string;
};

export const BURI_MUNSI_RECEIPT_TEMPLATE = "buri_munsi.payment_received.v1";

/** Render a backend-owned ledger snapshot; never calculate balances here.
 * This template is specific to Buri Munsi savings, not all Collect groups.
 * Rendering does not enqueue, authorize or send a message.
 */
export function renderBuriMunsiReceipt(
  snapshot: BuriMunsiReceiptSnapshot,
): string {
  for (
    const amount of [
      snapshot.amount_rwf,
      snapshot.member_balance_rwf,
      snapshot.group_balance_rwf,
    ]
  ) {
    if (!Number.isSafeInteger(amount) || amount < 0) {
      throw new Error("Invalid integer RWF receipt snapshot");
    }
  }
  if (
    snapshot.amount_rwf <= 0 ||
    !/^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$/.test(snapshot.reference)
  ) {
    throw new Error("Invalid receipt amount or reference");
  }
  const format = (amount: number) =>
    amount.toLocaleString("en-US", { maximumFractionDigits: 0 });
  return `BuriMunsi: Twakiriye ubwizigame bwawe bwa ${
    format(snapshot.amount_rwf)
  } RWF. Balance yawe: ${
    format(snapshot.member_balance_rwf)
  } RWF; balance y'itsinda: ${
    format(snapshot.group_balance_rwf)
  } RWF. Ref: ${snapshot.reference}.`;
}
