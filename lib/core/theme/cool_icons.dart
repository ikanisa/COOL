import 'package:flutter/material.dart';

/// Single source of truth for icon mappings.
///
/// Guarantees one icon per concept across the entire app.
/// Every screen should reference [CoolIcons] instead of raw [Icons.*].
abstract final class CoolIcons {
  // ── Navigation ────────────────────────────────────────────────────
  static const back = Icons.arrow_back_rounded;
  static const close = Icons.close_rounded;
  static const chevron = Icons.chevron_right_rounded;
  static const home = Icons.home_filled;
  static const menu = Icons.menu_rounded;

  // ── Core features ─────────────────────────────────────────────────
  static const groups = Icons.groups_2_outlined;
  static const savings = Icons.savings_rounded;
  static const contribute = Icons.add_rounded;
  static const wallet = Icons.account_balance_wallet_outlined;
  static const history = Icons.receipt_long_rounded;
  static const statements = Icons.receipt_long_rounded;

  // ── BioPay ────────────────────────────────────────────────────────
  static const faceScan = Icons.center_focus_strong_rounded;
  static const nfc = Icons.nfc_rounded;
  static const qrCode = Icons.qr_code_2_rounded;
  static const qrScan = Icons.qr_code_scanner_rounded;

  // ── Profile & Settings ────────────────────────────────────────────
  static const profile = Icons.person_outline_rounded;
  static const settings = Icons.tune_rounded;
  static const settingsGear = Icons.settings_outlined;
  static const shield = Icons.verified_user_rounded;
  static const admin = Icons.admin_panel_settings_rounded;
  static const support = Icons.chat_rounded;
  static const logout = Icons.logout_rounded;
  static const delete = Icons.delete_outline_rounded;
  static const faceId = Icons.face_retouching_natural_rounded;

  // ── Actions ───────────────────────────────────────────────────────
  static const add = Icons.add_rounded;
  static const invite = Icons.person_add_rounded;
  static const share = Icons.share_rounded;
  static const edit = Icons.edit_rounded;
  static const check = Icons.check_rounded;
  static const search = Icons.search_rounded;
  static const refresh = Icons.refresh_rounded;

  // ── Status & Info ─────────────────────────────────────────────────
  static const payment = Icons.payments_rounded;
  static const members = Icons.people_rounded;
  static const lock = Icons.lock_outline_rounded;
  static const groupOff = Icons.group_off_rounded;
  static const cloudOff = Icons.cloud_off_rounded;
  static const empty = Icons.inbox_rounded;
  static const error = Icons.error_outline_rounded;
  static const info = Icons.info_outline_rounded;
}
