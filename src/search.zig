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
};

pub fn negamax(board: *Board, depth: u32, alpha_init: i32, beta: i32) i32 {
    var alpha = alpha_init;

    if (depth == 0) {
        return eval.evaluate(board.*);
    }

    var moves = movegen.generateLegalMoves(board);

    // no legal moves — checkmate or stalemate
    if (moves.count == 0) {
        if (movegen.isInCheck(board.*, board.side_to_move)) {
            // checkmate — subtract depth so engine prefers faster mates
            return -(CHECKMATE_SCORE - @as(i32, @intCast(depth)));
        } else {
            return DRAW_SCORE;
        }
    }

    for (moves.slice()) |move| {
        const undo = board.makeMove(move);
        const score = -negamax(board, depth - 1, -beta, -alpha);
        board.unmakeMove(move, undo);

        if (score >= beta) {
            return beta; // beta cutoff
        }
        if (score > alpha) {
            alpha = score;
        }
    }

    return alpha;
}

// returns the best move and its score from the current position
pub fn search(board: *Board, depth: u32) SearchResult {
    var best_move: ?Move = null;
    var best_score: i32 = -CHECKMATE_SCORE - 1;
    var alpha: i32 = -CHECKMATE_SCORE - 1;
    const beta: i32 = CHECKMATE_SCORE + 1;

    var moves = movegen.generateLegalMoves(board);

    for (moves.slice()) |move| {
        const undo = board.makeMove(move);
        const score = -negamax(board, depth - 1, -beta, -alpha);
        board.unmakeMove(move, undo);

        if (score > best_score) {
            best_score = score;
            best_move = move;
            if (score > alpha) {
                alpha = score;
            }
        }
    }

    return SearchResult{ .move = best_move, .score = best_score };
}

test "search finds only legal move" {
    const fen_mod = @import("fen.zig");
    // white rook on a1, king on e1 — only one legal move available
    var board = try fen_mod.parse("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1");
    const result = search(&board, 3);
    try std.testing.expect(result.move != null);
}

test "search finds checkmate in one" {
    const fen_mod = @import("fen.zig");
    // white queen on h5, bishop on c4, black king on e8 — Qxf7 is mate
    var board = try fen_mod.parse("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 0 1");
    const result = search(&board, 2);
    try std.testing.expect(result.move != null);
    try std.testing.expect(result.score > CHECKMATE_SCORE - 100);
}

test "search returns draw score for stalemate" {
    const fen_mod = @import("fen.zig");
    // black to move, stalemated
    var board = try fen_mod.parse("k7/8/1QK5/8/8/8/8/8 b - - 0 1");
    const result = search(&board, 1);
    try std.testing.expectEqual(@as(?Move, null), result.move);
}

test "search prefers capturing a free piece" {
    const fen_mod = @import("fen.zig");
    // white rook on a5, black queen on a8 — same file, nothing between them,
    // queen is completely undefended
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
