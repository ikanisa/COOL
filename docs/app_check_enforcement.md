# Firebase App Check Enforcement — Setup Guide

This document covers the GCP Console steps required to enable Firebase App Check enforcement for Supabase edge functions. The code changes (token attachment + server-side validation) are already in place.

## Prerequisites

- Firebase project linked to the GCP project
- Android app registered in Firebase Console
- iOS app registered in Firebase Console (if applicable)

## Step 1: Enable App Check Providers

1. Go to **Firebase Console** → **App Check** (left sidebar under Build)
2. For each registered app:
   - **Android**: Click the app → Register → Select **Play Integrity** → Save
   - **iOS**: Click the app → Register → Select **App Attest** → Save
   - **Web** (if applicable): Select **reCAPTCHA Enterprise** → Provide site key → Save

## Step 2: Obtain the Firebase Project Number

1. Go to **Firebase Console** → **Project Settings** → **General**
2. Note the **Project number** (numeric, e.g. `123456789012`)
3. This is used by the server-side token verification

## Step 3: Configure Debug Provider (Development)

For local development / emulator builds:

1. In Firebase Console → App Check → **Apps** tab
2. Click the overflow menu (⋮) on your app → **Manage debug tokens**
3. Add a debug token (copy from your local debug output)

The app's `AppCheckService` already uses `DebugProvider` in debug builds, which prints the debug token to the console on first run.

## Step 4: Verify End-to-End

1. Deploy the updated edge functions (`biopay-enroll`, `biopay-match`, `biopay-revoke`)
2. Run the app in release mode on a real device
3. Trigger a BioPay enrollment
4. Check edge function logs for the `X-Firebase-AppCheck` header presence
5. Test rejection: use `curl` to call the endpoint with a valid JWT but **without** the App Check header — should return 401

## Step 5: Enable Enforcement (When Ready)

> **⚠️ Do this only after verifying all clients send valid tokens.**

1. Firebase Console → App Check → **APIs** tab
2. Find your Supabase project's custom API endpoint (if registered)
3. Toggle **Enforce** to ON

For Supabase edge functions specifically, enforcement is handled **in our code** via `requireAppCheckToken()`. The Firebase Console enforcement toggle applies to Firebase-native services (Firestore, Storage, etc.), not custom endpoints. Our server-side validation is the enforcement layer.

## Current Status

| Component | Status |
|-----------|--------|
| Client token retrieval (`AppCheckService`) | ✅ Implemented |
| Client token attachment (`BiopayRepository`) | ✅ Implemented |
| Server-side validation (`_shared/app_check.ts`) | ✅ Implemented |
| `biopay-enroll` enforcement | ✅ Implemented |
| `biopay-match` enforcement | ✅ Implemented |
| `biopay-revoke` enforcement | ✅ Implemented |
| Firebase Console provider registration | ⏳ Manual step |
| End-to-end verification on device | ⏳ Manual step |
