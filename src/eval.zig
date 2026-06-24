const std = @import("std");
const Board = @import("board.zig").Board;
const Square = @import("square.zig").Square;
const Color = @import("piece.zig").Color;
const PieceType = @import("piece.zig").PieceType;
const movegen = @import("movegen.zig");

pub const PAWN_VALUE: i32 = 100;
pub const KNIGHT_VALUE: i32 = 320;
pub const BISHOP_VALUE: i32 = 330;
pub const ROOK_VALUE: i32 = 500;
pub const QUEEN_VALUE: i32 = 900;
pub const KING_VALUE: i32 = 20000;

fn pieceValue(kind: PieceType) i32 {
    return switch (kind) {
        .pawn => PAWN_VALUE,
        .knight => KNIGHT_VALUE,
        .bishop => BISHOP_VALUE,
        .rook => ROOK_VALUE,
        .queen => QUEEN_VALUE,
        .king => KING_VALUE,
    };
}

// All PSTs are written from white's perspective with index 0 = a1.
// index = rank * 8 + file, rank 0 = rank 1 (white's back rank).
// For black pieces, mirror the rank: index = (7 - rank) * 8 + file.

// Knights want the center, hate the edges and corners.
const knight_pst = [64]i32{
    // rank 1
    -50, -40, -30, -30, -30, -30, -40, -50,
    // rank 2
    -40, -20, 0,   5,   5,   0,   -20, -40,
    // rank 3
    -30, 5,   10,  15,  15,  10,  5,   -30,
    // rank 4
    -30, 0,   15,  20,  20,  15,  0,   -30,
    // rank 5
    -30, 5,   15,  20,  20,  15,  5,   -30,
    // rank 6
    -30, 0,   10,  15,  15,  10,  0,   -30,
    // rank 7
    -40, -20, 0,   5,   5,   0,   -20, -40,
    // rank 8
    -50, -40, -30, -30, -30, -30, -40, -50,
};

// Pawns: reward advancement and central control, slight penalty for edge pawns.
const pawn_pst = [64]i32{
    // rank 1 — pawns can't be here
    0,  0,  0,   0,   0,   0,   0,  0,
    // rank 2 — starting rank, small structural bonuses
    5,  10, 10,  -20, -20, 10,  10, 5,
    // rank 3
    5,  -5, -10, 0,   0,   -10, -5, 5,
    // rank 4
    0,  0,  0,   20,  20,  0,   0,  0,
    // rank 5
    5,  5,  10,  25,  25,  10,  5,  5,
    // rank 6
    10, 10, 20,  30,  30,  20,  10, 10,
    // rank 7 — one step from promotion
    50, 50, 50,  50,  50,  50,  50, 50,
    // rank 8 — can't be here (already promoted)
    0,  0,  0,   0,   0,   0,   0,  0,
};

// King middlegame: strongly reward castled squares (g1=30, c1=10),
// penalize centralisation which is dangerous in the middlegame.
const king_pst = [64]i32{
    // rank 1
    20,  30,  10,  0,   0,   10,  30,  20,
    // rank 2 — pawn shelter nearby
    20,  20,  0,   0,   0,   0,   20,  20,
    // rank 3
    -10, -20, -20, -20, -20, -20, -20, -10,
    // rank 4
    -20, -30, -30, -40, -40, -30, -30, -20,
    // rank 5
    -30, -40, -40, -50, -50, -40, -40, -30,
    // rank 6
    -30, -40, -40, -50, -50, -40, -40, -30,
    // rank 7
    -30, -40, -40, -50, -50, -40, -40, -30,
    // rank 8
    -30, -40, -40, -50, -50, -40, -40, -30,
};

// Returns the PST index for a piece of the given color on sq.
// White uses the raw index; black mirrors the rank.
fn pstIndex(sq: Square, color: Color) usize {
    const r: usize = if (color == .white) sq.rank() else 7 - @as(usize, sq.rank());
    return r * 8 + sq.file();
}

fn pieceSquareBonus(kind: PieceType, sq: Square, color: Color) i32 {
    const idx = pstIndex(sq, color);
    return switch (kind) {
        .knight => knight_pst[idx],
        .pawn => pawn_pst[idx],
        .king => king_pst[idx],
        else => 0,
    };
}

fn evaluateSide(board: Board, color: Color) i32 {
    var score: i32 = 0;

    for (board.squares, 0..) |maybe_piece, i| {
        const piece = maybe_piece orelse continue;
        if (piece.color != color) continue;
        const sq: Square = @enumFromInt(i);
        score += pieceValue(piece.kind);
        score += pieceSquareBonus(piece.kind, sq, color);
    }

    return score;
}

// Mobility: count pseudo-legal moves available to each side.
// Uses pseudo-legal (not full legal) movegen to keep eval fast.
// Each available move is worth a small bonus.
const MOBILITY_BONUS: i32 = 4;

fn mobilityScore(board: Board, color: Color) i32 {
    var b = board;
    b.side_to_move = color;
    const moves = movegen.generatePseudoLegalMoves(b);
    return @as(i32, @intCast(moves.count)) * MOBILITY_BONUS;
}

// Returns a score relative to the side to move.
// Positive = good for the side to move, negative = bad.
pub fn evaluate(board: Board) i32 {
    const white = evaluateSide(board, .white) + mobilityScore(board, .white);
    const black = evaluateSide(board, .black) + mobilityScore(board, .black);
    const score = white - black;
    return if (board.side_to_move == .white) score else -score;
}

test "equal material evaluates to zero" {
    const fen_mod = @import("fen.zig");
    const board = try fen_mod.parse(fen_mod.start_position);
    // PSTs are symmetric and mobility is equal, so the starting position is 0
    try std.testing.expectEqual(@as(i32, 0), evaluate(board));
}

test "extra white pawn is positive for white" {
    const fen_mod = @import("fen.zig");
    const board = try fen_mod.parse("rnbqkbnr/pppppppp/8/8/4P3/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    // With PST bonuses the exact value varies, but it must be positive
    try std.testing.expect(evaluate(board) > 0);
}

test "extra black pawn is negative for white to move" {
    const fen_mod = @import("fen.zig");
    const board = try fen_mod.parse("rnbqkbnr/pppppppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    try std.testing.expect(evaluate(board) < 0);
}

test "score flips sign based on side to move" {
    const fen_mod = @import("fen.zig");
    const white_to_move = try fen_mod.parse("rnbqkbnr/pppppppp/8/8/4P3/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    const black_to_move = try fen_mod.parse("rnbqkbnr/pppppppp/8/8/4P3/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1");
    try std.testing.expectEqual(evaluate(white_to_move), -evaluate(black_to_move));
}

test "piece values are ordered correctly" {
    try std.testing.expect(PAWN_VALUE < KNIGHT_VALUE);
    try std.testing.expect(KNIGHT_VALUE < BISHOP_VALUE);
    try std.testing.expect(BISHOP_VALUE < ROOK_VALUE);
    try std.testing.expect(ROOK_VALUE < QUEEN_VALUE);
    try std.testing.expect(QUEEN_VALUE < KING_VALUE);
}

test "knight in center scores higher than knight on edge" {
    const fen_mod = @import("fen.zig");
    const center = try fen_mod.parse("8/8/8/8/3N4/8/8/k6K w - - 0 1");
    const edge = try fen_mod.parse("8/8/8/8/N7/8/8/k6K w - - 0 1");
    try std.testing.expect(evaluate(center) > evaluate(edge));
}

test "advanced pawn scores higher than starting pawn" {
    const fen_mod = @import("fen.zig");
    const advanced = try fen_mod.parse("8/8/4P3/8/8/8/8/k6K w - - 0 1");
    const starting = try fen_mod.parse("8/8/8/8/8/8/4P3/k6K w - - 0 1");
    try std.testing.expect(evaluate(advanced) > evaluate(starting));
}

test "castled king scores higher than centralised king" {
    const fen_mod = @import("fen.zig");
    const castled = try fen_mod.parse("8/8/8/8/8/8/8/5K1k w - - 0 1"); // g1
    const central = try fen_mod.parse("8/8/8/8/8/8/8/3K3k w - - 0 1"); // d1
    try std.testing.expect(evaluate(castled) > evaluate(central));
}
