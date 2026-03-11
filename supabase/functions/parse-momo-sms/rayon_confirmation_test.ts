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

Deno.test("ticket confirmation becomes idempotent after the first callback", () => {
  const first = planRayonTicketConfirmation("pending");
  const replay = planRayonTicketConfirmation(first.nextStatus);

  assertEquals(
    first.nextStatus,
    "valid",
    "first callback should validate ticket",
  );
  assertEquals(
    first.pointsToAward,
    ticketPoints(),
    "first callback should award ticket points",
  );
  assert(first.shouldSendWhatsApp, "first callback should send confirmation");

  assertEquals(
    replay.nextStatus,
    "valid",
    "replayed callback keeps valid status",
  );
  assertEquals(
    replay.pointsToAward,
    0,
    "replayed callback must not re-award points",
  );
  assert(
    !replay.shouldSendWhatsApp,
    "replayed callback must not resend confirmation",
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

Deno.test("shop order confirmation becomes idempotent after the first callback", () => {
  const first = planRayonShopOrderConfirmation("pending", 12500);
  const replay = planRayonShopOrderConfirmation(first.nextStatus, 12500);

  assertEquals(
    first.nextStatus,
    "paid",
    "first callback should mark order as paid",
  );
  assertEquals(
    first.pointsToAward,
    shopPoints(12500),
    "first callback should award shop points",
  );
  assert(
    first.shouldSendWhatsApp,
    "first callback should send order confirmation",
  );

  assertEquals(
    replay.nextStatus,
    "paid",
    "replayed callback keeps paid status",
  );
  assertEquals(
    replay.pointsToAward,
    0,
    "replayed callback must not re-award shop points",
  );
  assert(
    !replay.shouldSendWhatsApp,
    "replayed callback must not resend shop confirmation",
  );
});

Deno.test("paid and fulfilled shop orders do not regress on duplicate callbacks", () => {
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
    "first callback should update initiative totals",
  );
  assertEquals(
    first.pointsToAward,
    supportPoints(3000),
    "first callback should award support points",
  );
  assert(
    first.shouldSendWhatsApp,
    "first callback should send support confirmation",
  );

  assert(
    !replay.shouldIncrementInitiativeTotals,
    "replayed callback must not increment initiative totals again",
  );
  assertEquals(
    replay.pointsToAward,
    0,
    "replayed callback must not re-award support points",
  );
  assert(
    !replay.shouldSendWhatsApp,
    "replayed callback must not resend support confirmation",
  );
});
