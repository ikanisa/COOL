#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Cool App — Build a release APK for QA / Firebase App Distribution
# ──────────────────────────────────────────────────────────────────────────────
# Usage:
#   ./scripts/build_qa_apk.sh
#
# Required environment variables (pass via export or .env):
#   SUPABASE_URL          — e.g. https://xxxx.supabase.co
#   SUPABASE_ANON_KEY     — project anon key
#
# Optional (defaults apply):
#   COOL_APP_MOMO_NUMBER  — MoMo recipient number (subscription payments)
#   COOL_DEEP_LINK_HOST   — Deep link host (defaults to cool.app)
#   COOL_PRIVACY_POLICY_URL
#   COOL_TERMS_OF_SERVICE_URL
#   COOL_ACCOUNT_DELETION_URL
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/_android_release_build.sh"

# ── Build the release APK ─────────────────────────────────────────────────────
echo "🔨 Validating env vars and building release APK…"

build_android_release apk

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

if [[ -f "$APK_PATH" ]]; then
  echo ""
  echo "✅ QA APK built successfully:"
  echo "   $APK_PATH"
  echo ""
  echo "📲 To install on a connected device:"
  echo "   adb install -r $APK_PATH"
  echo ""
  echo "🚀 To distribute via Firebase App Distribution:"
  echo "   firebase appdistribution:distribute $APK_PATH \\"
  echo "     --app <FIREBASE_APP_ID> --groups staff"
else
  echo "❌ APK not found at expected path: $APK_PATH"
  exit 1
fi
