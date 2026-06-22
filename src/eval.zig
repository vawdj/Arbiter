const std = @import("std");
const Board = @import("board.zig").Board;
const Color = @import("piece.zig").Color;
const PieceType = @import("piece.zig").PieceType;

// values in centipawns — pawn = 100 is the universal baseline
// everything else is relative to that
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

fn countMaterial(board: Board, color: Color) i32 {
    var total: i32 = 0;
    for (board.squares) |maybe_piece| {
        const piece = maybe_piece orelse continue;
        if (piece.color == color) {
            total += pieceValue(piece.kind);
        }
    }
    return total;
}

// returns a score relative to the side to move
// positive = good for the side to move
// negative = bad for the side to move
pub fn evaluate(board: Board) i32 {
    const white = countMaterial(board, .white);
    const black = countMaterial(board, .black);
    const score = white - black;
    return if (board.side_to_move == .white) score else -score;
}

test "equal material evaluates to zero" {
    const fen_mod = @import("fen.zig");
    const board = try fen_mod.parse(fen_mod.start_position);
    try std.testing.expectEqual(@as(i32, 0), evaluate(board));
}

test "extra white pawn is positive for white" {
    const fen_mod = @import("fen.zig");
    // white has an extra pawn on e4
    const board = try fen_mod.parse("rnbqkbnr/pppppppp/8/8/4P3/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    try std.testing.expectEqual(@as(i32, PAWN_VALUE), evaluate(board));
}

test "extra black pawn is negative for white to move" {
    const fen_mod = @import("fen.zig");
    // black has an extra pawn, white to move
    const board = try fen_mod.parse("rnbqkbnr/pppppppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    try std.testing.expectEqual(@as(i32, -PAWN_VALUE), evaluate(board));
}

test "score flips sign based on side to move" {
    const fen_mod = @import("fen.zig");
    // same position, white vs black to move — scores should be negations of each other
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
