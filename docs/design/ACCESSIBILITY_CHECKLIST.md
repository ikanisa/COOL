# Collect Accessibility Checklist

## Visual

- Light and dark themes use contrast-safe text and status colors.
- Status always includes text and an icon, never color alone.
- Focus, hover, pressed, and disabled states come from component tokens.
- Components avoid text overlap at large text sizes.

## Interaction

- Interactive targets are at least 44 px in Flutter logical pixels.
- Forms have labels and helper text for sensitive fields.
- Admin actions remain reachable by keyboard and screen reader.
- QR/share/copy actions expose semantic labels.

## Motion

- Motion is subtle, tokenized, and disabled or shortened when `MediaQuery.disableAnimations` is true.
- Loading states avoid flashing and preserve layout.

## Content

- Payment instructions state that Collect does not move money.
- Public/private/anonymity states are explicit.
- Raw SMS, phone numbers, and MOMO numbers are never exposed on public screens.
- Error states explain the next safe action.

## Validation

- Run widget tests for labels, status text, and route smoke.
- Test light and dark theme construction.
- Manually inspect dynamic text for home, payment, ledger, receiver, and admin screens.
