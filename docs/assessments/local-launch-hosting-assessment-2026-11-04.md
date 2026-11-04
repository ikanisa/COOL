# Collect launch: local hosting and staged growth assessment

**Date:** 4 November 2026  
**Purpose:** Decision support for a staff-managed initial launch in which members do not need to install the Collect mobile app.  
**Status:** Assessment and recommendations; not a deployment decision, implementation plan approval, or production-readiness certification.

## Executive recommendation

Use a **controlled, locally operated pilot** as the preferred launch direction, subject to the gates below: Collect's production database, backend, Admin and required SMS components on dedicated infrastructure at the operating site; staff access over a private network; no requirement for a member app; and a deliberately limited, verified assisted-service journey. Retain mobile-network connectivity for SMS and external payment rails, and an independently protected off-site recovery copy. Defer public app marketing and general self-service until there is demonstrated demand and the customer journeys and operations are ready.

This is a recommendation for a **new launch scope**, not proof that the current system can be deployed in that form today. If the team cannot provide dependable operating ownership, tested backups and recovery, physical security and the other launch controls, choose managed hosting for the backend or a qualified local data centre instead. A single office computer with no restore test is a poor home for live financial and identity records regardless of user count.

Local hosting offers control over data placement and can keep staff working through an internet outage if the actual application and authentication are engineered and tested for it. It also transfers infrastructure, security and recovery duties to Collect. It does not remove dependence on a mobile carrier, payment provider or electricity, and it does not itself satisfy privacy, financial or telecom requirements.

## 1. What “local” means for this decision

| Layer | Proposed launch boundary | Qualification |
| --- | --- | --- |
| Business database, Auth, application API, files and jobs | Self-hosted at the operating site or a specifically chosen local facility | A real hardened production deployment and operational ownership are needed. |
| Admin | Served locally and restricted to approved staff on the private network; controlled remote access only if needed | A local frontend option exists, but installed end-to-end acceptance and an explicit change to the earlier Cloudflare Admin criterion are still needed. |
| Member channel | Staff-assisted onboarding and support, SMS notifications, payment through the actual approved payment channel | SMS interaction, account inquiries or commands must be specified and verified before claiming they exist. |
| SMS service | Local gateway software and approved staff-operated handset/SIM or an approved provider | The carrier network, signal, number, SIM, airtime and potentially aggregator are external. Local software does not guarantee delivery. |
| Face enrollment | Potentially local capture and processing, **if justified and verified** | The inspected Collect paths did not establish an existing working face-enrollment implementation or where face data is stored. Confirm exact component and data flows. |
| Backups | Encrypted separate copies, at least one protected off-site, with independent key custody | Physical separation can remain within Rwanda if that is the chosen residency policy; agree retention, recovery, and legal basis. |
| Updates and supporting services | Controlled connectivity where needed | Current production package requires real SMTP and Cloudflare Turnstile; its documented production TLS setup also uses public certificate issuance. True internet-independent operation needs redesign and testing. |

**On-premises is not the same as disconnected.** A local data centre is self-hosted and potentially in-country, but is not physically at the office and requires a network link to reach it. A genuinely air-gapped system cannot use mobile network SMS or external payment rails. This report recommends local operation with controlled external dependencies, not an air-gapped financial service.

## 2. What the current Collect evidence actually shows

The [self-hosted README](../../deploy/self-hosted/README.md) describes a 13-service Compose deployment, a local Node/Caddy Admin option, PostgreSQL-backed application and gateway state, and a profile-based configuration. It describes a Linux/Docker host path and separate backup and recovery tooling. This is useful implementation groundwork, but the [qualification status](../implementation/self-hosted-20261101/task-status.md) records tests using actual PostgreSQL with Auth, provider and native-service doubles; the recorded 152 scenarios had no real provider calls. Its dated record says there was no live deployment, real provider message, physical SIM/device acceptance, complete physical restore or production cutover during that pass. Those statements should not be read as a current infrastructure inventory or proof that nothing happened elsewhere since then.

The same status says positive import into the current 102-table schema remains unsupported: the historical promoter refuses the newer target. A genuinely empty new launch may avoid that specific import, but still needs controlled initialization and verification; an existing populated installation requires a proven migration, original key custody, reconciliation and a single-writer cutover. A fresh installer must not be used as an in-place migration.

The [Admin status](../implementation/self-hosted-20261101/admin-status.md) records qualification builds and functional components; the real staff role/route and populated financial workflows still need acceptance. The current production package requires SMTP and Turnstile; simply changing DNS or isolating the LAN does not prove that login, account recovery, challenge flows, certificates or job execution will work offline. The production profile described in the package rejects its internal TLS mode. Therefore the proposed private-LAN production model requires a deliberate security, certificate and configuration design and its own tests.

The existing 36-item acceptance record preserves an Admin-on-Cloudflare criterion. Adopting local Admin for the pilot needs an explicit owner decision and an updated launch-specific acceptance scope; it does not retroactively pass that criterion or erase other relevant financial, security and recovery work. Deferring the public app may defer some store-distribution work, but a staff gateway or receiver still needs its own signed/installable build, physical-device qualification, access controls and maintenance.

## 3. Comparison of realistic options

| Dimension | A. On-site local stack | B. Self-hosted in a local data centre | C. Managed cloud/backend and hosted Admin | D. Hybrid: local operational core plus limited hosted services |
| --- | --- | --- | --- | --- |
| Data location | Direct physical control, if backups and providers also follow policy | Depends on facility, subcontractors and backups | Depends on selected region and provider terms | Depends on exactly which records and copies leave the site |
| Staff work during office internet loss | Potentially continues on LAN; must prove auth, DNS, certificates and app dependencies | Generally stops if site link fails | Generally stops if site link fails | Only functions designed and tested to remain local continue |
| Power/site failure | Office and server may fail together | Facility redundancy may improve resilience; verify contract | Provider infrastructure may improve resilience, but internet remains a dependency | Depends on failover design; two copies do not automatically create a safe second writer |
| Responsibility | Collect owns nearly all infrastructure and recovery | Collect manages stack; facility may own power/network/hardware under contract | Provider operates more infrastructure; Collect still owns application security, data, configurations and provider integration | Highest boundary complexity and shared responsibilities |
| Security exposure | Can keep Admin private; physical and insider risks remain | Private connectivity and hardening needed | Internet exposure and provider configuration require careful controls | Extra paths, keys and synchronization create more failure modes |
| Cost profile | Equipment, power, replacement, monitoring and operator time; potentially low platform fees | Recurring facility, support and connectivity costs | Recurring platform, connectivity, backup and provider fees; lower infrastructure workload | Both local and hosted costs, plus integration and reconciliation |
| Recovery | Only as good as the actual backup, keys, spare capacity and rehearsed process | Facility service levels do not replace Collect recovery | Plan-dependent managed capabilities help, but application files and integrations still need coverage | Recovery requires clear data authority and conflict handling |
| Fit at launch | **Best fit if local operations can meet the gates** | Good alternative if reliable local operational support/facility exists | Strong alternative if no competent local operations team | Reserve for a justified resilience or access need; avoid unnecessary replication at first |

Supabase says self-hosted installations do not include its managed backups and point-in-time recovery, and self-hosters are responsible for hardening, Postgres maintenance, monitoring, availability and disaster recovery. Its CLI development stack is not a hardened production deployment. [Supabase self-hosting](https://supabase.com/docs/guides/self-hosting). Managed service does not eliminate Collect's responsibility for access control, correct business logic and external services. [Supabase shared responsibility](https://supabase.com/docs/guides/deployment/shared-responsibility-model).

### Decision under the owner's priorities

- **Choose A for a small, staff-operated pilot** only when a named primary and backup operator, a secure site, power protection, independent recoverable backups and the specific end-to-end acceptance gates are funded and available.
- **Choose B** if in-country custody matters but the office cannot maintain reliable power, physical security or around-the-clock operational response. Confirm actual facility and contract rather than assuming residency or service levels.
- **Choose C** if continuity and a small operations team matter more than physical control. Evaluate provider location, contracts and all copies. Cloud hosting still cannot make carrier or payment services available during their own outage.
- **Choose D later**, for example for a public information site or encrypted remote backup. Keep one authoritative financial writer. Do not promise active-active financial operation without a separately engineered, tested failover and reconciliation design.

## 4. Member journey without a member app

Not requiring an app is feasible as a **product and operations choice**, but the exact service cannot be inferred from an outbound SMS gateway. Distinguish:

1. **Gateway SMS:** a staff-controlled sender sends an OTP or notification. An accepted queue item is not evidence of handset send or recipient delivery.
2. **Dedicated receiver:** a separately configured installation may receive messages delivered to its own number, subject to actual permissions and device behavior.
3. **Member app capture:** the existing member Android path captures eligible incoming MoMo messages on that member's own phone after permission. A staff gateway cannot automatically read a member's private incoming payment SMS.
4. **Two-way member SMS:** members send commands, inquiries or requests to a service number and receive responses. This is a separate product workflow; the inspected evidence does not establish its end-to-end implementation or readiness.

See [Android SMS access](../ANDROID_SMS_ACCESS.md) and the [gateway README](../../deploy/collect-sms/README.md). The source explicitly treats captured messages as candidate evidence, not standalone proof of settlement. A phone message, parser success or SMS acknowledgment must not be represented as a verified payment without the applicable Collect financial controls.

**Recommended pilot journey:** staff identify and enroll a member using a reviewed non-app procedure; record group membership and an appropriate reachable number; member makes a payment using the permitted external payment channel under the agreed operating model; staff or the authorized receiving process records the evidence that actually reaches it; Collect validates and reconciles it under its approved financial rules; an authorized operation posts it once; the member receives an accurate confirmation when the outbound channel actually succeeds. Provide a staff-supported route for a member to inquire, dispute an entry or correct a number. Never ask staff to collect a member's mobile-money PIN or OTP.

Before implementation freeze, define who pays, which account receives funds, which phone receives the provider evidence, how payer and beneficiary are matched, who can post or correct, what happens when a message is ambiguous or delayed, and what the member sees if notification fails. If members send a text message as an instruction, specify its commands, authentication, fees, language, error handling, queueing and limits separately. SMS sender numbers can be spoofed or reassigned and are not sufficient sole proof of authority for sensitive account changes or financial instructions. [NIST authentication guidance](https://pages.nist.gov/800-63-4/sp800-63b.html) treats PSTN-based authentication as restricted; it is a risk reference here, not a statement of Rwandan law.

A carrier/payment outage can delay transactions or confirmations even if the LAN is healthy. If the server or evidence path fails, record a clearly identifiable pending case through the approved incident procedure and reconcile original evidence before any posting or resend. Do not invent a successful payment, silently discard an uncertain send, or run two independent ledgers as though they were synchronized.

## 5. Face enrollment and privacy

The user describes local face enrollment, but the inspected Collect application, self-hosted deployment and function paths did not establish the exact component or a production-ready enrollment/matching flow. Confirm whether this means a photograph, an identity-verification service, biometric template extraction, face matching, liveness, or merely local capture; also identify camera device, processing location, staff access, retention, backups and whether third parties receive data.

**Recommendation:** do not make biometric enrollment a prerequisite for the pilot unless a documented need and legal basis justify it and the real workflow is separately qualified. Use an appropriate accessible non-biometric assisted alternative. If adopted, minimize collected data, restrict access, encrypt and independently protect keys, document deletion and backup retention, test quality and demographic performance, and provide a human-review and correction route. No inference about accuracy or liveness can be drawn from the phrase “local face enrollment.”

Rwanda's Data Protection and Privacy Office describes biometric information, including facial recognition used for unique identification, as sensitive personal data. Its [guidance](https://dpo.gov.rw/faqs) also addresses controller/processor registration and data-subject obligations. The accountable organization should obtain Rwanda-specific legal review of the actual processing, applicable sensitive-data grounds, notices, registration, retention, security, data-subject rights, breach procedures and any cross-border transfers. Storing the primary database locally does not resolve copies on devices, backups, SMS carriers, support tools or service providers.

For SMS, [RURA's bulk-SMS notice](https://www.rura.rw/index.php?eID=dumpFile&f=113022&t=f&token=bc9ec86d293bc6f495467cb1c6746af0dbf2caca) is relevant where the proposed activity is bulk messaging. Do not assume that every transactional text is bulk SMS or that a local SIM gateway automatically has the required permissions: confirm the actual use, number/short code, volume, inter-network reach, commercial terms and any approvals with RURA and the operators. The regulatory characterization of payment activities and partners also depends on the actual business model; hosting does not determine it. [National Bank of Rwanda payment systems](https://www.bnr.rw/paymentsystems).

## 6. Minimum operational design for the local pilot

- **Host and power:** a dedicated, supported Linux server with monitored storage, UPS and a tested orderly shutdown/startup; protected router, staff endpoints and gateway handset. Size using actual workload, growth and restore tests. Supabase's general recommended starting point is 4 CPU cores, 8 GB RAM and 80 GB SSD, but that is not a Collect capacity estimate or a high-availability guarantee. [Supabase Docker requirements](https://supabase.com/docs/guides/self-hosting/docker).
- **Network and identity:** isolate Admin and infrastructure on a controlled LAN; no public database, Studio or staff Admin. Use unique staff identities, least privilege, session controls, MFA appropriate to the operating environment, access revocation and review. Design and test DNS, trusted HTTPS certificates, enrollment and account recovery for the actual network; do not disable controls simply to make the LAN work.
- **SMS availability:** secure, powered and monitored gateway handset/SIM, carrier coverage and airtime, appropriate permission and device management, delivery-state tracking, and a rehearsed secondary device/provider path. Hold ambiguous deliveries for reconciliation, not blind resend. A spare SIM or phone is only useful after configuration, authority and failover behavior are proven.
- **Backup and restore:** define owners and targets for database, stored files, configuration, versioned deployment artifacts, authentication/session dependencies, encryption and signing keys, gateway/outbox state and financial evidence. Use encrypted, access-controlled, separately held copies, with an off-site copy protected from the same incident and destructive credentials. Perform a full populated restore on separate hardware, then test Admin login, file access, balances, evidence, queued and uncertain messages, and reconciliation. A database dump alone is not a complete recovery strategy.
- **Recovery targets:** approve an explicit recovery point objective (maximum tolerable data loss) and recovery time objective (maximum tolerable downtime) with the financial owner. As an **illustrative proposal to validate**, a pilot might target recovery within 4 business hours and at most 15 minutes of accepted data loss; these are not current capabilities or automatically appropriate. If losing any posted transaction is unacceptable, require a design that meets that requirement and accounts for unreplicated writes; scheduled daily backups alone cannot do so.
- **Operations:** name a primary and deputy for infrastructure, financial reconciliation and member support; document incident escalation and support coverage. Monitor backup success and restoreability, disk, certificate expiry, host/service health, gateway heartbeat, failed jobs, unknown sends, reconciliation backlog and power. Test patch/rollback, lost device, staff departure and key recovery. Decide maintenance windows and alerting that works for the responsible people.
- **Physical and data safety:** locked site, restricted hardware access, device encryption, protected backups and documented handling of data on staff phones. Record retention, access, deletion and breach-response duties across every copy.

## 7. Cost comparison: measure total cost, not subscription alone

Compare a 36-month total cost using the same launch volumes and service expectations. Obtain real supplier quotes; no Collect-specific price or savings are established by the inspected evidence.

**Local total** = server and spare equipment + UPS/network/security + setup and maintenance labor + electricity and connectivity + replacement/repair + SMS/telecom + monitoring + backup media or facility + support + expected incident/recovery costs.

**Managed total** = recurring database/compute/hosting + storage, backup and recovery options + egress + internet + support + SMS/telecom + configuration and security labor + any local devices and incident costs. Do not assume a free plan includes required production reliability or recovery.

For a simple comparison, amortize one-time setup over 36 months and add monthly recurring and realistically costed operator hours. For example, if one-time expenditure is **X**, recurring costs are **Y/month**, and operations are **H hours/month at R/hour**, the indicative monthly equivalent is **X/36 + Y + H×R**. Compare this with the same formula for managed hosting; include any service-level differences and end-of-term replacement. Run low/base/high cases for transaction volume, messages, staff support, failure and capacity, then compare actual quotes in the same currency. This formula is not a forecast.

## 8. Staged rollout and decision gates

| Stage | Scope | Evidence needed before moving forward |
| --- | --- | --- |
| 0. Specify and narrow | Confirm no-app member journey, financial authority, local face use or deferral, real sites, responsible staff, residency and downtime tolerance. Explicitly adopt local Admin as launch scope while preserving the historical acceptance record. | Approved journey and service boundaries; named owners; regulatory/provider review; budget and service targets. |
| 1. Private qualification | Install exact candidate on a representative local host. Test production-equivalent auth, certificates, Admin roles, SMS handset, power/internet failure, key custody, scheduler and full restore with representative non-live data. | End-to-end evidence, including original transaction and unknown-send reconciliation; independent role/security review; successful populated restore and measured RPO/RTO. |
| 2. Controlled pilot | Small defined member cohort, staff-managed operations and approved partner rails; no public-app dependency. Restrict features to what has passed acceptance, with service hours and incident process. | Actual authorized device/SIM and provider delivery tests; financial reconciliation and correct statements; staff training, support and owner acceptance; daily operational oversight. |
| 3. Expand operations | Add staff/site capacity after observing real load and incidents; add local facility, redundant power/network or a backup gateway where justified. | Measured availability, recovery drills, backlog and response times, access reviews, funding and evidence that change does not create competing writers. |
| 4. Optional wider services | Consider remote staff access, hosted public information, app distribution or an online member service only where demand and operational capacity support it. | New threat model, provider/legal review, data-location map, accessible user flows, authenticated transactions and channel-specific production acceptance. |

The stage numbers express dependencies, not calendar promises. Define cohort size, acceptable losses and service hours with the owner; none is established by this assessment.

## 9. Launch-blocking questions and acceptance

1. Which entity operates Collect, which members and groups are included, and what exact financial activity and partner arrangements are authorized?
2. Is launch a truly empty database or must existing accounts, balances, evidence and keys migrate? If populated, positive current-schema import, reconciliation, cutover and rollback/recovery must be demonstrated.
3. What exact server, location, staff, uptime coverage, internet and power arrangements are available? Who is the deputy when the primary operator is absent?
4. Which exact phone/SIM and gateway installations receive and send each message type? Can the real carrier, provider and members support the intended volumes and networks?
5. What SMS member interactions are actually required? Which identity check, payment evidence, posting authorization and dispute/correction process applies to each?
6. Is face enrollment mandatory, and what software, biometric purpose, lawful basis, alternative and retention apply? If these cannot be answered and validated, defer the feature.
7. What RPO/RTO and financial loss are acceptable, and has the complete system been restored and checked against them on a separate target?
8. Which existing production requirements can be deferred for the no-public-app pilot, and which remain applicable? Record the owner's scope decision and do not relabel historical checks as complete.

## Sources and limits

Repository sources: [self-hosted deployment](../../deploy/self-hosted/README.md), [qualification status](../implementation/self-hosted-20261101/task-status.md), [Admin status](../implementation/self-hosted-20261101/admin-status.md), [Android SMS access](../ANDROID_SMS_ACCESS.md), and [Collect SMS gateway](../../deploy/collect-sms/README.md). They contain dated, source-specific local evidence and are not independent proof of today's live infrastructure. The working tree contained pre-existing changes during this review; this assessment did not modify or validate those changes. Official external sources are linked next to the claims they support. Legal and licensing conclusions require review against the actual operational facts and current applicable instruments.
