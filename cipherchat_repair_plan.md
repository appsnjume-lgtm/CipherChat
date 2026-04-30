# CipherChat Refactor Plan
> Generated from audit dated 2026-04-28. Feed to Codex one phase at a time.

---

## Rules for Codex

- Read each file fully before editing it
- Make targeted edits — do not rewrite files wholesale
- Do not change function signatures unless the task explicitly requires it
- Do not rename existing model classes or database columns
- Each phase should be a separate commit — do not mix phase changes
- After every SQL migration, update the canonical `cipherchat_schema.sql` to match
- All new Supabase RPCs must use `SECURITY DEFINER` and validate `auth.uid()` matches `p_user_id` before returning data

---

## Phase 1 — Security (nothing else ships until this is done)

### 1.1 — Remove and replace `.env` config
**Files:** `.env`, `pubspec.yaml`, `lib/core/startup/app_startup.dart`, `README`

- Remove `.env` from the `assets` list in `pubspec.yaml`
- Delete `.env` from source control and add it to `.gitignore`
- Create `.env.example` with placeholder values only
- Replace all `dotenv` reads of `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `app_startup.dart` with `--dart-define` constants using `String.fromEnvironment`
- Update the README with instructions for passing `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` at build time

### 1.2 — Fix sticker privacy
**Files:** `supabase/cipherchat_schema.sql`, new migration file, `lib/features/chat/data/repositories/sticker_repository.dart`

- In `cipherchat_schema.sql`, change the `stickers_select_public_or_owner` RLS policy from `using (true)` to `using (is_public = true OR user_id = auth.uid())`
- Write a migration `supabase/migrations/YYYYMMDD_fix_sticker_privacy.sql` that:
    - Drops the old `stickers_select_public_or_owner` policy
    - Creates the correct policy as above
    - Changes the `stickers` storage bucket from public to private
- In `sticker_repository.dart`, replace all `getPublicUrl` calls for sticker objects with `createSignedUrl` with an appropriate expiry, for both upload and retrieval paths

### 1.3 — Sync canonical schema with hardening migration
**Files:** `supabase/cipherchat_schema.sql`

- Find the `group_images_select_authenticated` policy in `cipherchat_schema.sql`
- Replace it with `group_images_select_members_only` to match `supabase/migrations/20260414_preproduction_hardening.sql`
- Verify no other policies in the canonical schema contradict the hardening migration

---

## Phase 2 — Critical Bug Fixes

### 2.1 — Fix direct chat delete (Bug B3)
**Files:** `lib/features/chat/data/repositories/chat_repository.dart`

- Find the `deleteChat` method
- Add a branch: if the chat is a direct chat, do NOT call the `delete_chat` RPC; instead upsert `chat_user_state` with `hidden_at = now()` for the current user
- If a `chat_user_state` upsert helper doesn't exist, add a private method that calls the Supabase table directly
- Ensure the chat list query filters out chats where `chat_user_state.hidden_at` is set for the current user

### 2.2 — Fix grid_breach cache parsing (Bug B1)
**Files:** `lib/core/services/local_chat_cache_service.dart`

- Find `_messageKindFromValue` (around line 398–413)
- Add `case 'grid_breach': return MessageKind.grid_breach;` to the switch/if chain

### 2.3 — Fix grid_breach pending sync crash (Bug B2)
**Files:** `lib/features/chat/application/services/pending_outgoing_message_sync_service.dart`

- Find the switch on `MessageKind` around line 172
- Replace the `UnimplementedError` for `grid_breach` with an explicit permanent-drop: log a warning and mark the record as permanently failed so it does not block the sync loop

### 2.4 — Fix call channel disposal (Bug B4)
**Files:** `lib/features/call/presentation/providers/call_provider.dart`

- Find every call to `disposeChannel()` inside `dispose` or teardown methods (around lines 90–96 and 438–448)
- Wrap each with `unawaited(disposeChannel().catchError((e) => debugPrint('channel dispose error: $e')))`

---

## Phase 3 — Performance: Startup & Chat List

### 3.1 — Create `get_chat_inbox` RPC
**Files:** New migration `supabase/migrations/YYYYMMDD_add_get_chat_inbox.sql`, `supabase/cipherchat_schema.sql`

- Write a `SECURITY DEFINER` PostgreSQL function `get_chat_inbox(p_user_id uuid)` that returns one row per chat the user is a member of, containing:
    - All columns from the `chats` table
    - Member list with visible profiles (reuse logic from `get_visible_profiles_by_ids`)
    - Latest message via a `LATERAL` subquery on `messages ORDER BY created_at DESC LIMIT 1`
    - Unread count from `message_receipts` where `user_id = p_user_id` and unread
    - Excludes chats where `chat_user_state.hidden_at` is set for `p_user_id`
- Confirm indexes exist: `chat_members(user_id)`, `messages(chat_id, created_at DESC)` — create them if missing
- Update `cipherchat_schema.sql` to include the new function

### 3.2 — Replace N+1 chat hydration with the inbox RPC
**Files:** `lib/features/chat/data/repositories/chat_repository.dart`

- Replace the `fetchChats` and `_buildChat` fan-out logic with a single call to `get_chat_inbox`
- Parse the returned JSON into the existing chat/member/message model classes
- Keep the local cache load as the immediate first render; fire `get_chat_inbox` after and reconcile

### 3.3 — Defer realtime channel subscriptions
**Files:** `lib/features/chat/presentation/providers/chat_provider.dart`, `lib/core/services/realtime_service.dart`

- Change `_syncSubscriptions` so it does NOT open per-chat message/receipt channels for every chat on startup
- Subscribe to a single user-scoped channel for inbox-level changes (new messages, unread count updates)
- Open full message + receipt + typing channels only when a chat is actively opened
- Unsubscribe from those channels when the user navigates away from the chat

### 3.4 — Unblock auth gate from remote profile fetch
**Files:** `lib/features/auth/presentation/screens/auth_gate_screen.dart`, `lib/features/auth/presentation/providers/auth_provider.dart`

- Change the routing condition in `auth_gate_screen.dart` so a valid session alone is enough to navigate to `ChatListScreen` — profile `null` must no longer block routing
- Show a loading/skeleton state inside the app shell while profile loads
- In `auth_provider.dart`, ensure `fetchProfile` still runs after routing and updates state asynchronously

---

## Phase 4 — Performance: Database & Queries

### 4.1 — Reduce receipt over-fetching
**Files:** `lib/features/chat/data/repositories/chat_repository.dart`

- Find `fetchMessages` (around line 198–212)
- Change the query from `"*, message_receipts(*)"` to select only the current user's receipt row per message
- For the sender's delivery/read aggregate, add a separate lightweight query that fetches receipt summary (delivered count, read count) only when the sender explicitly requests receipt detail

### 4.2 — Fix discoverable groups over-fetch
**Files:** `lib/features/chat/data/repositories/chat_repository.dart`, new Supabase RPC or filtered query

- Find `fetchDiscoverableGroups` (around line 82–99)
- Add limit and offset for pagination
- Replace full `_buildChat` hydration with a lightweight query returning only: group id, name, image, member count, and whether the current user is already a member or has a pending request — no latest message, no full member list

### 4.3 — Delay pending outbox sync
**Files:** `lib/main.dart`

- Find the `syncAllPendingMessages` call (around lines 134–140)
- Move the call so it fires after `ChatListScreen` completes its first render using a post-frame callback or short `Future.delayed`

---

## Phase 5 — Notification Optimization

### 5.1 — Cache notification lookups (Bug B5)
**Files:** `lib/main.dart`

- Find `_showIncomingMessageNotification` (around lines 306–321 and 341–361)
- Do not query Supabase for current user profile/notification settings on every message — read these from the already-loaded `AuthController` profile state in memory
- Add a short-lived in-memory cache (`Map` with a timestamp) for sender profile display names and chat titles, keyed by their IDs, with a TTL of ~5 minutes
- Only hit the DB on a cache miss

---

## Phase 6 — Observability (do last)

### 6.1 — Add startup tracing
**Files:** `lib/core/startup/app_startup.dart`, `lib/main.dart`

- Wrap each major startup step with a `Stopwatch` or Flutter `TimelineTask`:
    - dart-define read
    - `Supabase.initialize`
    - Auth session recovery
    - `fetchProfile`
    - `get_chat_inbox` call
    - Realtime channel setup
- Print results with `debugPrint` in debug mode only — strip in release builds

---

## Summary Table

| Phase | Area                                           | Priority    |
|-------|------------------------------------------------|-------------|
| 1.1   | Remove `.env` from assets, use dart-define     | 🔴 Critical |
| 1.2   | Fix sticker RLS + storage bucket privacy       | 🔴 Critical |
| 1.3   | Sync canonical schema with hardening migration | 🔴 Critical |
| 2.1   | Fix direct chat delete → hide/archive instead  | 🔴 Critical |
| 2.2   | Fix `grid_breach` cache parsing                | 🟠 High     |
| 2.3   | Fix `grid_breach` pending sync crash           | 🟠 High     |
| 2.4   | Fix call channel disposal                      | 🟠 High     |
| 3.1   | Create `get_chat_inbox` RPC                    | 🟠 High     |
| 3.2   | Replace N+1 chat hydration                     | 🟠 High     |
| 3.3   | Defer realtime channel subscriptions           | 🟠 High     |
| 3.4   | Unblock auth gate from profile fetch           | 🟠 High     |
| 4.1   | Reduce receipt over-fetching                   | 🟡 Medium   |
| 4.2   | Fix discoverable groups over-fetch             | 🟡 Medium   |
| 4.3   | Delay outbox sync to post-render               | 🟡 Medium   |
| 5.1   | Cache notification lookups                     | 🟡 Medium   |
| 6.1   | Add startup tracing                            | 🔵 Optional |