// BuriMunsi payment receipt v2. The original recorded-savings wording discloses
// only the recipient's own immutable post-payment balance.
export const paymentSmsTemplate = Object.freeze({
  template_key: 'buri_munsi.payment_received',
  version: 2,
  locale: 'rw',
  kind: 'receipt',
  body: 'BuriMunsi: Ubwizigame bwa {{amount}} RWF bwanditswe. Igiteranyo cyawe cyanditswe muri iri tsinda ku {{recorded_at}}: {{member_balance}} RWF. Ref: {{reference}}.',
  variables: Object.freeze({ amount: 'text', recorded_at: 'datetime', member_balance: 'text', reference: 'text' }),
});

const kigali = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Africa/Kigali', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
});

function formattedRwf(value, min) {
  if (!Number.isSafeInteger(value) || value < min) throw Error('invalid_payment_sms_amount');
  return String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

export function paymentSmsVariables({ amount, memberBalance, recordedAt, reference }) {
  const time = typeof recordedAt === 'string' ? Date.parse(recordedAt) : NaN;
  if (!Number.isFinite(time) || !/^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$/.test(reference ?? '')) {
    throw Error('invalid_payment_sms_reference');
  }
  return {
    amount: formattedRwf(amount, 1),
    recorded_at: new Date(time).toISOString(),
    member_balance: formattedRwf(memberBalance, 0),
    reference,
  };
}

export function renderPaymentSms(facts) {
  const variables = paymentSmsVariables(facts);
  const pieces = Object.fromEntries(kigali.formatToParts(new Date(variables.recorded_at))
    .filter(({ type }) => type !== 'literal').map(({ type, value }) => [type, value]));
  const local = pieces.year + '-' + pieces.month + '-' + pieces.day + ' ' + pieces.hour + ':' + pieces.minute + ' CAT';
  return paymentSmsTemplate.body.replace(/\{\{([a-z_]+)\}\}/g,
    (_, field) => field === 'recorded_at' ? local : variables[field]);
}
