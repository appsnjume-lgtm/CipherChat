# CipherChat Deep Security Audit (Red Team Review) - 2026-06-12

## 1. Executive Summary

This deep security audit identifies several critical and high-severity vulnerabilities in the CipherChat application and its Supabase backend. While the application implements End-to-End Encryption (E2EE) and has made significant progress in hardening its Row Level Security (RLS) policies, several fundamental architectural flaws remain that expose user metadata, permit unauthorized state manipulation, and lack modern cryptographic properties like Forward Secrecy.

The most critical findings involve the exposure of private group memberships to all users, the ability to leak direct chat relationships between any two users, and a "Secure Media" implementation that allows unauthorized file uploads.

---

## 2. Attack Surface Overview

The attack surface consists of:
*   **Supabase PostgREST API**: Directly accessible via the bundled Anon Key.
*   **RPC Functions**: Several `SECURITY DEFINER` functions with broad permissions.
*   **Realtime Subscriptions**: Potential for data leakage through improperly filtered channels.
*   **Android App**: Reverse engineering risk and insecure build configuration.
*   **E2EE Implementation**: Cryptographic weaknesses in key management.

---

## 3. Critical Findings

### C1. Private Chat Relationship Leak (Metadata Disclosure)
*   **Severity:** Critical
*   **Attack Scenario:** An attacker calls the `find_direct_chat_between(user_a_uuid, user_b_uuid)` RPC for any two users in the system.
*   **Impact:** The attacker can determine if any two users have a direct chat relationship. This is a major privacy violation and allows mapping the social graph of the entire user base.
*   **Affected File(s):** `supabase/cipherchat_schema.sql` (Grant on `find_direct_chat_between`)
*   **Exploitation Difficulty:** Trivial (One API call).
*   **Recommended Mitigation:** Revoke public execute permission on this function. Ensure only the users involved or a validated system process can call it.

### C2. Unauthorized Direct Chat Creation (Insecure RPC)
*   **Severity:** Critical
*   **Attack Scenario:** An attacker calls `ensure_direct_chat(victim_a, victim_b)` directly via the Supabase RPC API.
*   **Impact:** The attacker can force a chat connection between any two users without their consent. This can be used to bypass block lists (as the function doesn't check blocks) and spam users' inboxes.
*   **Affected File(s):** `supabase/cipherchat_schema.sql` (Function `ensure_direct_chat`)
*   **Exploitation Difficulty:** Trivial.
*   **Recommended Mitigation:** Restrict the function to only allow creating a chat where the caller (`auth.uid()`) is one of the participants. Add block checks before creation.

### C3. Global Group Membership Leak
*   **Severity:** Critical
*   **Attack Scenario:** An attacker queries the `chat_members` table for any `chat_id`.
*   **Impact:** Due to the RLS policy `chat_members_select_visible_groups_or_members`, any authenticated user can view the full member list of **any group chat** (`is_group = true`), regardless of whether they are a member.
*   **Affected File(s):** `supabase/cipherchat_schema.sql` (Policy on `chat_members`)
*   **Exploitation Difficulty:** Trivial.
*   **Recommended Mitigation:** Update the policy to only allow members to see other members of private groups.

---

## 4. High Findings

### H1. Lack of Forward Secrecy in E2EE
*   **Severity:** High
*   **Attack Scenario:** An attacker compromises a user's device and extracts the long-term identity key stored in Secure Storage.
*   **Impact:** Because the system uses long-term X25519 keys to wrap message keys without a DH ratchet (like Double Ratchet or X3DH), the attacker can decrypt **all past and future messages** for that user.
*   **Affected File(s):** `lib/core/security/secure_message_crypto.dart`, `lib/core/security/identity_key_service.dart`
*   **Exploitation Difficulty:** High (Requires device compromise), but the impact is total.
*   **Recommended Mitigation:** Implement the Signal Protocol (Double Ratchet + X3DH) to provide forward and future secrecy.

### H2. Insecure Build Configuration (Debug Key in Release)
*   **Severity:** High
*   **Attack Scenario:** An attacker downloads the "release" APK and notices it is signed with a debug key.
*   **Impact:** Release builds should never use debug signing configs. This facilitates tampering and suggests other build-time security features (like ProGuard/R8) may be misconfigured or disabled.
*   **Affected File(s):** `android/app/build.gradle.kts`
*   **Exploitation Difficulty:** Trivial.
*   **Recommended Mitigation:** Use a proper release keystore and enable `isMinifyEnabled` / `isShrinkResources` in the release build type.

### H3. User Enumeration via Profile Search
*   **Severity:** High
*   **Attack Scenario:** An attacker calls `search_visible_profiles` with a `null` or empty query.
*   **Impact:** The function returns a list of users (up to 30 per call). By iterating, an attacker can scrape the entire user database (Usernames, IDs, Avatars).
*   **Affected File(s):** `supabase/cipherchat_schema.sql` (Function `search_visible_profiles`)
*   **Exploitation Difficulty:** Easy.
*   **Recommended Mitigation:** Require a minimum query length (e.g., 3 characters) and implement strict rate limiting.

---

## 5. Medium Findings

### M1. Unauthorized Secure Media Uploads
*   **Severity:** Medium
*   **Attack Scenario:** An attacker who is a member of a chat uploads files to `secure-media/{chat_id}/{random_uuid}.ext` using the storage API.
*   **Impact:** The `can_upload_secure_media_object` function only checks chat membership, not whether the `message_id` exists or belongs to the uploader. This can be used for storage exhaustion or "ghost" file hosting.
*   **Affected File(s):** `supabase/cipherchat_schema.sql` (Function `can_upload_secure_media_object`)
*   **Recommended Mitigation:** Verify that a corresponding message row exists and that the `auth.uid()` matches the `sender_id`.

### M2. Android `allowBackup` Enabled
*   **Severity:** Medium
*   **Attack Scenario:** An attacker with physical access to an unlocked device uses `adb backup` to extract application data.
*   **Impact:** Sensitive information, including cached messages and potentially secure storage keys (depending on Android version/device), could be leaked.
*   **Affected File(s):** `android/app/src/main/AndroidManifest.xml`
*   **Recommended Mitigation:** Set `android:allowBackup="false"` in the Manifest.

---

## 6. Low Findings

### L1. Username Validation Bypass on Profile Update
*   **Severity:** Low
*   **Description:** While signup enforces a strict username regex, the profile update path in Settings does not.
*   **Affected File(s):** `lib/features/settings/presentation/screens/profile_settings_screen.dart`
*   **Recommended Mitigation:** Centralize validation logic in `AuthController` or `AuthRepository`.

---

## 7. Authentication Review

*   **Account Creation**: Attackers can create unlimited accounts (missing rate limits/CAPTCHA).
*   **User Enumeration**: High (via profile search RPC).
*   **Sessions**: Access tokens are stored in `flutter_secure_storage`.
*   **Revocation**: NOT VERIFIED. No explicit session management UI found.

---

## 8. E2EE Review

*   **Implementation**: Uses `X25519` and `AES-GCM-256`.
*   **Key Storage**: Secure (KeyStore/Keychain via `flutter_secure_storage`).
*   **Forward Secrecy**: **NONE**. Long-term keys are static.
*   **Metadata Leakage**: High. Server knows all participants and can verify if a direct chat exists between any two users.

---

## 9. Supabase Review

*   **RLS Policies**: Generally good for `messages`, but fundamentally broken for `chats` (group metadata) and `chat_members` (group participants).
*   **Security Definer Functions**: `ensure_direct_chat` is the highest risk as it lacks caller identity validation.

---

## 10. Android Review

*   **Exported Components**: `MainActivity` is exported (Standard).
*   **Permissions**: Broad but relevant to a chat app.
*   **Signing**: **INSECURE**. Debug key used for release builds.

---

## 11. Messaging Security Review

*   **Forgergy**: Prevented by RLS `auth.uid() = sender_id`.
*   **Tampering**: Prevented by lack of `UPDATE` policy on `messages`.
*   **Deleted Messages**: Soft-delete is server-enforced and secure.

---

## 12. Group Security Review

*   **Privacy**: **FAIL**. Group names and members are visible to all authenticated users.
*   **Admin Escalation**: NOT VERIFIED. Logic depends on `is_chat_admin` which checks `chats.created_by`.

---

## 13. File Upload Review

*   **Validation**: Server-side MIME/extension validation is **MISSING** in schema checks (relies on client).
*   **MIME/Extension Verification**: NOT VERIFIED.
*   **IDOR**: Prevented by path-based membership checks.

---

## 14. Privacy Review

*   **Contact Leaks**: Any user can check if two others are contacts via `find_direct_chat_between`.
*   **Online Status**: Visible to any user who can see the profile.
*   **Deleted Data**: Soft-delete wipes the encrypted payload, which is good.

---

## 15. Reverse Engineering Review

*   **Rating**: **WEAK**. Debug signing in release and lack of obfuscation config make reverse engineering significantly easier.

---

## 16. Abuse & DoS Review

*   **RPC Flooding**: All RPCs lack rate limiting.
*   **Chat Spam**: `ensure_direct_chat` allows creating unlimited chats between arbitrary users.

---

## 17. Recommended Remediation Order

1.  **CRITICAL**: Fix `chat_members` RLS to protect private group memberships.
2.  **CRITICAL**: Revoke public execute on `find_direct_chat_between` and `ensure_direct_chat`.
3.  **HIGH**: Fix `search_visible_profiles` to prevent user scraping.
4.  **HIGH**: Update `android/app/build.gradle.kts` to use a release keystore and enable obfuscation.
5.  **HIGH**: Begin planning for Signal Protocol (Double Ratchet) implementation.
6.  **MEDIUM**: Add `android:allowBackup="false"` to Manifest.
7.  **MEDIUM**: Harden `can_upload_secure_media_object` to verify message ownership.

---
*End of Security Deep Audit*
