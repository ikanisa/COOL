# Screen Flow Map

This map groups the implemented screens by likely user journey rather than by code module.

## Entry And Authentication

1. `SplashScreen`: Startup gate that handles initial brand presentation, session restore, and first navigation routing. Route `/`.
2. `OnboardingScreen`: Introductory marketing/onboarding screen that explains the app value and pushes users into authentication. Route `/onboarding`.
3. `OtpScreen`: Phone number capture screen with a focused, low-friction OTP request flow. Route `/otp`.
4. `OtpVerifyScreen`: Verification screen for entering and confirming the OTP code with a simple, trust-first auth UI. Route `/otp-verify`.
5. `RegisterScreen`: New-user profile setup screen that collects the minimum identity details required to activate the account. Route `/register`.
6. `AppAccessOnboardingScreen`: Access-approval entry screen that explains availability or rollout access and guides the user to the next allowed step. Route `/app-access`.

## Primary Home And Discovery

1. `HomeScreen`: Primary app home screen that introduces the main product surfaces and top user actions. Route `/home`.
2. `PartnersScreen`: Partner directory screen where users browse the available institutions and partner product surfaces. Route `/partners`.
4. `GroupsScreen`: Main group discovery and management screen showing the user’s savings/community groups. Route `/groups`.
5. `ProfileScreen`: User account hub for personal details, settings, wallet shortcuts, and identity-related actions. Route `/profile`.

## Profile And Verification

1. `ProfileIdentityScreen`: Profile detail screen focused on identity data, KYC progress, and verification access points. Route `/profile/identity`.
3. `ProfileWalletScreen`: Wallet settings/detail screen for payment route preferences and money-related profile controls. Route `/profile/wallet`.
4. `KycIdScanScreen`: Camera-based identity capture flow for scanning an ID card with privacy guidance overlays. Internal flow only.
5. `KycSelfieScreen`: Selfie verification screen that captures the user’s face for identity and face-match workflows. Route `/kyc/selfie`.

## Groups Journey

1. `GroupsScreen`: Main group discovery and management screen showing the user’s savings/community groups. Route `/groups`.
2. `CreateGroupScreen`: Group creation flow for setting up a new group with a guided, form-led setup experience. Route `/groups/create`.
3. `GroupInviteScreen`: Invite redemption screen that previews a group and lets a user join through a shared code. Route `/invite/:code`.
4. `GroupDetailScreen`: Group overview screen for members, balances, contributions, invites, and group-level actions. Route `/groups/:id`.
5. `GroupLedgerScreen`: Financial detail screen for reviewing posted group transactions and export-ready ledger history. Route `/groups/:id/ledger`.

## Wallet And MoMo Journey

1. `MomoScreen`: Wallet and MoMo control center for balance views, transaction actions, and payment tooling. Route `/momo`.
2. `MomoStatementsScreen`: Statement/history screen for scanning transaction records, exports, and reconciliation-friendly history. Route `/momo/statements`.
3. `MomoNfcScreen`: In-flow NFC payment/scan screen used for tap-based or card-adjacent wallet interactions. Internal flow only.
4. `QrScannerScreen`: General-purpose scanner screen for QR-based flows such as payments, tickets, and access control. Route `/scanner`.

## Credit Journey

1. `CreditScoreScreen`: Credit overview screen that presents the user’s score, contributing factors, and confidence-building signals. Route `/credit`.
2. `CreditReadinessScreen`: Guidance screen that breaks credit eligibility into actionable readiness checks and next steps. Route `/credit/readiness`.

## Partner Discovery Journey

1. `PartnersScreen`: Partner directory screen where users browse the available institutions and partner product surfaces. Route `/partners`.
2. `BankPartnerScreen`: Partner detail screen for a bank-like institution with trust cues, offerings, and onboarding entry points. Route `/partners/:id`.
3. `PrismaPartnerScreen`: Partner showcase screen for the Prisma surface with partner-specific value proposition and actions. Route `/partners/:id`.
4. `RadiantPartnerScreen`: Partner showcase screen for the Radiant surface with brand-specific product and CTA presentation. Route `/partners/:id`.
5. `BankOnboardingScreen`: Guided onboarding screen for partner-origin flows such as bank account or product activation. Route `/partners/:id/onboarding/:type`.

## Rayon Fan Journey

1. `RayonHomeScreen`: Rayon Sports landing screen combining club identity, key fan actions, and premium fan engagement modules. Route `/partners/rayon-sports`.
2. `FanClubsScreen`: Fan-club discovery screen for exploring available supporter communities and joining them. Route `/partners/rayon-sports/clubs`.
3. `FanClubDetailScreen`: Detailed fan-club screen with membership context, stats, and club-specific actions. Route `/partners/rayon-sports/clubs/:clubId`.
4. `MembershipTiersScreen`: Membership comparison screen that explains fan tiers, value, and upgrade/join options. Route `/partners/rayon-sports/membership`.
5. `FanProfileScreen`: Fan identity screen showing membership status, benefits, orders, and club-linked profile data. Route `/partners/rayon-sports/profile`.
6. `MemberRegistryScreen`: Membership lookup/registry screen for searching members, fan IDs, and membership records. Route `/partners/rayon-sports/registry`.
7. `ClubShopScreen`: Club commerce screen for browsing products, offers, and official merchandise. Route `/partners/rayon-sports/shop`.
8. `ShopCheckoutScreen`: Focused checkout flow for confirming cart contents, payment route, and order completion. Route `/partners/rayon-sports/shop/checkout`.
9. `SupportScreen`: Initiative listing screen for supporter contributions, causes, and club support opportunities. Route `/partners/rayon-sports/support`.
10. `SupportDetailScreen`: Donation/support detail screen that explains one initiative and drives contribution actions. Route `/partners/rayon-sports/support/:initiativeId`.
11. `TicketsScreen`: Ticket discovery and purchase screen for matches, seat choices, and payment initiation. Route `/partners/rayon-sports/tickets`.
12. `TicketConfirmationScreen`: Post-purchase confirmation screen for payment success, ticket unlock state, and next steps. Route `/partners/rayon-sports/tickets/:ticketId/confirm`.
13. `MyTicketsScreen`: Personal ticket wallet screen for viewing owned tickets and event entry status. Route `/partners/rayon-sports/tickets/my-tickets`.

## Gamification And Retention

1. `CoolTokensScreen`: Gamification/status screen that shows token balances, progress, and reward-oriented engagement data. Route `/tokens`.
2. `MissionsScreen`: Missions hub where users browse active tasks, progress states, and reward opportunities. Route `/missions`.
3. `ReferralHubScreen`: Referral center that helps users share invite links/QR codes and understand referral rewards. Route `/referral`.
4. `SeasonsActivitiesScreen`: Seasonal activity screen for current season content, progress, and campaign-linked participation. Route `/seasons`.

## Platform Admin Journey

1. `AdminWorkspacesScreen`: Admin landing screen that routes staff into the correct workspace or control area. Route `/admin`.
2. `AdminDashboardScreen`: High-level platform command screen summarizing system health, activity, and major admin actions. Route `/admin/platform`.
3. `OperationalDashboardScreen`: Monitoring screen for live platform operations, triage, and operational readiness signals. Route `/admin/operations`.
4. `SystemAnalyticsScreen`: Analytics dashboard for platform-wide trends, KPIs, and decision-support metrics. Route `/admin/analytics`.
5. `AuditLogScreen`: Operational trace screen for reviewing administrative actions and accountability records. Route `/admin/audit-log`.
6. `ManageUsersScreen`: User management screen for browsing, filtering, and acting on user accounts. Route `/admin/users`.
7. `ManagePartnersScreen`: Partner catalog management screen for reviewing and editing partner entities in the platform. Route `/admin/partners`.
8. `PartnerAdminWorkspaceScreen`: Scoped partner workspace for managing a single partner’s settings, content, and operational surfaces. Route `/admin/partners/:partnerId`.
9. `BankAdminWorkspaceScreen`: Bank-specific operations screen for allocation, ledger review, and savings/group administration. Route `/admin/banks/:partnerId`.
10. `ManageServicesScreen`: Service configuration screen for editing service cards, availability, and action behavior. Route `/admin/services`.
11. `ManageQuickActionsScreen`: Admin tool for curating shortcut actions and surfaced utility flows in the app shell. Route `/admin/quick-actions`.
13. `ManageAppConfigScreen`: Central application configuration screen for rollout flags, runtime settings, and scoped config values. Route `/admin/app-config`.
14. `ManageMissionsScreen`: Mission authoring and control screen for engagement missions, rules, and activation state. Route `/admin/missions`.
15. `ManageActivitiesScreen`: Activity management screen for configuring platform activities and engagement surfaces. Route `/admin/activities`.
16. `ManageSeasonsScreen`: Seasonal content and timing management screen for campaign/season lifecycle control. Route `/admin/seasons`.
17. `ManageSpecialProductsScreen`: Admin commerce/editorial screen for curated product drops, bundles, or promoted inventory. Route `/admin/special-products`.
18. `ManageAdminRolesScreen`: Role assignment screen for granting, reviewing, and revoking privileged admin access. Route `/admin/roles`.
19. `ManageAiContentScreen`: Moderation/editorial screen for generated content drafts, approval flows, and publishing control. Route `/admin/ai-content`.

## Rayon Admin Journey

1. `RsAdminDashboardScreen`: Rayon admin command screen summarizing club operations, KPIs, and action entry points. Route `/admin/rayon`.
2. `RsAdminAnalyticsScreen`: Club analytics screen for reviewing fan, ticket, commerce, and engagement performance. Route `/admin/rayon/analytics`.
3. `RsAdminFinanceScreen`: Finance operations screen for payouts, payment routes, order money flow, and statements. Route `/admin/rayon/finance`.
4. `RsAdminInitiativesScreen`: Club initiative management screen for support campaigns, causes, and fundraising setup. Route `/admin/rayon/initiatives`.
5. `RsAdminMatchesScreen`: Match operations screen for managing fixtures, match metadata, and ticket-related setup. Route `/admin/rayon/matches`.
6. `RsAdminMembersScreen`: Membership administration screen for fan records, tiers, and member operations. Route `/admin/rayon/members`.
7. `RsAdminOrdersScreen`: Order management screen for tracking commerce orders, statuses, and fulfilment actions. Route `/admin/rayon/orders`.
8. `RsAdminPackagesScreen`: Package/catalog management screen for memberships, bundles, or club commercial offers. Route `/admin/rayon/packages`.
9. `RsAdminShopScreen`: Club shop admin screen for product inventory, pricing, and merchandising management. Route `/admin/rayon/shop`.
10. `RsAdminTicketsScreen`: Ticketing admin screen for inventory, seat access, routing, and matchday ticket controls. Route `/admin/rayon/tickets`.
