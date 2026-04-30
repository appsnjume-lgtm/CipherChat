## GRID BREACH (GX MODE) Implementation Steps

### 1. [x] Database Schema

- `supabase/migrations/20260404_create_grid_breach.sql` ✅
- **User action required: Run SQL in Supabase SQL editor → Verify tables/RLS/realtime**

- Create `supabase/migrations/202604XX_create_grid_breach.sql` with tables: grid_breach_matches, grid_breach_moves, grid_breach_board_state
- Include RLS policies, indexes, triggers/functions for move validation/win detect
- User: Run SQL in Supabase dashboard

### 2. [x] Game Models

- `lib/features/chat/game/data/models/game_models.dart` ✅ (simple JSON models)

- `lib/features/chat/game/data/models/game_models.dart`: GridBreachMatch, GridBreachMove, BoardState (List<List<int?>> 6x7)

### 3. [x] Game Repository

- `lib/features/chat/game/data/repositories/game_repository.dart` ✅ (createMatch, makeMove, realtime sub)

- `lib/features/chat/game/data/repositories/game_repository.dart`: createMatch, makeMove (validate/server logic), subscribeToMoves

### 4. [x] Game Provider

- `lib/features/chat/game/presentation/providers/game_provider.dart` ✅ (GameController)

- `lib/features/chat/game/presentation/providers/game_provider.dart`: GameController (state mgmt, loadMatch, makeMove)

### 5. [x] Game Screen

- `lib/features/chat/game/presentation/screens/game_screen.dart` ✅ GX board UI/anims
- `lib/features/chat/game/domain/game_utils.dart` ✅ win detect/drop logic

- `lib/features/chat/game/presentation/screens/game_screen.dart`: Board UI, col taps, anims, GX styling
- `lib/features/chat/game/presentation/widgets/` : BoardGrid, NodeDropAnim, WinOverlay

### 6. [x] Realtime Integration

- Edit `lib/core/services/realtime_service.dart`: ✅ subscribeToGameMoves

- Edit `lib/core/services/realtime_service.dart`: add subscribeToGameMoves (PostgresChanges on moves/board)

### 7. [ ] Chat Integration

- Edit `lib/features/chat/presentation/screens/chat_screen.dart`: Parse game challenges in messages, accept button → create match → nav to game
- Edit `lib/features/chat/presentation/providers/message_provider.dart`: add sendGameChallenge

### 8. [x] Router

- Edit `lib/core/router/app_router.dart` ✅ /chat/game/:matchId

- Add route `/chat/game/:matchId` if needed

### 9. [ ] Test

- Challenge → accept → moves sync → win/draw → back

### 10. [ ] Polish

- Anims: drop easing, win pulse/scanline
- GX guards: isGX ? terminal UI : null
