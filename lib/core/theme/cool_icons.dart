import 'package:flutter/material.dart';

/// Single source of truth for icon mappings.
///
/// Guarantees one icon per concept across the entire app.
/// Every screen should reference [CoolIcons] instead of raw [Icons.*].
abstract final class CoolIcons {
  // ── Navigation ────────────────────────────────────────────────────
  /// Back arrow for app bars and detail screens.
  static const back = Icons.arrow_back_rounded;

  /// Close/dismiss for sheets, dialogs, and banners.
  static const close = Icons.close_rounded;

  /// Trailing chevron for navigable list rows.
  static const chevron = Icons.chevron_right_rounded;

  /// Forward arrow for CTA hints and card actions.
  static const forward = Icons.arrow_forward_rounded;

  /// Home tab icon.
  static const home = Icons.home_filled;

  /// Hamburger menu (rarely used — prefer contextual actions).
  static const menu = Icons.menu_rounded;

  // ── Core features ─────────────────────────────────────────────────
  /// Groups / contribution circles icon.
  static const groups = Icons.groups_2_outlined;

  /// Savings / piggy bank.
  static const savings = Icons.savings_rounded;

  /// Primary add/contribute action.
  static const contribute = Icons.add_rounded;

  /// Wallet / MoMo.
  static const wallet = Icons.account_balance_wallet_outlined;

  /// Transaction history / receipts.
  static const history = Icons.receipt_long_rounded;

  /// Statements (alias for history — same concept).
  static const statements = Icons.receipt_long_rounded;

  // ── BioPay ────────────────────────────────────────────────────────
  /// Face scan / biometric pay.
  static const faceScan = Icons.center_focus_strong_rounded;

  /// NFC tap-to-pay.
  static const nfc = Icons.nfc_rounded;

  /// QR code display.
  static const qrCode = Icons.qr_code_2_rounded;

  /// QR code scanner.
  static const qrScan = Icons.qr_code_scanner_rounded;

  // ── Profile & Settings ────────────────────────────────────────────
  /// User profile / account.
  static const profile = Icons.person_outline_rounded;

  /// Settings (tune/filter variant).
  static const settings = Icons.tune_rounded;

  /// Settings gear (alternative).
  static const settingsGear = Icons.settings_outlined;

  /// Verified / security shield.
  static const shield = Icons.verified_user_rounded;

  /// Admin workspace.
  static const admin = Icons.admin_panel_settings_rounded;

  /// Help / support chat.
  static const support = Icons.chat_rounded;

  /// Chat bubble (WhatsApp-style messaging).
  static const chatBubble = Icons.chat_bubble_rounded;

  /// Sign out.
  static const logout = Icons.logout_rounded;

  /// Delete / destructive.
  static const delete = Icons.delete_outline_rounded;

  /// Face ID / biometric enrollment.
  static const faceId = Icons.face_retouching_natural_rounded;

  // ── Actions ───────────────────────────────────────────────────────
  /// Generic add action.
  static const add = Icons.add_rounded;

  /// Invite / add person.
  static const invite = Icons.person_add_rounded;

  /// Share content.
  static const share = Icons.share_rounded;

  /// Edit / modify.
  static const edit = Icons.edit_rounded;

  /// Confirm / checkmark.
  static const check = Icons.check_rounded;

  /// Search.
  static const search = Icons.search_rounded;

  /// Refresh / reload.
  static const refresh = Icons.refresh_rounded;

  /// Copy to clipboard.
  static const copy = Icons.content_copy_rounded;

  /// Open external link.
  static const link = Icons.open_in_new_rounded;

  // ── Expand / Collapse ─────────────────────────────────────────────
  /// Expand section / show more.
  static const expand = Icons.keyboard_arrow_down_rounded;

  /// Collapse section / show less.
  static const collapse = Icons.keyboard_arrow_up_rounded;

  /// Expand circle variant (for inline expand triggers).
  static const expandCircle = Icons.expand_circle_down_rounded;

  // ── Content & Data ────────────────────────────────────────────────
  /// Calendar / date picker.
  static const calendar = Icons.calendar_month_rounded;

  /// PDF export.
  static const pdf = Icons.picture_as_pdf_rounded;

  /// Grid / table view.
  static const grid = Icons.grid_on_rounded;

  /// Notifications / alerts.
  static const notifications = Icons.notifications_outlined;

  /// Person / individual member.
  static const person = Icons.person_rounded;

  // ── Permissions & System ──────────────────────────────────────────
  /// SMS / messaging.
  static const sms = Icons.sms_outlined;

  /// Camera.
  static const camera = Icons.camera_alt_outlined;

  /// Contacts / address book.
  static const contacts = Icons.contacts_outlined;

  /// Photo library / media.
  static const photos = Icons.photo_library_outlined;

  /// Sync / data transfer.
  static const sync = Icons.sync_rounded;

  /// Security / protection.
  static const security = Icons.security_rounded;

  // ── Appearance ────────────────────────────────────────────────────
  /// System/auto theme.
  static const themeAuto = Icons.brightness_auto_rounded;

  /// Dark theme.
  static const themeDark = Icons.dark_mode_outlined;

  /// Selected / active circle.
  static const selected = Icons.check_circle_rounded;

  /// Unselected / inactive circle.
  static const unselected = Icons.circle_outlined;

  // ── Status & Info ─────────────────────────────────────────────────
  /// Payment / money.
  static const payment = Icons.payments_rounded;

  /// Members / people.
  static const members = Icons.people_rounded;

  /// Lock / restricted.
  static const lock = Icons.lock_outline_rounded;

  /// Group not found / removed.
  static const groupOff = Icons.group_off_rounded;

  /// Offline / no connection.
  static const cloudOff = Icons.cloud_off_rounded;

  /// Empty state.
  static const empty = Icons.inbox_rounded;

  /// Error state.
  static const error = Icons.error_outline_rounded;

  /// Success circle / completed state.
  static const checkCircle = Icons.check_circle_outline_rounded;

  /// Informational.
  static const info = Icons.info_outline_rounded;

  /// Help / question circle.
  static const help = Icons.help_outline_rounded;

  /// Loading / pending state.
  static const loading = Icons.hourglass_top_rounded;

  /// Warning / caution.
  static const warning = Icons.warning_amber_rounded;

  // ── Transaction Status ──────────────────────────────────────────
  /// Verified / confirmed status.
  static const verified = Icons.verified_rounded;

  /// Draft / edit note.
  static const editNote = Icons.edit_note_rounded;

  /// Pending / awaiting.
  static const pending = Icons.pending_rounded;

  /// Pending manual action.
  static const pendingActions = Icons.pending_actions_rounded;

  /// AI-suggested / auto-fix.
  static const autoFix = Icons.auto_fix_high_rounded;

  /// Cancelled / rejected.
  static const cancelled = Icons.cancel_rounded;

  /// Debit / outgoing money.
  static const debit = Icons.north_east_rounded;

  /// Credit / incoming money.
  static const credit = Icons.south_west_rounded;

  /// Sync / transfer.
  static const syncAlt = Icons.sync_alt_rounded;

  // ── Navigation (additional) ──────────────────────────────────────
  /// iOS-style back chevron (for scanner overlays).
  static const backIos = Icons.arrow_back_ios_new_rounded;

  /// Dropdown indicator arrow.
  static const dropDown = Icons.arrow_drop_down;

  /// Left-facing chevron (previous / back alternative).
  static const chevronLeft = Icons.chevron_left_rounded;

  // ── Financial Arrows ─────────────────────────────────────────────
  /// Arrow down (incoming / credit transaction).
  static const arrowDown = Icons.arrow_downward_rounded;

  /// Arrow up (outgoing / debit transaction).
  static const arrowUp = Icons.arrow_upward_rounded;

  // ── Profile & Identity (additional) ──────────────────────────────
  /// Identity badge / display name.
  static const badge = Icons.badge_outlined;

  /// Phone number.
  static const phone = Icons.phone_outlined;

  /// Country flag / nationality.
  static const flag = Icons.flag_outlined;

  /// Fingerprint / biometric local auth.
  static const fingerprint = Icons.fingerprint_rounded;

  /// Route / journey / MoMo route.
  static const route = Icons.route_rounded;

  // ── Content & Data (additional) ──────────────────────────────────
  /// QR code (simple variant, for share action triggers).
  static const qrCodeSimple = Icons.qr_code_rounded;

  /// Notifications (filled variant for active bell).
  static const notificationsFilled = Icons.notifications_rounded;

  /// Wallet (filled variant for balance cards).
  static const walletFilled = Icons.account_balance_wallet_rounded;

  /// Shield (outlined, for insured/protected label).
  static const shieldOutline = Icons.shield_outlined;

  /// SMS (filled variant for rationale sheets).
  static const smsFilled = Icons.sms_rounded;

  /// Contacts (filled variant for share actions).
  static const contactsFilled = Icons.contacts_rounded;

  /// Link / URL reference.
  static const linkUrl = Icons.link_rounded;

  // ── System & PWA ─────────────────────────────────────────────────
  /// Install / add to home screen.
  static const install = Icons.install_mobile_rounded;

  /// iOS share button.
  static const iosShare = Icons.ios_share_rounded;

  /// Add box (iOS "Add to Home Screen" step).
  static const addBox = Icons.add_box_outlined;

  /// Maintenance / engineering.
  static const maintenance = Icons.engineering_rounded;

  /// Settings gear (rounded variant for nav bar).
  static const settingsRounded = Icons.settings_rounded;

  /// Home (rounded variant, for nav bar).
  static const homeRounded = Icons.home_rounded;

  // ── Trends & Dashboard ───────────────────────────────────────────
  /// Trending up (positive net change).
  static const trendUp = Icons.trending_up_rounded;

  /// Trending down (negative net change).
  static const trendDown = Icons.trending_down_rounded;

  /// Flat / horizontal rule (zero net change).
  static const horizontalRule = Icons.horizontal_rule_rounded;

  /// Recent operations / history toggle.
  static const historyToggle = Icons.history_toggle_off_rounded;

  /// Receipt outlined (empty state variant).
  static const receiptOutlined = Icons.receipt_long_outlined;

  /// Groups outlined (community section header).
  static const groupsOutlined = Icons.groups_outlined;

  // ── BioPay (additional) ──────────────────────────────────────────
  /// Contactless NFC tap animation.
  static const contactless = Icons.contactless_rounded;

  // ── Admin Module ─────────────────────────────────────────────────
  /// Admin panel settings (outlined).
  static const adminPanel = Icons.admin_panel_settings_outlined;

  /// Admin panel settings (filled).
  static const adminPanelFilled = Icons.admin_panel_settings_rounded;

  /// Dashboard customize.
  static const dashboardCustomize = Icons.dashboard_customize_outlined;

  /// Account tree / org structure.
  static const accountTree = Icons.account_tree_outlined;

  /// Dataset linked / data connections.
  static const datasetLinked = Icons.dataset_linked_outlined;

  /// Fact check / verification.
  static const factCheck = Icons.fact_check_outlined;


  /// Task completed / approved.
  static const taskComplete = Icons.task_alt_outlined;

  /// Rule folder / policies.
  static const ruleFolder = Icons.rule_folder_outlined;

  /// Timeline / activity log.
  static const timeline = Icons.timeline_outlined;

  /// Monitor / health check.
  static const monitor = Icons.monitor_outlined;

  /// Monitor heart / system health.
  static const monitorHeart = Icons.monitor_heart_outlined;

  /// Monitor heart (filled).
  static const monitorHeartFilled = Icons.monitor_heart_rounded;

  /// Analytics (outlined).
  static const analytics = Icons.analytics_outlined;

  /// Analytics (filled).
  static const analyticsFilled = Icons.analytics_rounded;

  /// Science / experimental.
  static const science = Icons.science_outlined;

  /// Flash / quick action.
  static const flash = Icons.flash_on_outlined;

  /// Bolt / power.
  static const bolt = Icons.bolt_outlined;

  /// Electric bolt.
  static const electricBolt = Icons.electric_bolt_rounded;

  /// Functions / formulas.
  static const functions = Icons.functions_outlined;

  /// Show chart / line chart.
  static const showChart = Icons.show_chart_rounded;

  /// Star (filled).
  static const star = Icons.star_rounded;


  /// Savings (outlined).
  static const savingsOutlined = Icons.savings_outlined;

  /// Account balance / bank (outlined).
  static const accountBalanceOutlined = Icons.account_balance_outlined;

  /// Account balance / bank (filled).
  static const accountBalanceFilled = Icons.account_balance_rounded;

  /// Account balance wallet (outlined).
  static const walletOutlined = Icons.account_balance_wallet_outlined;

  /// Payments (outlined).
  static const payments = Icons.payments_outlined;

  /// Payments (filled).
  static const paymentsFilled = Icons.payments_rounded;

  /// Verified user (outlined).
  static const verifiedUser = Icons.verified_user_outlined;

  /// Verified user (filled).
  static const verifiedUserFilled = Icons.verified_user_rounded;


  /// People (outlined).
  static const people = Icons.people_outline_rounded;

  /// Group (outlined).
  static const groupOutlined = Icons.group_outlined;

  /// Groups (filled).
  static const groupsFilled = Icons.groups_rounded;


  /// Group work / team.
  static const groupWork = Icons.group_work_rounded;

  /// Person add.
  static const personAdd = Icons.person_add_rounded;

  /// Visibility / eye.
  static const visibility = Icons.visibility_outlined;


  /// Edit (outlined).
  static const editOutlined = Icons.edit_outlined;


  /// Remove circle / minus.
  static const removeCircle = Icons.remove_circle_outline_rounded;

  /// Add circle / plus.
  static const addCircle = Icons.add_circle_outline_rounded;


  /// Check circle (outlined).
  static const checkCircleOutlined = Icons.check_circle_outline_rounded;

  /// Cancel / dismiss.
  static const cancel = Icons.cancel_rounded;

  /// History / recent.
  static const historyRounded = Icons.history_rounded;


  /// Priority high / alert.
  static const priorityHigh = Icons.priority_high_rounded;

  /// Search off / no results.
  static const searchOff = Icons.search_off_rounded;

  /// Arrow forward / navigate.
  static const arrowForward = Icons.arrow_forward_rounded;

  /// Chevron right.
  static const chevronRight = Icons.chevron_right_rounded;

  /// Expand more / dropdown.
  static const expandMore = Icons.expand_more_rounded;

  /// Expand less / collapse.
  static const expandLess = Icons.expand_less_rounded;

  /// Unfold more / expand all.
  static const unfoldMore = Icons.unfold_more_rounded;



  /// Paste / clipboard.
  static const paste = Icons.paste_rounded;

  /// Inbox (outlined).
  static const inbox = Icons.inbox_outlined;

  /// Store / storefront.
  static const store = Icons.store_rounded;

  /// Storefront.
  static const storefront = Icons.storefront_rounded;

  /// Smart toy / AI.
  static const smartToy = Icons.smart_toy_rounded;

  /// Auto awesome / magic.
  static const autoAwesome = Icons.auto_awesome_rounded;

  /// Construction / under development.
  static const construction = Icons.construction_rounded;

  /// School / education.
  static const school = Icons.school_rounded;

  /// Agriculture / farming.
  static const agriculture = Icons.agriculture_rounded;

  /// Local hospital / health.
  static const hospital = Icons.local_hospital_rounded;

  /// Directions car / transport.
  static const car = Icons.directions_car_rounded;

  /// Handshake / partnership.
  static const handshake = Icons.handshake_rounded;

  /// Grid on / table view.
  static const gridOn = Icons.grid_on_rounded;

  /// Loop / recurring.
  static const loop = Icons.loop_rounded;

  /// Tune / fine-tune.
  static const tune = Icons.tune_rounded;

  /// Phone android (outlined).
  static const phoneAndroidOutlined = Icons.phone_android_outlined;

  /// Phone android (rounded).
  static const phoneAndroid = Icons.phone_android_rounded;

  /// QR code (rounded).
  static const qrCodeRounded = Icons.qr_code_rounded;

  /// Settings (outlined).
  static const settingsOutlined = Icons.settings_outlined;

  /// Picture as PDF.
  static const pdfRounded = Icons.picture_as_pdf_rounded;

  /// Sticky note.
  static const stickyNote = Icons.sticky_note_2_rounded;

  /// Flag (rounded fill).
  static const flagFilled = Icons.flag_rounded;
}
