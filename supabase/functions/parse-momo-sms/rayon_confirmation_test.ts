import {
  planRayonInitiativeConfirmation,
  planRayonShopOrderConfirmation,
  planRayonTicketConfirmation,
  shopPoints,
  supportPoints,
  ticketPoints,
} from "./rayon_confirmation.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

Deno.test("ticket confirmation becomes idempotent after the first SMS confirmation", () => {
  const first = planRayonTicketConfirmation("pending");
  const replay = planRayonTicketConfirmation(first.nextStatus);

  assertEquals(
    first.nextStatus,
    "valid",
    "first confirmation should validate ticket",
  );
  assertEquals(
    first.pointsToAward,
    ticketPoints(),
    "first confirmation should award ticket points",
  );
  assert(
    first.shouldSendWhatsApp,
    "first confirmation should send confirmation",
  );

  assertEquals(
    replay.nextStatus,
    "valid",
    "replayed confirmation keeps valid status",
  );
  assertEquals(
    replay.pointsToAward,
    0,
    "replayed confirmation must not re-award points",
  );
  assert(
    !replay.shouldSendWhatsApp,
    "replayed confirmation must not resend confirmation",
  );
});

Deno.test("used tickets stay used on duplicate confirmations", () => {
  const confirmation = planRayonTicketConfirmation("used");

  assertEquals(
    confirmation.nextStatus,
    "used",
    "used tickets must remain used",
  );
  assertEquals(
    confirmation.pointsToAward,
    0,
    "used tickets must not receive duplicate points",
  );
  assert(
    !confirmation.shouldSendWhatsApp,
    "used tickets must not resend confirmation",
  );
});

Deno.test("shop order confirmation becomes idempotent after the first SMS confirmation", () => {
  const first = planRayonShopOrderConfirmation("pending", 12500);
  const replay = planRayonShopOrderConfirmation(first.nextStatus, 12500);

  assertEquals(
    first.nextStatus,
    "paid",
    "first confirmation should mark order as paid",
  );
  assertEquals(
    first.pointsToAward,
    shopPoints(12500),
    "first confirmation should award shop points",
  );
  assert(
    first.shouldSendWhatsApp,
    "first confirmation should send order confirmation",
  );

  assertEquals(
    replay.nextStatus,
    "paid",
    "replayed confirmation keeps paid status",
  );
  assertEquals(
    replay.pointsToAward,
    0,
    "replayed confirmation must not re-award shop points",
  );
  assert(
    !replay.shouldSendWhatsApp,
    "replayed confirmation must not resend shop confirmation",
  );
});

Deno.test("paid and fulfilled shop orders do not regress on duplicate confirmations", () => {
  const paidReplay = planRayonShopOrderConfirmation("paid", 9200);
  const fulfilledReplay = planRayonShopOrderConfirmation("fulfilled", 9200);

  assertEquals(paidReplay.nextStatus, "paid", "paid orders stay paid");
  assertEquals(
    fulfilledReplay.nextStatus,
    "fulfilled",
    "fulfilled orders stay fulfilled",
  );
  assertEquals(
    paidReplay.pointsToAward,
    0,
    "paid orders must not receive duplicate points",
  );
  assertEquals(
    fulfilledReplay.pointsToAward,
    0,
    "fulfilled orders must not receive duplicate points",
  );
});

Deno.test("initiative contribution confirmation increments totals only once", () => {
  const first = planRayonInitiativeConfirmation("pending", 3000);
  const replay = planRayonInitiativeConfirmation(first.nextStatus, 3000);

  assert(
    first.shouldIncrementInitiativeTotals,
    "first confirmation should update initiative totals",
  );
  assertEquals(
    first.pointsToAward,
    supportPoints(3000),
    "first confirmation should award support points",
  );
  assert(
    first.shouldSendWhatsApp,
    "first confirmation should send support confirmation",
  );

  assert(
    !replay.shouldIncrementInitiativeTotals,
    "replayed confirmation must not increment initiative totals again",
  );
  assertEquals(
    replay.pointsToAward,
    0,
    "replayed confirmation must not re-award support points",
  );
  assert(
    !replay.shouldSendWhatsApp,
    "replayed confirmation must not resend support confirmation",
  );
});
