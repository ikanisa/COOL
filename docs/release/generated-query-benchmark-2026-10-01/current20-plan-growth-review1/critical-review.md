# Actual query plans and growth — scoped current20 benchmark

248 checks passed on genuine local maker/checker/finalizer postings at 1,000 and 10,000 rows, with all production triggers. Both clones were removed and the shared database/catalog/column grants/cron were preserved. This is synthetic mechanical evidence.

The outer current-source gate failed when the cancellation audit migration arrived. That refusal remains a failure; the captured20-stage correctness and plans remain usable scoped evidence.

## Page selection still scans the global payment set

The newest global first page returns50 items and materializes51 candidates, but its actual nested page plan examines every payment row. Full totals and revision computation necessarily read the matching data; this finding concerns the second page-selection scan.

| Volume | Matched | Returned | Summary ms / root hits | Page ms / root hits | Page payment rows examined |
|---:|---:|---:|---:|---:|---:|
| 1000 | 834 | 50 | 5.391 / 1443 | 3.292 / 117 | 1000 |
| 10000 | 8334 | 50 | 31.606 / 1855 | 6.194 / 525 | 10000 |

The10,000-row newest page has a sequential payment scan (8,334 rows accepted and1,666 filtered) followed by a top-N51 sort using34kB. Deep highest still examines10,000 rows (50 accepted and9,950 filtered). Bounded JSON output does not prove a bounded storage scan.

The same10,000-row readable-private newest first page uses `payments_history_collection_newest_idx`:51 payment rows,45 scan-node hits. The own-unreadable private first page examines100 payment rows with58 scan-node hits. Existing eight partial history indexes are prefixed by collection or contributor; the retained catalog has no global sort-prefix index.

## Measured growth in global history calls

Each number is the median of three uninstrumented local Docker/psql calls, including process startup. Independent nested auto_explain diagnostics capture query plans and buffers. These are neither hosted service latency nor p95/p99 or an approved service objective.

| Sort / depth | 1,000 median seconds | 10,000 median seconds | Page rows examined at10,000 |
|---|---:|---:|---:|
| newest / first | 0.060802 | 0.212181 | 10000 |
| newest / middle | 0.056091 | 0.119364 | 10000 |
| newest / deep | 0.054296 | 0.152923 | 10000 |
| oldest / first | 0.076132 | 0.143588 | 10000 |
| oldest / middle | 0.088836 | 0.185821 | 10000 |
| oldest / deep | 0.092092 | 0.168093 | 60 |
| highest / first | 0.075335 | 0.155464 | 10000 |
| highest / middle | 0.080492 | 0.200251 | 10000 |
| highest / deep | 0.075379 | 0.132350 | 10000 |
| lowest / first | 0.116926 | 0.178488 | 10000 |
| lowest / middle | 0.077669 | 0.131315 | 10000 |
| lowest / deep | 0.109171 | 0.155569 | 10000 |

## Required local correction and verification

Compare an isolated global four-sort partial-index candidate against the identical generated production query, dataset and authorization. Require exact known IDs/ties/pages/counts/full and own sums, hidden/foreign/anonymous privacy, and actual stale/fresh cursors. Retain raw plans and prove reduced page scanning/buffers for first, middle and deep windows. Publish an additive migration only after that comparison demonstrates correctness and benefit.

An index alone may leave deep cursors scanning from the beginning if the keyset predicate remains a filter. Actual index conditions and rows examined must decide the result. Complete totals/revision scans and search costs must remain explicit; an improved page window does not remove them.

All216 actual history measurements, query hashes, payment scan nodes, sort memory observations and root buffers are in `plan-growth.json`. Root buffer totals are not added to child totals. Three samples and warm-cache zero-read plans cannot certify cold-cache behavior, peak memory, production hardware or settlement.
