# CipherChat Identity, Username, and Profile Audit

Audit scope: current repository state as of 2026-04-30. This report traces the checked implementation in `lib/`, `supabase/`, `supabase/migrations/`, and `supabase/OLD DATABASE/` for user identity, usernames, email use, and profile handling. No source files were modified for this audit.

## 1. SYSTEM OVERVIEW

### Identity model

SYSTEM IDENTITY FIELD = `public.profiles.id`, a UUID that is also `auth.users.id`.

Evidence:

- `supabase/cipherchat_schema.sql` defines `public.profiles.id uuid primary key references auth.users (id) on delete cascade`.
- `lib/features/auth/presentation/providers/auth_provider.dart` exposes `currentUserIdProvider` as `session?.user.id`.
- `lib/features/auth/data/repositories/auth_repository.dart` fetches profiles with `.from('profiles').select().eq('id', userId)`.
- Profile creation uses `.from('profiles').upsert({'id': userId, ...})`, where `userId` comes from the Supabase Auth session.
- Most user references in chat, calls, reports, blocking, stickers, and games reference `public.profiles(id)`.

Email is not the system identity field in application tables. Email is only passed into Supabase Auth login, signup, and password reset APIs.

Known inconsistency:

- `public.chat_user_state.user_id` references `auth.users(id)` directly, while most other user-related tables reference `public.profiles(id)`. Because `profiles.id` itself references `auth.users(id)`, the UUID identity remains the same, but the foreign-key target is inconsistent.

### Username model

Username is stored in `public.profiles.username`.

Current database definition:

- Type: `citext`
- Required: `not null`
- Unique: `unique`
- Length check: `char_length(trim(username::text)) between 3 and 32`

Current client/profile setup validation:

- Required for email-profile completion.
- Optional for anonymous login.
- Trimmed before save.
- 3 to 24 characters.
- Allowed regex: `^[a-zA-Z0-9._]+$`.

Current profile update paths do not consistently apply that validator.

### Email model

Email is handled by Supabase Auth only in the checked application code:

- Login: `_client.auth.signInWithPassword(email: email, password: password)`
- Signup: `_client.auth.signUp(email: email, password: password, emailRedirectTo: ...)`
- Password reset: `_client.auth.resetPasswordForEmail(email, redirectTo: ...)`

No `email` column exists in `public.profiles` or the canonical public schema. No checked app query joins, filters, or foreign-keys application data by email.

Whether the underlying `auth.users.email` is unique is not defined in the repository SQL, because the Supabase-managed `auth.users` table DDL is not present here. The client expects duplicate email signup to fail and maps Supabase Auth errors such as `user already registered`.

## 2. DATABASE FINDINGS

### `public.profiles`

Canonical table:

```sql
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique,
  ...
  constraint profiles_username_length_check
    check (char_length(trim(username::text)) between 3 and 32),
  constraint profiles_bio_length_check
    check (char_length(bio) <= 280),
  ...
);
```

Constraints and indexes:

- Primary key: `id`
- Foreign key: `id -> auth.users(id) on delete cascade`
- Unique constraint: `username` via `username citext not null unique`
- Username length check: trimmed length 3 to 32
- Trigram index: `idx_profiles_username_trgm on public.profiles using gin ((username::text) gin_trgm_ops)`
- RLS:
  - `profiles_select_authenticated`: `using (auth.uid() = id)`
  - `profiles_insert_own`: `with check (auth.uid() = id)`
  - `profiles_update_own`: `using (auth.uid() = id) with check (auth.uid() = id)`

What the DB enforces for usernames:

- Case-insensitive uniqueness through `citext`. `Tony` and `tony` cannot both exist as distinct usernames in the same `username` column.
- Non-null username.
- Trimmed username length between 3 and 32.

What the DB does not enforce:

- No lowercase normalization.
- No generated normalized username column.
- No regex/character whitelist for letters, numbers, dots, and underscores.
- No check preventing internal spaces, punctuation, emoji, or other characters.
- No unique index on `trim(username::text)` or a normalized trimmed value. Because the unique constraint is on raw `citext`, values that differ by leading/trailing whitespace are not explicitly ruled out by a trim-normalized unique constraint.

### Other user-related canonical tables

User-reference pattern in `supabase/cipherchat_schema.sql`:

- `public.chats.created_by -> public.profiles(id)`
- `public.chat_members.user_id -> public.profiles(id)`, with `unique(chat_id, user_id)`
- `public.stickers.user_id -> public.profiles(id)`
- `public.messages.sender_id -> public.profiles(id)`
- `public.messages.deleted_for_everyone_by -> public.profiles(id)`
- `public.message_receipts.user_id -> public.profiles(id)`, with `unique(message_id, user_id)`
- `public.user_stickers.user_id -> public.profiles(id)`, with `unique(user_id, sticker_id)`
- `public.chat_requests.user_id/requested_by/sender_id/receiver_id -> public.profiles(id)`
- `public.call_sessions.caller_id/callee_id -> public.profiles(id)`
- `public.call_signals.sender_id -> public.profiles(id)`
- `public.blocked_users.blocker_id/blocked_user_id -> public.profiles(id)`, with `unique(blocker_id, blocked_user_id)`
- `public.user_reports.reporter_id/reported_user_id -> public.profiles(id)`
- `public.direct_chat_pairs.left_user_id/right_user_id -> public.profiles(id)`, with primary key `(left_user_id, right_user_id)`
- `public.chat_user_state.user_id -> auth.users(id)`, with primary key `(chat_id, user_id)`

Game tables also reference `public.profiles(id)`:

- `grid_breach_matches.player_1_id`, `player_2_id`, `current_turn`, `winner_id`, `rematch_requested_by`
- `grid_breach_moves.player_id`
- scoreboard migrations use profile UUIDs for player IDs.

### Database profile lookup functions

`get_visible_profiles_by_ids(uuid[])`:

- Fetches by `p.id = any(p_user_ids)`.
- Returns `id`, `username`, avatar/profile fields, privacy-filtered profile fields, and booleans such as `is_contact` and `is_blocked`.
- Uses `auth.uid()` as viewer identity.

`search_visible_profiles(text, integer)`:

- Searches profiles by username only:
  - `p.username::text ilike '%' || v.query || '%'`
  - `p.username::text % v.query`
- Excludes current viewer: `p.id <> v.viewer_id`.
- Returns profile rows with privacy-filtered fields.

`search_global_contacts(text, integer)`:

- Searches by `p.username::text ilike` and trigram similarity.
- Returns `user_id`, `username`, `avatar_id`, `direct_chat_id`, shared chat count, relevance.

Presence functions:

- `heartbeat_profile_presence()` updates the row where `id = auth.uid()`.
- `set_profile_presence_offline()` updates the row where `id = auth.uid()`.

### Old SQL and migrations

The checked `supabase/OLD DATABASE/schema.sql` repeatedly defines the same core identity model:

- `id uuid primary key references auth.users(id) on delete cascade`
- `username citext not null unique`
- `profiles_username_length_check`
- `idx_profiles_username_trgm`

Old migrations add profile privacy/presence/avatar fields and constraints but do not add a separate display name, normalized username field, or server-side username character whitelist. Current `supabase/migrations/` mainly adds game, sticker, inbox, and hardening objects; it does not redefine `public.profiles.username`.

## 3. BACKEND FINDINGS

There is no separate backend server implementation in this repository. Backend behavior is implemented through Supabase Auth, Supabase PostgREST table calls, RPC functions, and RLS policies.

### Authentication repository

`lib/features/auth/data/repositories/auth_repository.dart`:

- `signInWithEmail(email, password)` calls Supabase Auth with email and password.
- `signUpWithEmail(email, password)` calls Supabase Auth with email and password.
- `sendPasswordResetEmail(email)` calls Supabase Auth password reset.
- `fetchProfile(userId)` reads `profiles` by `.eq('id', userId)`.
- `createProfile(userId, username, gender, avatarId)` upserts:
  - `id: userId`
  - `username: username.trim()`
  - `gender`
  - `avatar_id`
  - `is_online: true`
- `isUsernameAvailable(username)` checks `.eq('username', username.trim())`.
- `updateProfile(userId, username, ...)` updates `profiles` by `.eq('id', userId)` and sets `updates['username'] = username.trim()` when username is provided.
- `generateAnonymousUsername(userId)` returns `user_${first8HexChars}`.

Backend validation actually enforced by Supabase/Postgres:

- RLS only allows insert/update of the caller's own profile row.
- DB unique/citext blocks case-insensitive duplicate usernames.
- DB trimmed length check blocks usernames shorter than 3 or longer than 32 after trimming.
- DB does not enforce the app's character regex.

### Auth controller

`lib/features/auth/presentation/providers/auth_provider.dart`:

- Current identity is `session.user.id`.
- Anonymous login validates optional username using `optionalUsernameValidationMessage`.
- Email profile completion validates username using `usernameValidationMessage`.
- Email signup validates email/password only; profile is created later after session/profile setup.
- `updateProfile(...)` does not call `usernameValidationMessage` before forwarding username to repository.

This creates a current-state validation split:

- Initial profile completion path validates username format in the controller.
- Later profile/settings update path does not validate username format in the controller.

### Profile and chat repositories

User fetch/query trace:

- `AuthRepository.fetchProfile`: by profile `id`.
- `ContactProfileRepository.fetchContactProfile`: by RPC `get_visible_profiles_by_ids([contactUserId])`.
- `ChatRepository.fetchChatMembers`: fetches chat members, then enriches via `_fetchVisibleProfilesByIds(userIds: member.userId list)`.
- `ChatRepository.searchUsers`: calls RPC `search_visible_profiles(p_query, p_limit)`, then filters out `currentUserId`.
- `ChatRepository._fetchVisibleProfile`: calls `get_visible_profiles_by_ids([userId])`.
- `main.dart` notification sender lookup: calls `get_visible_profiles_by_ids([senderId])`, then uses returned `username` as display text.
- `IdentityKeyService.ensurePublishedIdentity` and `ChatRepository.ensurePublicKey`: update `profiles.e2ee_public_key` by `.eq('id', userId)`.

No checked repository fetches application users by email.

## 4. CLIENT FINDINGS

### Signup and login UI

`lib/features/auth/presentation/screens/auth_screen.dart`:

- Login form collects email/password.
- Signup form collects email/password only.
- Profile completion card collects username and gender after auth session exists and `profile == null`.
- Anonymous tab collects optional username and gender.

Email validation:

- `AppErrorHelper.emailValidationMessage`
  - trims input
  - requires non-empty
  - regex: `^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$`

Password validation:

- Login requires non-empty password.
- Signup requires 8+ characters, uppercase, lowercase, and a number.

Username validation used here:

- `AppErrorHelper.usernameValidationMessage`
  - trims input
  - required
  - min 3
  - max 24
  - regex `^[a-zA-Z0-9._]+$`
- `AppErrorHelper.optionalUsernameValidationMessage`
  - empty is allowed for anonymous
  - non-empty delegates to the same username validator

### Profile edit screens

`lib/features/settings/presentation/screens/profile_settings_screen.dart`:

- Has a plain `TextField` for username.
- Save condition only requires `.trim().isNotEmpty`.
- Saves via `authController.updateProfile(username: _usernameController.text.trim(), ...)`.
- Does not call `AppErrorHelper.usernameValidationMessage`.

`lib/features/settings/presentation/screens/settings_screen.dart` and `sections/account_section.dart`:

- Account section uses a plain `TextField` for username.
- `_saveAccountSection` calls `authController.updateProfile(username: _usernameController.text.trim(), bio: ..., gender: ..., avatarId: ...)`.
- Does not call `AppErrorHelper.usernameValidationMessage`.

Current mismatch:

- Initial username creation screens enforce allowed characters and 24-character max.
- Settings/profile edit screens do not enforce allowed characters or 24-character max before sending update.
- The DB allows up to 32 trimmed characters and does not enforce the character regex.

### Display name handling

No separate display-name field was found in the active schema or client models.

Current display behavior:

- `AppUser.username` is displayed as the user-facing name.
- Chat tiles use `ChatMember.username`.
- Contact profile header uses `data.user.username`.
- Notification sender display uses returned `username`.
- Search results display `AppUser.username`.

Group names are stored separately as `chats.title`; that is group metadata, not user display name.

## 5. CRITICAL ISSUES (HIGH PRIORITY)

### 1. Username format is not consistently enforced after profile creation

Current state:

- Initial profile completion validates usernames with `^[a-zA-Z0-9._]+$` and max length 24.
- Profile edits in `ProfileSettingsScreen` and `SettingsScreen` do not use this validator.
- `AuthController.updateProfile` does not validate username.
- DB only checks trimmed length 3 to 32 and uniqueness.

Real risk:

- A logged-in user can change their own username through the app settings path to values that initial signup would reject, as long as the DB length and uniqueness checks pass.
- Examples allowed by DB/update path but rejected by initial client validator: names with spaces, punctuation outside dot/underscore, and 25-32 character usernames.

### 2. Database has no canonical normalized username field

Current state:

- `username` is `citext`, so case-insensitive uniqueness exists.
- Stored value preserves submitted casing.
- There is no `username_normalized` column.
- There is no unique index on `lower(trim(username::text))` or equivalent normalized expression.

Real risk:

- Case duplicates such as `Tony` and `tony` are blocked by `citext`.
- Trim/format variants are not explicitly normalized by the DB. Direct API writes or any unvalidated client path can persist visually confusing usernames if they satisfy trimmed length and raw `citext` uniqueness.

### 3. Client and DB username length rules disagree

Current state:

- Client creation validator: max 24 characters.
- DB constraint: max 32 trimmed characters.
- Profile update client path does not apply the 24-character validator.

Real risk:

- Usernames from 25 to 32 characters can exist after profile edit or direct API update, even though initial profile creation UI rejects them.

## 6. MEDIUM / LOW ISSUES

### Medium: `isUsernameAvailable` exists but is not used in checked signup/profile flows

Current state:

- `AuthRepository.isUsernameAvailable(username)` queries `profiles` by `.eq('username', username.trim())`.
- The checked profile creation flow relies on the DB unique constraint and error mapping instead of prechecking availability.

Impact:

- Duplicate username handling is database-backed and safe for uniqueness, but availability behavior is not proactively checked in the current UI flow.

### Medium: `chat_user_state.user_id` references `auth.users(id)` while related app tables reference `profiles(id)`

Current state:

- `chat_user_state.user_id` points to `auth.users`.
- Other user-owned/chat user fields point to `public.profiles`.

Impact:

- The UUID identity is the same, but referential modeling is inconsistent.
- A `chat_user_state` row can be valid against `auth.users` even if no `profiles` row exists yet for that user.

### Low: Email uniqueness is not auditable from repository SQL

Current state:

- No public application table stores email.
- Supabase Auth APIs are used for email login/signup/reset.
- The repository does not define the Supabase-managed `auth.users` table or its constraints.

Impact:

- Application code expects duplicate email signup to be rejected by Supabase Auth, but the exact DB constraint is outside the checked schema files.

### Low: No separate display name model

Current state:

- User-facing display name is always username.
- No display-name-specific restrictions or non-unique display-name behavior exist.

Impact:

- There is no current risk of accidental display-name uniqueness enforcement because no display-name field exists.

## 7. FINAL VERDICT

Is system SAFE or UNSAFE for usernames?

UNSAFE for username format consistency. SAFE against case-only duplicate usernames in the canonical `profiles.username` field because `citext unique` blocks `Tony` and `tony` from coexisting. NOT SAFE against invalid-format usernames entering through profile update paths or direct authenticated profile updates, because server/database enforcement does not match the client creation validator.

Is refactor REQUIRED before scaling?

Yes, for username/profile consistency before scaling. The current identity field is coherent and UUID-based, and email is not misused as application identity. The username system, however, has mismatched client and DB rules, no canonical normalized username field, no DB character whitelist, and profile update paths that bypass the initial username validator.

Edge-case answers from current implementation:

- Can `Tony` and `tony` both exist? No, not in `profiles.username`, because it is `citext unique`.
- Can two users share the same email? Not determinable from repository SQL; app code delegates this to Supabase Auth and expects duplicate email rejection.
- Can username be changed without the initial username validator? Yes, via settings/profile update paths.
- Can duplicate usernames be created via API bypass? Case-insensitive exact duplicates are blocked by DB unique `citext`; trim/format variants are not blocked by a normalized unique expression.
- Is email used in joins, lookups, or foreign keys? No checked application table/query uses email for joins, profile lookup, or foreign keys.
