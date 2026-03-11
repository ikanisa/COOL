type RayonTicketStatus = "valid" | "used";
type RayonShopOrderStatus = "paid" | "fulfilled" | "packed";

type ConfirmationPlan<TStatus extends string> = {
  nextStatus: TStatus;
  wasAlreadyConfirmed: boolean;
  pointsToAward: number;
  shouldSendWhatsApp: boolean;
};

export type RayonInitiativeConfirmationPlan = ConfirmationPlan<"confirmed"> & {
  shouldIncrementInitiativeTotals: boolean;
};

function normalizeStatus(status: string | null | undefined): string {
  return (status ?? "").trim().toLowerCase();
}

export function ticketPoints(): number {
  return 50;
}

export function shopPoints(totalAmount: number): number {
  return Math.floor(Math.max(totalAmount, 0) / 100);
}

export function supportPoints(amount: number): number {
  return Math.floor(Math.max(amount, 0) / 100) * 2;
}

export function planRayonTicketConfirmation(
  currentStatus: string | null | undefined,
): ConfirmationPlan<RayonTicketStatus> {
  const normalizedStatus = normalizeStatus(currentStatus);
  const wasAlreadyConfirmed = normalizedStatus === "valid" ||
    normalizedStatus === "used";

  return {
    nextStatus: normalizedStatus === "used" ? "used" : "valid",
    wasAlreadyConfirmed,
    pointsToAward: wasAlreadyConfirmed ? 0 : ticketPoints(),
    shouldSendWhatsApp: !wasAlreadyConfirmed,
  };
}

export function planRayonShopOrderConfirmation(
  currentStatus: string | null | undefined,
  totalAmount: number,
): ConfirmationPlan<RayonShopOrderStatus> {
  const normalizedStatus = normalizeStatus(currentStatus);
  const wasAlreadyConfirmed = [
    "confirmed",
    "fulfilled",
    "packed",
    "paid",
  ].includes(normalizedStatus);

  const nextStatus: RayonShopOrderStatus = normalizedStatus === "fulfilled"
    ? "fulfilled"
    : normalizedStatus === "packed"
    ? "packed"
    : "paid";

  return {
    nextStatus,
    wasAlreadyConfirmed,
    pointsToAward: wasAlreadyConfirmed ? 0 : shopPoints(totalAmount),
    shouldSendWhatsApp: !wasAlreadyConfirmed,
  };
}

export function planRayonInitiativeConfirmation(
  currentStatus: string | null | undefined,
  amount: number,
): RayonInitiativeConfirmationPlan {
  const wasAlreadyConfirmed = normalizeStatus(currentStatus) === "confirmed";

  return {
    nextStatus: "confirmed",
    wasAlreadyConfirmed,
    shouldIncrementInitiativeTotals: !wasAlreadyConfirmed,
    pointsToAward: wasAlreadyConfirmed ? 0 : supportPoints(amount),
    shouldSendWhatsApp: !wasAlreadyConfirmed,
  };
}
