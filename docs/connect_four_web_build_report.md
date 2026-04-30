# Connect Four / GRID BREACH Implementation Report

## Purpose

This file documents how the current mobile app implements the Connect Four feature that is branded as `GRID BREACH`.

The goal is to give you enough exact detail to rebuild the feature for the web while staying compatible with the current Flutter client and Supabase backend.

This report covers:

- Match creation and chat invite flow
- Game states and lifecycle
- Board model, columns, rows, turns, and win rules
- Disc drop animation and board hit testing
- Timer and timeout behavior
- Rematch, quit, draw, and scoreboard logic
- Realtime flow
- Supabase schema, RPCs, RLS, and authoritative validation
- Important implementation quirks you should know before building the web version

This report ignores everything inside folders named `OLD`.

## Source Of Truth

There are multiple SQL files for Grid Breach. The latest behavior is defined by the non-OLD migration chain, not just the standalone `grid_breach_schema.sql` file.

Use these as the effective source of truth:

- [game_repository.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/data/repositories/game_repository.dart)
- [game_provider.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/presentation/providers/game_provider.dart)
- [game_screen.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/presentation/screens/game_screen.dart)
- [grid_breach_board_layout.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/presentation/widgets/grid_breach_board_layout.dart)
- [game_models.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/data/models/game_models.dart)
- [game_utils.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/domain/game_utils.dart)
- [20260404_create_grid_breach.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260404_create_grid_breach.sql)
- [20260405_harden_grid_breach.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260405_harden_grid_breach.sql)
- [20260406_allow_grid_breach_message_type.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260406_allow_grid_breach_message_type.sql)
- [20260406_cleanup_grid_breach_runtime.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260406_cleanup_grid_breach_runtime.sql)
- [20260407_fix_grid_breach_false_wins.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260407_fix_grid_breach_false_wins.sql)
- [20260408_add_grid_breach_rematch_flow.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260408_add_grid_breach_rematch_flow.sql)
- [20260409_add_grid_breach_scoreboard_and_timer.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260409_add_grid_breach_scoreboard_and_timer.sql)
- [20260410_add_grid_breach_quit_flow.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260410_add_grid_breach_quit_flow.sql)
- [20260411_update_grid_breach_quit_and_timeout_rules.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260411_update_grid_breach_quit_and_timeout_rules.sql)
- [20260412_backfill_grid_breach_runtime_columns.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260412_backfill_grid_breach_runtime_columns.sql)
- [20260413_harden_grid_breach_move_integrity_and_server_clock.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260413_harden_grid_breach_move_integrity_and_server_clock.sql)

## Product Framing

- Internal/product name: `GRID BREACH`
- Actual ruleset: classic Connect Four
- Board size: 7 columns x 6 rows
- Players: exactly 2
- Game type: direct head-to-head, launched from chat
- Spectators: not supported
- Group chat support: effectively not supported for starting a match
- Theme dependency on mobile: the dedicated game screen only renders the full game UI when GX theme is active

## Where Matches Come From

### Launch Path

The match starts from chat, not from a standalone lobby.

In [chat_screen.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/presentation/screens/chat_screen.dart), `_launchGridBreach` does this:

1. Finds the peer with `chat.otherMemberFor(currentUserId)`.
2. Creates a new match in Supabase.
3. Sends a chat message of kind `grid_breach` whose encrypted payload contains the new `match_id`.
4. Navigates directly to `/chat/game/:matchId`.

Important details:

- The launcher requires a peer user, so it only works in a direct chat model.
- `createMatch` requires a non-empty `chatId`, but the current backend does not store `chat_id` in the match table.
- The chat message is what links the match to a chat conversation in practice.

### Route

The game screen is opened with:

- `/chat/game/:matchId`

Defined in [app_router.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/core/router/app_router.dart).

## Chat Message Representation

Grid Breach is also a chat message type.

### Message Kind

The message layer adds:

- `MessageKind.grid_breach`

Defined in [message.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/domain/entities/message.dart).

### Encrypted Payload

The invite payload is encrypted like other chat payloads. The only data inside is:

```json
{ "match_id": "<uuid>" }
```

This is written by `sendGridBreachInvite` in [secure_chat_service.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/application/services/secure_chat_service.dart).

### Resolved Message Presentation

When decrypted, the message resolves to:

- Text label: `GRID BREACH INVITE`
- `gameMatchId`: decrypted `match_id`

The resolved message model also carries:

- `isExpiredGridBreachSession`

Defined in [resolved_chat_message.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/application/models/resolved_chat_message.dart).

### Invite Bubble Behavior

The invite card UI is in [message_bubble.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/presentation/widgets/message_bubble.dart).

Displayed states:

- If disabled: subtitle is `Challenge expired`, button is `EXPIRED`
- If sender is me: subtitle is `Waiting for breach...`, button is `RESUME`
- If sender is opponent: subtitle is `Incoming breach attempt!`, button is `ACCEPT BREACH`

Important behavior:

- Tapping `ACCEPT BREACH` does not directly accept on the server.
- It only opens the game screen.
- Actual acceptance happens inside the game screen when player 2 presses `Accept Breach`.

### Invite Expiration Rules In Chat

A Grid Breach invite bubble is considered inactive when either of these is true:

1. The linked match is missing or is an expired quit session.
2. It is not the latest visible Grid Breach invite in the chat.

This means:

- Only the newest visible Grid Breach invite stays active in chat.
- Older invite cards are dimmed even if their match still exists.
- A quit/forfeit match is considered expired for chat-card purposes.

That behavior is driven by [message_provider.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/presentation/providers/message_provider.dart) and [chat_screen.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/presentation/screens/chat_screen.dart).

## Core Domain Model

### Match

`GridBreachMatch` contains:

- `id`
- `player1Id`
- `player2Id`
- `currentTurnUserId`
- `status`
- `winnerId`
- `createdAt`
- `updatedAt`
- `moveTimeLimitSeconds`
- `turnStartedAt`
- `moveDeadlineAt`
- `rematchRequestedBy`
- `rematchRequestedAt`
- `quitBy`
- `quitAt`

Defined in [game_models.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/data/models/game_models.dart).

Useful derived flags:

- `isWaiting`
- `isActive`
- `isFinished`
- `isDraw`
- `isPlayer1Turn`
- `isPlayer2Turn`
- `hasRematchRequest`
- `hasQuitSignal`
- `isExpiredSession`

`isExpiredSession` means:

- match is finished
- and `quitBy != null`

### Move

`GridBreachMove` contains:

- `id`
- `matchId`
- `playerId`
- `columnIndex`
- `rowIndex`
- `createdAt`

### Scoreboard

`GridBreachScoreboard` contains:

- `leftPlayerId`
- `rightPlayerId`
- `leftWins`
- `rightWins`
- `draws`
- `updatedAt`

Important detail:

- Scoreboards are keyed by the lexicographically ordered pair of player UUIDs, not by match id.
- The scoreboard is lifetime-ish aggregate history for the pair, not per match.

### Board State

`BoardState` contains:

- `grid`
- `movesCount`
- `lastMoveAt`

Static dimensions:

- `rowCount = 6`
- `columnCount = 7`

## Board Representation

The board is a 2D `List<List<int?>>` on the client and JSONB on the server.

Cell values mean:

- `null` = empty
- `1` = player 1 disc
- `2` = player 2 disc

### Coordinate System

The board uses:

- `row 0` = top row
- `row 5` = bottom row
- `column 0` = leftmost column
- `column 6` = rightmost column

This matters because dropping a disc does not use inverted UI coordinates. The server literally searches from row `5` down to `0` to find the next empty slot.

### Empty Board Shape

Empty board JSON is:

```json
[
  [null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null]
]
```

### Finding The Drop Row

Client and server both follow gravity.

Client helper:

- `GameUtils.getNextRow(grid, column)`

Server helper:

- `grid_breach_find_drop_row(board, column_index)`

Logic:

1. Start from bottom row `5`.
2. Move upward toward row `0`.
3. Return the first empty row.
4. Return `-1` if the column is full or invalid.

## Turn Model

### Players

- Player 1 is the challenger who created the match.
- Player 2 is the invited peer.

### Initial Turn

Player 1 always gets the first turn.

That is true:

- When a fresh match is created
- When a match is accepted
- When a rematch is accepted

### Current Turn Fields

There are two turn fields in the database:

- `current_turn`
- `current_turn_user_id`

Important detail:

- `current_turn_user_id` is the newer authoritative field.
- `current_turn` is still maintained for backward compatibility.
- The client reads `current_turn_user_id`, but falls back to `current_turn` when decoding JSON.

### Client Turn Ownership

The provider computes:

- `myPlayerNumber`
- `isMyTurn`

`myPlayerNumber` values:

- `1`
- `2`
- `0` if current user is not one of the players

## Match Lifecycle

### 1. Match Creation

`GameRepository.createMatch` inserts a row into `grid_breach_matches` with:

- `player_1_id = challenger`
- `player_2_id = invited peer`
- `current_turn = player1`
- `current_turn_user_id = player1`
- `status = waiting`

Board state is auto-created by trigger.

### 2. Waiting State

Meaning:

- Invite exists
- Player 2 has not accepted yet
- No moves have been played

UI:

- Player 2 sees `Accept Breach`
- Player 1 sees waiting messaging

### 3. Accept Match

Only player 2 can accept a waiting match.

Server RPC:

- `grid_breach_accept_match(match_id)`

Effects:

- `status = active`
- turn remains player 1
- `turn_started_at = now()`
- `move_deadline_at = turn_started_at + move_time_limit_seconds`

### 4. Active Match

Meaning:

- Moves are allowed
- Turn timer runs
- Realtime updates matter

### 5. Win

A win happens when the last placed piece creates a contiguous line of 4 for the mover.

Server effects:

- `status = finished`
- `winner_id = mover`
- turn fields point to winner
- timer fields are cleared
- scoreboard is incremented

### 6. Draw

A draw happens when:

- `moves_count >= 42`
- and no winner was found on the last move

Server effects:

- `status = finished`
- `winner_id = null`
- turn fields point to next player
- timer fields are cleared
- scoreboard draw count increments

### 7. Quit

Quit is a forfeit.

Server RPC:

- `grid_breach_quit_match(match_id)`

Effects:

- active match ends immediately
- quitter loses
- opponent becomes winner
- `quit_by` and `quit_at` are set
- rematch is blocked for quit matches
- scoreboard increments the opponent’s win

### 8. Timeout Claim

In the latest implementation, timeout is a win claim, not a turn skip.

Server RPC used by the app:

- `claim_timeout(match_id)`

Alias also exists:

- `grid_breach_claim_timeout(match_id)`

Effects:

- active match ends immediately
- claimant becomes winner
- timer fields are cleared
- rematch request fields are cleared
- scoreboard increments claimant’s win

Historical note:

- Earlier migrations changed timeout behavior over time.
- The current end state is final-win-on-claim, not pass-turn-on-claim.

### 9. Rematch Request

Server RPC:

- `grid_breach_request_rematch(match_id)`

Allowed only when:

- match is finished
- current user is a participant
- `quit_by is null`

Effects:

- sets `rematch_requested_by`
- sets `rematch_requested_at`

### 10. Rematch Accept

Server RPC:

- `grid_breach_accept_rematch(match_id)`

Allowed only when:

- match is finished
- current user is the other player
- a rematch request exists
- `quit_by is null`

Effects:

- deletes old moves
- resets board state to empty
- clears winner
- clears rematch fields
- clears quit fields
- sets `status = active`
- resets turn to player 1
- starts a new timer window
- scoreboard is preserved

## Win Detection

### Client Utility Logic

Client helper in [game_utils.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/domain/game_utils.dart):

- `findWinningLine(grid)`
- `winnerForGrid(grid)`

Directions checked from every occupied cell:

- Horizontal: `(0, 1)`
- Vertical: `(1, 0)`
- Diagonal down-right: `(1, 1)`
- Diagonal up-right: `(-1, 1)`

The first full length-4 line found is returned.

### Server Win Logic

Server helpers:

- `grid_breach_board_cell`
- `grid_breach_count_direction`
- `grid_breach_has_winner`
- `grid_breach_board_winner`

Actual move validation only checks the last placed piece, which is correct and efficient.

For each of the 4 directions above, server counts:

- contiguous same-player cells in the positive direction
- contiguous same-player cells in the negative direction
- plus the placed cell itself

If the maximum total is `>= 4`, the mover wins.

## Board Interaction On The Client

### Tap To Column Mapping

The client does not tap cells directly. It taps a board surface and converts X position to a column.

Defined in [grid_breach_board_layout.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/presentation/widgets/grid_breach_board_layout.dart).

Layout constants:

- padding: `10` on all sides
- horizontal spacing: `8`
- vertical spacing: `8`

Column detection:

1. Convert tap X to local board X
2. Account for left padding
3. Use a stride of `cellWidth + spacing`
4. Accept taps slightly into the gutter using half-spacing tolerance
5. Clamp to `0..6`

### Column Labels

The board header renders labels:

- `1` through `7`

Each column label is tinted as:

- accent color if playable
- dim if full

### Move Guard On Tap

Tap only triggers `makeMove(column)` when:

- it is your turn
- match is active
- no submit is in progress
- no quit signal exists
- the local timer does not consider your turn expired
- the target column is locally valid

Server still revalidates everything.

## Disc Drop Animation And Visual Physics

The game simulates gravity visually even though the server writes the move instantly.

### Animation Queue

Incoming moves are queued in `_moveQueue`.

When state changes:

1. New move ids are detected by comparing previous vs next move lists.
2. Already applied, currently animating, or queued move ids are ignored.
3. New moves are appended to the queue.
4. `_processNextMoveAnimation()` runs one move at a time.

### Hidden Cells During Animation

To avoid drawing the new disc twice:

- the target cell of the animating move is hidden in the static board
- queued moves are also hidden until their animation runs

### Animation Timing

Animation controller:

- base duration = `420ms`

Actual per-move duration:

- `220 + (rowIndex * 45)` milliseconds

So deeper drops animate longer.

Examples:

- row `0`: `220ms`
- row `5`: `445ms`

### Animation Curve

The rendered drop uses:

- `Curves.easeInCubic`

This makes the disc accelerate downward rather than fall at constant speed.

### Starting Position

The animated disc starts above the board:

- `startTop = padding.top - cellHeight`

It ends aligned with the target row’s cell rectangle.

### Render Colors

- Player 1 disc uses the primary accent color
- Player 2 disc uses the rival color
- Winning discs get stronger glow/border emphasis

## Timer Model

### Authoritative Server Logic

Latest server logic uses:

- `turn_started_at`
- `move_time_limit_seconds`

Deadline is derived by:

- `grid_breach_turn_deadline(turn_started_at, move_time_limit_seconds)`

`move_deadline_at` still exists and is updated, but `turn_started_at + limit` is the modern authoritative logic.

### Default Limit

Default move time limit:

- `45` seconds

Constraint:

- must be between `15` and `120`

### Client Clock Sync

The client loads `serverNow` using:

- `grid_breach_server_now()`

Then it stores:

- `_serverNowAnchor`
- `_serverClock` stopwatch

Current local estimate of server time is:

- `serverNowAnchor + stopwatch.elapsed`

### UI Refresh Frequency

The timer display updates every:

- `100ms`

This is done by a periodic timer.

### Countdown Rules

Client remaining time is:

- `turnDeadlineAt - estimatedServerNow`

If negative:

- clamped to `Duration.zero`

### Expired States

Client helper flags:

- `myTurnExpired`
- `opponentTurnExpired`

Meaning:

- `myTurnExpired`: my active turn reached zero, so I can no longer move
- `opponentTurnExpired`: opponent’s turn reached zero and I can claim timeout

### Timer Labels

Timer text changes by state:

- quit match: `EXPIRED`
- inactive match: `STANDBY`
- opponent timeout claim available: `CLAIM`
- my turn expired: `WAIT`
- normal: `mm:ss`

Countdown display format:

- zero-padded minutes and seconds
- clamped to a max of `5999` seconds before formatting

### Urgency Styling

The timer becomes visually urgent when:

- `<= 20s`: warning
- `<= 5s`: urgent pulse

The pulse animation uses a separate controller with repeat/reverse behavior.

## Client Game State Machine

Client `GameStatus` enum values:

- `waiting`
- `active`
- `finished`
- `winPlayer1`
- `winPlayer2`
- `draw`

Computed in `GameController._statusFromSnapshot`.

Rules:

- waiting with zero moves => `waiting`
- finished + winner is player1 => `winPlayer1`
- finished + winner is player2 => `winPlayer2`
- finished + no winner or full board => `draw`
- otherwise finished => `finished`
- else => `active`

## Bottom Action Panel Logic

The bottom panel changes based on state in this order:

1. If player 2 can accept waiting match: show `Accept Breach`
2. Else if opponent timed out: show `Claim Win`
3. Else if opponent requested rematch: show `Accept`
4. Else if I already requested rematch: show waiting banner
5. Else if I can request rematch: show `Request Rematch`
6. Else show informational helper text

This ordering matters.

## Quit Logic On The Client

Quit is only available while:

- match is active
- current user is player 1 or 2
- no quit signal is already set
- no current submit/move submit/loading lock exists

Quit action:

1. Show confirmation dialog
2. If confirmed, call `quitMatch()`
3. On success, pop the game screen

Quit label semantics:

- quitter sees expired/forfeited language
- opponent sees opponent-quit/win language

## Realtime Behavior

### Channel Scope

The repository creates one realtime channel per match:

- `grid-breach-<matchId>`

It listens to all postgres change events for:

- `grid_breach_matches`
- `grid_breach_board_state`
- `grid_breach_moves`

All events are filtered by `match id`.

### Refresh Strategy

Any change triggers a full refresh of the match snapshot.

Snapshot loads:

1. match
2. board state
3. move list
4. scoreboard
5. server time

The provider has refresh coalescing:

- if a refresh is already running, it marks `_refreshQueued = true`
- once current refresh completes, one more refresh runs if needed

This reduces overlap but still reloads the full snapshot on every match change.

### Scoreboard Realtime

There is no separate scoreboard realtime subscription.

Instead:

- scoreboard is re-read during every snapshot refresh

## Supabase Data Model

### `grid_breach_matches`

Final effective columns:

- `id uuid primary key`
- `player_1_id uuid not null`
- `player_2_id uuid not null`
- `status text not null`
- `current_turn uuid not null`
- `current_turn_user_id uuid not null`
- `winner_id uuid null`
- `move_time_limit_seconds integer not null default 45`
- `turn_started_at timestamptz null`
- `move_deadline_at timestamptz null`
- `rematch_requested_by uuid null`
- `rematch_requested_at timestamptz null`
- `quit_by uuid null`
- `quit_at timestamptz null`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

Key constraints:

- players must be different
- status must be `waiting`, `active`, or `finished`
- current turn fields must reference one of the two players
- winner must be one of the two players or null
- rematch requester must be one of the two players or null
- quitter must be one of the two players or null
- if status is active, `turn_started_at` must exist
- move time limit must be between `15` and `120`

### `grid_breach_moves`

Columns:

- `id`
- `match_id`
- `player_id`
- `column_index`
- `row_index`
- `created_at`

Constraints:

- column between `0` and `6`
- row between `0` and `5`
- unique `(match_id, column_index, row_index)`

### `grid_breach_board_state`

Columns:

- `match_id`
- `board jsonb`
- `moves_count`
- `last_move_at`
- `updated_at`

Constraints:

- moves count between `0` and `42`

### `grid_breach_scoreboards`

Columns:

- `left_player_id`
- `right_player_id`
- `left_wins`
- `right_wins`
- `draws`
- `created_at`
- `updated_at`

Key:

- composite primary key `(left_player_id, right_player_id)`

## Supabase Functions And RPC Contract

### Read Helpers

- `grid_breach_empty_board() -> jsonb`
- `grid_breach_board_cell(board, row, column) -> integer`
- `grid_breach_find_drop_row(board, column) -> integer`
- `grid_breach_count_direction(...) -> integer`
- `grid_breach_has_winner(...) -> boolean`
- `grid_breach_board_winner(board) -> integer`
- `grid_breach_server_now() -> timestamptz`
- `grid_breach_turn_deadline(turn_started_at, move_time_limit_seconds) -> timestamptz`

### Auth/Access Helpers

- `is_grid_breach_player(match_id, user_id default auth.uid()) -> boolean`
- `is_grid_breach_current_turn(match_id, user_id default auth.uid()) -> boolean`
- `grid_breach_can_make_move(match_id, column_index) -> boolean`

### Match Lifecycle RPCs

- `grid_breach_accept_match(match_id) -> grid_breach_matches`
- `grid_breach_request_rematch(match_id) -> grid_breach_matches`
- `grid_breach_accept_rematch(match_id) -> grid_breach_matches`
- `grid_breach_quit_match(match_id) -> grid_breach_matches`

### Move/Timeout RPCs The Flutter App Calls

- `make_move(match_id, column_index) -> grid_breach_moves`
- `claim_timeout(match_id) -> grid_breach_matches`

Compatibility aliases also exist:

- `grid_breach_make_move(match_id, column_index)` delegates to `make_move`
- `grid_breach_claim_timeout(match_id)` delegates to `claim_timeout`

### Scoreboard Helper

- `grid_breach_record_result(player_1_id, player_2_id, winner_id default null) -> void`

Important for the web build:

- The current Flutter repository calls the short names `make_move` and `claim_timeout`.
- Your web client should call the same names unless you intentionally standardize on the aliased `grid_breach_*` names.

## Row Level Security

### Matches

Participants can:

- select matches they belong to

Authenticated users can insert matches only when:

- they are `player_1_id`
- players are distinct
- `current_turn = player_1_id`
- status is `waiting`
- `winner_id is null`

### Moves

In the latest setup, clients do not directly insert moves through table insert policy.

Effective write path:

- use RPCs

Participants can:

- select moves for their matches

### Board State

Participants can:

- select board state for their matches

### Scoreboards

Participants can:

- select scoreboard rows where they are either left or right player

### Spectator Implication

Because of RLS:

- no spectator/read-only public board mode exists

## Realtime Publication

The following tables are added to `supabase_realtime`:

- `grid_breach_matches`
- `grid_breach_moves`
- `grid_breach_board_state`

## Important Implementation Quirks

These are current app/backend realities. Some should be preserved for compatibility; some are worth improving in the web version.

### 1. `chatId` Is Validated But Not Stored In The Match

`createMatch` requires `chatId`, but the Grid Breach match schema does not store it.

Practical implication:

- chat linkage lives in the invite message, not in the match table

Recommendation for web:

- either preserve this model for compatibility
- or add a `chat_id` column intentionally and migrate both clients

### 2. Invite Acceptance Is Two-Step

The invite card button says `ACCEPT BREACH`, but tapping it only navigates to the match screen.

Actual acceptance happens from inside the game screen when player 2 presses `Accept Breach`.

If you rebuild on web, either:

- keep this exact flow
- or make invite acceptance happen directly from the card

### 3. Only The Latest Invite Stays Active In Chat

This is UI logic, not database logic.

Implication:

- older invites are visually expired even if their match still exists

### 4. Quit Matches Are Considered Expired Sessions

Finished matches with `quit_by != null` are treated specially:

- chat cards mark them expired
- rematch is blocked

### 5. Full Snapshot Refresh On Every Event

Realtime currently causes full re-fetches of:

- match
- board
- moves
- scoreboard
- server clock

This is simple but not optimal.

Recommendation for web:

- you can start with this exact model for parity
- later optimize to incremental reducers if needed

### 6. `getMatchesByIds` Is N+1

The invite-state enrichment in chat fetches match ids one by one.

That is not ideal to copy if you expect a heavy message history.

### 7. GX Theme Gating Is Product/UI Specific, Not Game Logic

The mobile screen blocks play UI unless GX theme is active.

This is not required for core game behavior.

### 8. Timer Is Server-Authoritative, But Client Still Animates Locally

The client estimates server time after one anchor fetch.

If web needs stronger accuracy under tab throttling/backgrounding, you may want:

- periodic server resync
- or more aggressive realtime reconciliation

## Exact Rules To Preserve For Web Parity

If the web version should behave exactly like mobile plus current backend, preserve these rules:

1. Two players only.
2. Board is 7 columns x 6 rows.
3. Player 1 creates the match and goes first.
4. Match starts as `waiting`.
5. Only player 2 can accept.
6. Row 5 is the bottom-most row for drops.
7. Win is any line of 4 in horizontal, vertical, or either diagonal direction.
8. Draw happens at 42 moves with no winner.
9. Move legality is server-authoritative.
10. Timeout claim ends the match and awards the claimant the win.
11. Quit ends the match and awards the opponent the win.
12. Quit matches cannot be rematched.
13. Rematch resets board and moves but preserves pair scoreboard.
14. Turn timer defaults to 45 seconds.
15. `current_turn_user_id` is the authoritative turn field.
16. Participants-only RLS applies everywhere.
17. Invite messages carry `match_id` in encrypted payload.
18. Realtime watches matches, board state, and moves.

## Suggested Web Architecture

To stay compatible while building cleanly, a good web implementation would keep these layers:

### API Layer

- `createMatch(player1Id, player2Id, chatId)`
- `acceptMatch(matchId)`
- `makeMove(matchId, columnIndex)`
- `claimTimeout(matchId)`
- `requestRematch(matchId)`
- `acceptRematch(matchId)`
- `quitMatch(matchId)`
- `loadSnapshot(matchId)`
- `subscribeToMatch(matchId)`

### Domain Types

- `Match`
- `Move`
- `BoardState`
- `Scoreboard`
- `GameSnapshot`

### Local Helpers

- `findDropRow(grid, column)`
- `findWinningLine(grid)`
- `winnerForGrid(grid)`
- `formatCountdown(duration)`
- `columnForOffset(x)`

### UI States

- waiting
- active/my-turn
- active/opponent-turn
- opponent-timed-out-claimable
- my-turn-expired
- finished-win
- finished-loss
- finished-draw
- finished-quit
- rematch-requested-by-me
- rematch-requested-by-opponent

## Recommended Improvements If You Are Not Strictly Mirroring Mobile

- Add `chat_id` to `grid_breach_matches`.
- Batch fetch invite match states instead of N+1 lookups.
- Make scoreboard realtime or compute it from match results server-side in one view.
- Accept from invite card directly if product wants fewer clicks.
- Resync server time periodically in long sessions.
- Consider incremental realtime patching instead of full snapshot refreshes.

## Files To Read While Building The Web Version

If you want to mirror the current behavior exactly, read these in this order:

1. [game_models.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/data/models/game_models.dart)
2. [game_utils.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/domain/game_utils.dart)
3. [game_repository.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/data/repositories/game_repository.dart)
4. [game_provider.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/presentation/providers/game_provider.dart)
5. [grid_breach_board_layout.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/presentation/widgets/grid_breach_board_layout.dart)
6. [game_screen.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/game/presentation/screens/game_screen.dart)
7. [secure_chat_service.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/application/services/secure_chat_service.dart)
8. [message_provider.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/presentation/providers/message_provider.dart)
9. [message_bubble.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/presentation/widgets/message_bubble.dart)
10. [chat_screen.dart](/C:/Users/96IN/AndroidStudioProjects/cipherchat/lib/features/chat/presentation/screens/chat_screen.dart)
11. [20260404_create_grid_breach.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260404_create_grid_breach.sql)
12. [20260413_harden_grid_breach_move_integrity_and_server_clock.sql](/C:/Users/96IN/AndroidStudioProjects/cipherchat/supabase/migrations/20260413_harden_grid_breach_move_integrity_and_server_clock.sql)

## Final Takeaway

`GRID BREACH` is Connect Four with:

- direct-chat launch
- encrypted invite messages
- server-authoritative move validation
- server-authoritative timers
- pair-based persistent scoreboard
- realtime board sync
- rematch, quit, and timeout end states

If you rebuild it for web and keep the RPC contract, board coordinates, lifecycle rules, and invite/message behavior above, you will match the current mobile feature closely.
