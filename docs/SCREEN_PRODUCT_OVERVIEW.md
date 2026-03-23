# Product Screen Overview

This is a product-facing summary of the implemented app screens. Each screen is described in plain language so product, design, operations, and stakeholders can quickly understand what exists in the app today.

## Auth And Entry

- `SplashScreen`: Startup gate that handles initial brand presentation, session restore, and first navigation routing. Route: `/`.
- `OnboardingScreen`: Introductory marketing/onboarding screen that explains the app value and pushes users into authentication. Route: `/onboarding`.
- `OtpScreen`: Phone number capture screen with a focused, low-friction OTP request flow. Route: `/otp`.
- `OtpVerifyScreen`: Verification screen for entering and confirming the OTP code with a simple, trust-first auth UI. Route: `/otp-verify`.
- `RegisterScreen`: New-user profile setup screen that collects the minimum identity details required to activate the account. Route: `/register`.
- `AppAccessOnboardingScreen`: Access-approval entry screen that explains availability or rollout access and guides the user to the next allowed step. Route: `/app-access`.

## Core Status

- `CoolTokensScreen`: Gamification/status screen that shows token balances, progress, and reward-oriented engagement data. Route: `/tokens`.
- `MissionsScreen`: Missions hub where users browse active tasks, progress states, and reward opportunities. Route: `/missions`.
- `ReferralHubScreen`: Referral center that helps users share invite links/QR codes and understand referral rewards. Route: `/referral`.

## Admin

- `AdminWorkspacesScreen`: Admin landing screen that routes staff into the correct workspace or control area. Route: `/admin`.
- `AdminDashboardScreen`: High-level platform command screen summarizing system health, activity, and major admin actions. Route: `/admin/platform`.
- `AuditLogScreen`: Operational trace screen for reviewing administrative actions and accountability records. Route: `/admin/audit-log`.
- `OperationalDashboardScreen`: Monitoring screen for live platform operations, triage, and operational readiness signals. Route: `/admin/operations`.
- `SystemAnalyticsScreen`: Analytics dashboard for platform-wide trends, KPIs, and decision-support metrics. Route: `/admin/analytics`.
- `ManageUsersScreen`: User management screen for browsing, filtering, and acting on user accounts. Route: `/admin/users`.
- `ManagePartnersScreen`: Partner catalog management screen for reviewing and editing partner entities in the platform. Route: `/admin/partners`.
- `PartnerAdminWorkspaceScreen`: Scoped partner workspace for managing a single partner’s settings, content, and operational surfaces. Route: `/admin/partners/:partnerId`.
- `BankAdminWorkspaceScreen`: Bank-specific operations screen for allocation, ledger review, and savings/group administration. Route: `/admin/banks/:partnerId`.
- `ManageServicesScreen`: Service configuration screen for editing service cards, availability, and action behavior. Route: `/admin/services`.
- `ManageQuickActionsScreen`: Admin tool for curating shortcut actions and surfaced utility flows in the app shell. Route: `/admin/quick-actions`.
- `ManageVehicleTypesScreen`: Mobility configuration screen for maintaining vehicle categories and related operational metadata. Route: `/admin/vehicle-types`.
- `ManageAppConfigScreen`: Central application configuration screen for rollout flags, runtime settings, and scoped config values. Route: `/admin/app-config`.
- `ManageMissionsScreen`: Mission authoring and control screen for engagement missions, rules, and activation state. Route: `/admin/missions`.
- `ManageActivitiesScreen`: Activity management screen for configuring platform activities and engagement surfaces. Route: `/admin/activities`.
- `ManageSeasonsScreen`: Seasonal content and timing management screen for campaign/season lifecycle control. Route: `/admin/seasons`.
- `ManageSpecialProductsScreen`: Admin commerce/editorial screen for curated product drops, bundles, or promoted inventory. Route: `/admin/special-products`.
- `ManageAdminRolesScreen`: Role assignment screen for granting, reviewing, and revoking privileged admin access. Route: `/admin/roles`.
- `ManageAiContentScreen`: Moderation/editorial screen for generated content drafts, approval flows, and publishing control. Route: `/admin/ai-content`.

## Credit

- `CreditScoreScreen`: Credit overview screen that presents the user’s score, contributing factors, and confidence-building signals. Route: `/credit`.
- `CreditReadinessScreen`: Guidance screen that breaks credit eligibility into actionable readiness checks and next steps. Route: `/credit/readiness`.

## Groups

- `GroupsScreen`: Main group discovery and management screen showing the user’s savings/community groups. Route: `/groups`.
- `CreateGroupScreen`: Group creation flow for setting up a new group with a guided, form-led setup experience. Route: `/groups/create`.
- `GroupDetailScreen`: Group overview screen for members, balances, contributions, invites, and group-level actions. Route: `/groups/:id`.
- `GroupLedgerScreen`: Financial detail screen for reviewing posted group transactions and export-ready ledger history. Route: `/groups/:id/ledger`.
- `GroupInviteScreen`: Invite redemption screen that previews a group and lets a user join through a shared code. Route: `/invite/:code`.

## Home

- `HomeScreen`: Primary app home screen that introduces the main product surfaces and top user actions. Route: `/home`.
- `SeasonsActivitiesScreen`: Seasonal activity screen for current season content, progress, and campaign-linked participation. Route: `/seasons`.

## Mobility

- `MobilityHomeScreen`: Mobility landing screen for transport-focused discovery, posting, and trip-related actions. Route: `/mobility`.
- `DriverProfileScreen`: Driver account hub for profile, availability, and operator-facing transport identity details. Route: `/mobility/driver`.
- `DriverSubscriptionScreen`: Driver monetization screen for viewing plan status, credits, and upgrade/subscription access. Route: `/mobility/driver/subscription`.
- `DriverVehicleScreen`: Driver vehicle management screen for readiness, vehicle metadata, and posting eligibility. Route: `/mobility/driver/vehicle`.
- `ScheduleTripScreen`: Trip creation flow for scheduling transport with route, timing, and rider-facing details. Route: `/mobility/schedule`.
- `TripBoardScreen`: Trip listing board for browsing available trips, demand, route details, and booking/contact actions. Route: `/mobility/trips`.

## MoMo

- `MomoScreen`: Wallet and MoMo control center for balance views, transaction actions, and payment tooling. Route: `/momo`.
- `MomoStatementsScreen`: Statement/history screen for scanning transaction records, exports, and reconciliation-friendly history. Route: `/momo/statements`.
- `MomoNfcScreen`: In-flow NFC payment/scan screen used for tap-based or card-adjacent wallet interactions. Route: internal flow only.

## Partners Core

- `PartnersScreen`: Partner directory screen where users browse the available institutions and partner product surfaces. Route: `/partners`.
- `BankPartnerScreen`: Partner detail screen for a bank-like institution with trust cues, offerings, and onboarding entry points. Route: `/partners/:id`.
- `PrismaPartnerScreen`: Partner showcase screen for the Prisma surface with partner-specific value proposition and actions. Route: `/partners/:id`.
- `RadiantPartnerScreen`: Partner showcase screen for the Radiant surface with brand-specific product and CTA presentation. Route: `/partners/:id`.
- `BankOnboardingScreen`: Guided onboarding screen for partner-origin flows such as bank account or product activation. Route: `/partners/:id/onboarding/:type`.

## Rayon Consumer

- `RayonHomeScreen`: Rayon Sports landing screen combining club identity, key fan actions, and premium fan engagement modules. Route: `/partners/rayon-sports`.
- `FanClubsScreen`: Fan-club discovery screen for exploring available supporter communities and joining them. Route: `/partners/rayon-sports/clubs`.
- `FanClubDetailScreen`: Detailed fan-club screen with membership context, stats, and club-specific actions. Route: `/partners/rayon-sports/clubs/:clubId`.
- `MembershipTiersScreen`: Membership comparison screen that explains fan tiers, value, and upgrade/join options. Route: `/partners/rayon-sports/membership`.
- `FanProfileScreen`: Fan identity screen showing membership status, benefits, orders, and club-linked profile data. Route: `/partners/rayon-sports/profile`.
- `MemberRegistryScreen`: Membership lookup/registry screen for searching members, fan IDs, and membership records. Route: `/partners/rayon-sports/registry`.
- `ClubShopScreen`: Club commerce screen for browsing products, offers, and official merchandise. Route: `/partners/rayon-sports/shop`.
- `ShopCheckoutScreen`: Focused checkout flow for confirming cart contents, payment route, and order completion. Route: `/partners/rayon-sports/shop/checkout`.
- `SupportScreen`: Initiative listing screen for supporter contributions, causes, and club support opportunities. Route: `/partners/rayon-sports/support`.
- `SupportDetailScreen`: Donation/support detail screen that explains one initiative and drives contribution actions. Route: `/partners/rayon-sports/support/:initiativeId`.
- `TicketsScreen`: Ticket discovery and purchase screen for matches, seat choices, and payment initiation. Route: `/partners/rayon-sports/tickets`.
- `TicketConfirmationScreen`: Post-purchase confirmation screen for payment success, ticket unlock state, and next steps. Route: `/partners/rayon-sports/tickets/:ticketId/confirm`.
- `MyTicketsScreen`: Personal ticket wallet screen for viewing owned tickets and event entry status. Route: `/partners/rayon-sports/tickets/my-tickets`.

## Rayon Admin

- `RsAdminDashboardScreen`: Rayon admin command screen summarizing club operations, KPIs, and action entry points. Route: `/admin/rayon`.
- `RsAdminAnalyticsScreen`: Club analytics screen for reviewing fan, ticket, commerce, and engagement performance. Route: `/admin/rayon/analytics`.
- `RsAdminFinanceScreen`: Finance operations screen for payouts, payment routes, order money flow, and statements. Route: `/admin/rayon/finance`.
- `RsAdminInitiativesScreen`: Club initiative management screen for support campaigns, causes, and fundraising setup. Route: `/admin/rayon/initiatives`.
- `RsAdminMatchesScreen`: Match operations screen for managing fixtures, match metadata, and ticket-related setup. Route: `/admin/rayon/matches`.
- `RsAdminMembersScreen`: Membership administration screen for fan records, tiers, and member operations. Route: `/admin/rayon/members`.
- `RsAdminOrdersScreen`: Order management screen for tracking commerce orders, statuses, and fulfilment actions. Route: `/admin/rayon/orders`.
- `RsAdminPackagesScreen`: Package/catalog management screen for memberships, bundles, or club commercial offers. Route: `/admin/rayon/packages`.
- `RsAdminShopScreen`: Club shop admin screen for product inventory, pricing, and merchandising management. Route: `/admin/rayon/shop`.
- `RsAdminTicketsScreen`: Ticketing admin screen for inventory, seat access, routing, and matchday ticket controls. Route: `/admin/rayon/tickets`.

## Profile

- `ProfileScreen`: User account hub for personal details, settings, wallet shortcuts, and identity-related actions. Route: `/profile`.
- `ProfileIdentityScreen`: Profile detail screen focused on identity data, KYC progress, and verification access points. Route: `/profile/identity`.
- `ProfileTravelRoleScreen`: Preference screen for selecting or editing the user’s transport role and mobility behavior. Route: `/profile/travel-role`.
- `ProfileWalletScreen`: Wallet settings/detail screen for payment route preferences and money-related profile controls. Route: `/profile/wallet`.
- `KycIdScanScreen`: Camera-based identity capture flow for scanning an ID card with privacy guidance overlays. Route: internal flow only.
- `KycSelfieScreen`: Selfie verification screen that captures the user’s face for identity and face-match workflows. Route: `/kyc/selfie`.

## Shared Routed Utility

- `QrScannerScreen`: General-purpose scanner screen for QR-based flows such as payments, tickets, and access control. Route: `/scanner`.
