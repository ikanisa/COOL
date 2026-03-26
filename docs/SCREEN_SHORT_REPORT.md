# Screen Short Report

Short, screen-by-screen summary of the implemented app UI surface.

Each entry includes:
- screen name
- route if the screen is GoRouter-addressable
- a short UI/UX description of what the screen is for

## Auth And Entry

| Screen | Route | Short Description |
|---|---|---|
| `SplashScreen` | `/` | Startup gate that handles initial brand presentation, session restore, and first navigation routing. |
| `OnboardingScreen` | `/onboarding` | Introductory marketing/onboarding screen that explains the app value and pushes users into authentication. |
| `OtpScreen` | `/otp` | Phone number capture screen with a focused, low-friction OTP request flow. |
| `OtpVerifyScreen` | `/otp-verify` | Verification screen for entering and confirming the OTP code with a simple, trust-first auth UI. |
| `RegisterScreen` | `/register` | New-user profile setup screen that collects the minimum identity details required to activate the account. |
| `AppAccessOnboardingScreen` | `/app-access` | Access-approval entry screen that explains availability or rollout access and guides the user to the next allowed step. |

## Core Status

| Screen | Route | Short Description |
|---|---|---|
| `CoolTokensScreen` | `/tokens` | Gamification/status screen that shows token balances, progress, and reward-oriented engagement data. |
| `MissionsScreen` | `/missions` | Missions hub where users browse active tasks, progress states, and reward opportunities. |
| `ReferralHubScreen` | `/referral` | Referral center that helps users share invite links/QR codes and understand referral rewards. |

## Admin

| Screen | Route | Short Description |
|---|---|---|
| `AdminWorkspacesScreen` | `/admin` | Admin landing screen that routes staff into the correct workspace or control area. |
| `AdminDashboardScreen` | `/admin/platform` | High-level platform command screen summarizing system health, activity, and major admin actions. |
| `AuditLogScreen` | `/admin/audit-log` | Operational trace screen for reviewing administrative actions and accountability records. |
| `OperationalDashboardScreen` | `/admin/operations` | Monitoring screen for live platform operations, triage, and operational readiness signals. |
| `SystemAnalyticsScreen` | `/admin/analytics` | Analytics dashboard for platform-wide trends, KPIs, and decision-support metrics. |
| `ManageUsersScreen` | `/admin/users` | User management screen for browsing, filtering, and acting on user accounts. |
| `ManagePartnersScreen` | `/admin/partners` | Partner catalog management screen for reviewing and editing partner entities in the platform. |
| `PartnerAdminWorkspaceScreen` | `/admin/partners/:partnerId` | Scoped partner workspace for managing a single partner’s settings, content, and operational surfaces. |
| `BankAdminWorkspaceScreen` | `/admin/banks/:partnerId` | Bank-specific operations screen for allocation, ledger review, and savings/group administration. |
| `ManageServicesScreen` | `/admin/services` | Service configuration screen for editing service cards, availability, and action behavior. |
| `ManageQuickActionsScreen` | `/admin/quick-actions` | Admin tool for curating shortcut actions and surfaced utility flows in the app shell. |
| `ManageAppConfigScreen` | `/admin/app-config` | Central application configuration screen for rollout flags, runtime settings, and scoped config values. |
| `ManageMissionsScreen` | `/admin/missions` | Mission authoring and control screen for engagement missions, rules, and activation state. |
| `ManageActivitiesScreen` | `/admin/activities` | Activity management screen for configuring platform activities and engagement surfaces. |
| `ManageSeasonsScreen` | `/admin/seasons` | Seasonal content and timing management screen for campaign/season lifecycle control. |
| `ManageSpecialProductsScreen` | `/admin/special-products` | Admin commerce/editorial screen for curated product drops, bundles, or promoted inventory. |
| `ManageAdminRolesScreen` | `/admin/roles` | Role assignment screen for granting, reviewing, and revoking privileged admin access. |
| `ManageAiContentScreen` | `/admin/ai-content` | Moderation/editorial screen for generated content drafts, approval flows, and publishing control. |

## Credit

| Screen | Route | Short Description |
|---|---|---|
| `CreditScoreScreen` | `/credit` | Credit overview screen that presents the user’s score, contributing factors, and confidence-building signals. |
| `CreditReadinessScreen` | `/credit/readiness` | Guidance screen that breaks credit eligibility into actionable readiness checks and next steps. |

## Groups

| Screen | Route | Short Description |
|---|---|---|
| `GroupsScreen` | `/groups` | Main group discovery and management screen showing the user’s savings/community groups. |
| `CreateGroupScreen` | `/groups/create` | Group creation flow for setting up a new group with a guided, form-led setup experience. |
| `GroupDetailScreen` | `/groups/:id` | Group overview screen for members, balances, contributions, invites, and group-level actions. |
| `GroupLedgerScreen` | `/groups/:id/ledger` | Financial detail screen for reviewing posted group transactions and export-ready ledger history. |
| `GroupInviteScreen` | `/invite/:code` | Invite redemption screen that previews a group and lets a user join through a shared code. |

## Home

| Screen | Route | Short Description |
|---|---|---|
| `HomeScreen` | `/home` | Primary app home screen that introduces the main product surfaces and top user actions. |
| `SeasonsActivitiesScreen` | `/seasons` | Seasonal activity screen for current season content, progress, and campaign-linked participation. |

## MoMo

| Screen | Route | Short Description |
|---|---|---|
| `MomoScreen` | `/momo` | Wallet and MoMo control center for balance views, transaction actions, and payment tooling. |
| `MomoStatementsScreen` | `/momo/statements` | Statement/history screen for scanning transaction records, exports, and reconciliation-friendly history. |
| `MomoNfcScreen` | `Internal only` | In-flow NFC payment/scan screen used for tap-based or card-adjacent wallet interactions. |

## Partners Core

| Screen | Route | Short Description |
|---|---|---|
| `PartnersScreen` | `/partners` | Partner directory screen where users browse the available institutions and partner product surfaces. |
| `BankPartnerScreen` | `/partners/:id` | Partner detail screen for a bank-like institution with trust cues, offerings, and onboarding entry points. |
| `PrismaPartnerScreen` | `/partners/:id` | Partner showcase screen for the Prisma surface with partner-specific value proposition and actions. |
| `RadiantPartnerScreen` | `/partners/:id` | Partner showcase screen for the Radiant surface with brand-specific product and CTA presentation. |
| `BankOnboardingScreen` | `/partners/:id/onboarding/:type` | Guided onboarding screen for partner-origin flows such as bank account or product activation. |

## Rayon Consumer

| Screen | Route | Short Description |
|---|---|---|
| `RayonHomeScreen` | `/partners/rayon-sports` | Rayon Sports landing screen combining club identity, key fan actions, and premium fan engagement modules. |
| `FanClubsScreen` | `/partners/rayon-sports/clubs` | Fan-club discovery screen for exploring available supporter communities and joining them. |
| `FanClubDetailScreen` | `/partners/rayon-sports/clubs/:clubId` | Detailed fan-club screen with membership context, stats, and club-specific actions. |
| `MembershipTiersScreen` | `/partners/rayon-sports/membership` | Membership comparison screen that explains fan tiers, value, and upgrade/join options. |
| `FanProfileScreen` | `/partners/rayon-sports/profile` | Fan identity screen showing membership status, benefits, orders, and club-linked profile data. |
| `MemberRegistryScreen` | `/partners/rayon-sports/registry` | Membership lookup/registry screen for searching members, fan IDs, and membership records. |
| `ClubShopScreen` | `/partners/rayon-sports/shop` | Club commerce screen for browsing products, offers, and official merchandise. |
| `ShopCheckoutScreen` | `/partners/rayon-sports/shop/checkout` | Focused checkout flow for confirming cart contents, payment route, and order completion. |
| `SupportScreen` | `/partners/rayon-sports/support` | Initiative listing screen for supporter contributions, causes, and club support opportunities. |
| `SupportDetailScreen` | `/partners/rayon-sports/support/:initiativeId` | Donation/support detail screen that explains one initiative and drives contribution actions. |
| `TicketsScreen` | `/partners/rayon-sports/tickets` | Ticket discovery and purchase screen for matches, seat choices, and payment initiation. |
| `TicketConfirmationScreen` | `/partners/rayon-sports/tickets/:ticketId/confirm` | Post-purchase confirmation screen for payment success, ticket unlock state, and next steps. |
| `MyTicketsScreen` | `/partners/rayon-sports/tickets/my-tickets` | Personal ticket wallet screen for viewing owned tickets and event entry status. |

## Rayon Admin

| Screen | Route | Short Description |
|---|---|---|
| `RsAdminDashboardScreen` | `/admin/rayon` | Rayon admin command screen summarizing club operations, KPIs, and action entry points. |
| `RsAdminAnalyticsScreen` | `/admin/rayon/analytics` | Club analytics screen for reviewing fan, ticket, commerce, and engagement performance. |
| `RsAdminFinanceScreen` | `/admin/rayon/finance` | Finance operations screen for payouts, payment routes, order money flow, and statements. |
| `RsAdminInitiativesScreen` | `/admin/rayon/initiatives` | Club initiative management screen for support campaigns, causes, and fundraising setup. |
| `RsAdminMatchesScreen` | `/admin/rayon/matches` | Match operations screen for managing fixtures, match metadata, and ticket-related setup. |
| `RsAdminMembersScreen` | `/admin/rayon/members` | Membership administration screen for fan records, tiers, and member operations. |
| `RsAdminOrdersScreen` | `/admin/rayon/orders` | Order management screen for tracking commerce orders, statuses, and fulfilment actions. |
| `RsAdminPackagesScreen` | `/admin/rayon/packages` | Package/catalog management screen for memberships, bundles, or club commercial offers. |
| `RsAdminShopScreen` | `/admin/rayon/shop` | Club shop admin screen for product inventory, pricing, and merchandising management. |
| `RsAdminTicketsScreen` | `/admin/rayon/tickets` | Ticketing admin screen for inventory, seat access, routing, and matchday ticket controls. |

## Profile

| Screen | Route | Short Description |
|---|---|---|
| `ProfileScreen` | `/profile` | User account hub for personal details, settings, wallet shortcuts, and identity-related actions. |
| `ProfileIdentityScreen` | `/profile/identity` | Profile detail screen focused on identity data, KYC progress, and verification access points. |
| `ProfileWalletScreen` | `/profile/wallet` | Wallet settings/detail screen for payment route preferences and money-related profile controls. |
| `KycIdScanScreen` | `Internal only` | Camera-based identity capture flow for scanning an ID card with privacy guidance overlays. |
| `KycSelfieScreen` | `/kyc/selfie` | Selfie verification screen that captures the user’s face for identity and face-match workflows. |

## Shared Routed Utility

| Screen | Route | Short Description |
|---|---|---|
| `QrScannerScreen` | `/scanner` | General-purpose scanner screen for QR-based flows such as payments, tickets, and access control. |
