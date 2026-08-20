# Bank-transfer UAT execution report

Date: 20 August 2026

| Journey | Automated result | Production evidence still required |
| --- | --- | --- |
| Create group and manage members | Pass | Authenticated production walkthrough |
| Create EUR transfer request | Pass | Production beneficiary enabled |
| Copy exact bank details/reference | Pass | Checker-approved real details |
| Open Revolut without claiming success | Pass | Physical-device handoff |
| Ingest bank SMS/email evidence | Pass | Real governed message source |
| Import daily statement | Pass | Real bank statement |
| Reconcile exact receipt | Pass | Production match record |
| Post balanced immutable journal | Pass | Production journal readback |
| Resolve exception/maker-checker allocation | Pass | Independent operator walkthrough |
| Send notification | Pass locally | FCM/APNs delivery proof |

Synthetic fixtures contain no production customer data or credentials. The UAT
is complete only when the real receipt-to-notification chain is captured and
approved.
