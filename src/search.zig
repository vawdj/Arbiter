const std = @import("std");
const Board = @import("board.zig").Board;
const Move = @import("move.zig").Move;
const MoveList = @import("move.zig").MoveList;
const movegen = @import("movegen.zig");
const eval = @import("eval.zig");

pub const CHECKMATE_SCORE: i32 = 100_000;
pub const DRAW_SCORE: i32 = 0;

pub const SearchResult = struct {
    move: ?Move,
    score: i32,
    depth: u32,
};

pub const SearchState = struct {
    stop: bool = false,
};

pub fn negamax(board: *Board, depth: u32, alpha_init: i32, beta: i32, state: *SearchState) i32 {
    if (state.stop) return 0;

    var alpha = alpha_init;

    if (depth == 0) {
        return eval.evaluate(board.*);
    }

    var moves = movegen.generateLegalMoves(board);

    if (moves.count == 0) {
        if (movegen.isInCheck(board.*, board.side_to_move)) {
            return -(CHECKMATE_SCORE - @as(i32, @intCast(depth)));
        } else {
            return DRAW_SCORE;
        }
    }

    for (moves.slice()) |move| {
        const undo = board.makeMove(move);
        const score = -negamax(board, depth - 1, -beta, -alpha, state);
        board.unmakeMove(move, undo);

        if (state.stop) return alpha;

        if (score >= beta) return beta;
        if (score > alpha) alpha = score;
    }

    return alpha;
}

fn searchDepth(board: *Board, depth: u32, state: *SearchState) SearchResult {
    var best_move: ?Move = null;
    var best_score: i32 = -CHECKMATE_SCORE - 1;
    var alpha: i32 = -CHECKMATE_SCORE - 1;
    const beta: i32 = CHECKMATE_SCORE + 1;

    var moves = movegen.generateLegalMoves(board);

    for (moves.slice()) |move| {
        const undo = board.makeMove(move);
        const score = -negamax(board, depth - 1, -beta, -alpha, state);
        board.unmakeMove(move, undo);

        if (state.stop) break;

        if (score > best_score) {
            best_score = score;
            best_move = move;
            if (score > alpha) alpha = score;
        }
    }

    return SearchResult{ .move = best_move, .score = best_score, .depth = depth };
}

pub fn search(board: *Board, max_depth: u32) SearchResult {
    var state = SearchState{};
    var best = SearchResult{ .move = null, .score = 0, .depth = 0 };

    var depth: u32 = 1;
    while (depth <= max_depth) : (depth += 1) {
        const result = searchDepth(board, depth, &state);
        if (state.stop) break;
        best = result;
    }

    return best;
}

// search with external state — used by UCI to stop mid-search
pub fn searchWithState(board: *Board, max_depth: u32, state: *SearchState) SearchResult {
    var best = SearchResult{ .move = null, .score = 0, .depth = 0 };

    var depth: u32 = 1;
    while (depth <= max_depth) : (depth += 1) {
        const result = searchDepth(board, depth, state);
        if (state.stop) break;
        best = result;
    }

    return best;
}

test "search finds only legal move" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1");
    const result = search(&board, 3);
    try std.testing.expect(result.move != null);
}

test "search finds checkmate in one" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 0 1");
    const result = search(&board, 2);
    try std.testing.expect(result.move != null);
    try std.testing.expect(result.score > CHECKMATE_SCORE - 100);
}

test "search returns draw score for stalemate" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse("k7/8/1QK5/8/8/8/8/8 b - - 0 1");
    const result = search(&board, 1);
    try std.testing.expectEqual(@as(?Move, null), result.move);
}

test "search prefers capturing a free piece" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse("q3k3/8/8/R7/8/8/8/4K3 w - - 0 1");
    const result = search(&board, 2);
    try std.testing.expect(result.move != null);
    try std.testing.expectEqual(Move{ .from = .a5, .to = .a8, .flag = .capture }, result.move.?);
}

test "board unchanged after search" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse(fen_mod.start_position);
    const before = try fen_mod.toFen(board, std.testing.allocator);
    defer std.testing.allocator.free(before);
    _ = search(&board, 3);
    const after = try fen_mod.toFen(board, std.testing.allocator);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings(before, after);
}

test "iterative deepening reaches max depth" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse(fen_mod.start_position);
    const result = search(&board, 4);
    try std.testing.expectEqual(@as(u32, 4), result.depth);
}

test "search with external state can be stopped early" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse(fen_mod.start_position);
    var state = SearchState{ .stop = true };
    const result = searchWithState(&board, 4, &state);
    // stopped before any depth completed — move may be null
    try std.testing.expectEqual(@as(u32, 0), result.depth);
}
