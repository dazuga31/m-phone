# Kiosk POS App

The Kiosk module connects a compact in-world POS surface to `m-business:KioskCheckout`.

## Internal flow

- WebUI submits `kioskPay` with selected IDs, quantity, payment method, and request ID.
- The client forwards `m-phone:kioskPay` to the server.
- The server delegates checkout to the Business adapter.
- `m-phone:kioskPayResult` returns the normalized result.

Pricing, VAT, stock, payment, item delivery, business credit, and rollback are server-authoritative in `m-business`. This module is presentation transport only.
