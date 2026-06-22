const std = @import("std");
const Board = @import("board.zig").Board;
const Square = @import("square.zig").Square;
const Piece = @import("piece.zig").Piece;
const Color = @import("piece.zig").Color;
const MoveList = @import("move.zig").MoveList;
const Move = @import("move.zig").Move;
// all offsets as {file_delta, rank_delta}
const knight_offsets = [8][2]i8{
    .{ -2, -1 }, .{ -2, 1 }, .{ -1, -2 }, .{ -1, 2 },
    .{ 1, -2 },  .{ 1, 2 },  .{ 2, -1 },  .{ 2, 1 },
};

const king_offsets = [8][2]i8{
    .{ -1, -1 }, .{ -1, 0 }, .{ -1, 1 }, .{ 0, -1 },
    .{ 0, 1 },   .{ 1, -1 }, .{ 1, 0 },  .{ 1, 1 },
};

const bishop_dirs = [4][2]i8{
    .{ -1, -1 }, .{ -1, 1 }, .{ 1, -1 }, .{ 1, 1 },
};

const rook_dirs = [4][2]i8{
    .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 },
};

pub fn isSquareAttacked(board: Board, sq: Square, by: Color) bool {
    const file = @as(i8, sq.file());
    const rank = @as(i8, sq.rank());

    // knights
    for (knight_offsets) |off| {
        const f = file + off[0];
        const r = rank + off[1];
        if (f < 0 or f > 7 or r < 0 or r > 7) continue;
        const s = Square.fromFileRank(@intCast(f), @intCast(r));
        if (board.pieceAt(s)) |p| {
            if (p.color == by and p.kind == .knight) return true;
        }
    }

    // king
    for (king_offsets) |off| {
        const f = file + off[0];
        const r = rank + off[1];
        if (f < 0 or f > 7 or r < 0 or r > 7) continue;
        const s = Square.fromFileRank(@intCast(f), @intCast(r));
        if (board.pieceAt(s)) |p| {
            if (p.color == by and p.kind == .king) return true;
        }
    }

    // pawns — check backwards from sq using the attacker's pawn direction
    // if `by` is white, white pawns attack upward, so they would attack
    // sq from one rank below and one file either side
    const pawn_rank_dir: i8 = if (by == .white) -1 else 1;
    for ([2]i8{ -1, 1 }) |file_off| {
        const f = file + file_off;
        const r = rank + pawn_rank_dir;
        if (f < 0 or f > 7 or r < 0 or r > 7) continue;
        const s = Square.fromFileRank(@intCast(f), @intCast(r));
        if (board.pieceAt(s)) |p| {
            if (p.color == by and p.kind == .pawn) return true;
        }
    }

    // sliding pieces — bishops and queens on diagonals
    for (bishop_dirs) |dir| {
        var f = file + dir[0];
        var r = rank + dir[1];
        while (f >= 0 and f <= 7 and r >= 0 and r <= 7) {
            const s = Square.fromFileRank(@intCast(f), @intCast(r));
            if (board.pieceAt(s)) |p| {
                if (p.color == by and (p.kind == .bishop or p.kind == .queen)) return true;
                break; // blocked by any piece regardless of color
            }
            f += dir[0];
            r += dir[1];
        }
    }

    // sliding pieces — rooks and queens on ranks and files
    for (rook_dirs) |dir| {
        var f = file + dir[0];
        var r = rank + dir[1];
        while (f >= 0 and f <= 7 and r >= 0 and r <= 7) {
            const s = Square.fromFileRank(@intCast(f), @intCast(r));
            if (board.pieceAt(s)) |p| {
                if (p.color == by and (p.kind == .rook or p.kind == .queen)) return true;
                break; // blocked by any piece regardless of color
            }
            f += dir[0];
            r += dir[1];
        }
    }

    return false;
}

pub fn isInCheck(board: Board, color: Color) bool {
    const king_sq = board.findKing(color);
    return isSquareAttacked(board, king_sq, color.opponent());
}

fn generateCastlingMoves(board: Board, list: *MoveList) void {
    const color = board.side_to_move;

    // can't castle while in check
    if (isInCheck(board, color)) return;

    switch (color) {
        .white => {
            // kingside — squares f1 and g1 must be empty
            // king must not pass through f1 or land on g1 while attacked
            if (board.castling.white_kingside) {
                if (board.pieceAt(.f1) == null and
                    board.pieceAt(.g1) == null and
                    !isSquareAttacked(board, .f1, .black) and
                    !isSquareAttacked(board, .g1, .black))
                {
                    list.append(Move{ .from = .e1, .to = .g1, .flag = .castle_kingside });
                }
            }

            // queenside — squares b1, c1, d1 must be empty
            // king passes through d1 and lands on c1 — both must be safe
            // b1 must be empty but the king doesn't pass through it so
            // it doesn't need to be checked for attacks
            if (board.castling.white_queenside) {
                if (board.pieceAt(.b1) == null and
                    board.pieceAt(.c1) == null and
                    board.pieceAt(.d1) == null and
                    !isSquareAttacked(board, .d1, .black) and
                    !isSquareAttacked(board, .c1, .black))
                {
                    list.append(Move{ .from = .e1, .to = .c1, .flag = .castle_queenside });
                }
            }
        },

        .black => {
            if (board.castling.black_kingside) {
                if (board.pieceAt(.f8) == null and
                    board.pieceAt(.g8) == null and
                    !isSquareAttacked(board, .f8, .white) and
                    !isSquareAttacked(board, .g8, .white))
                {
                    list.append(Move{ .from = .e8, .to = .g8, .flag = .castle_kingside });
                }
            }

            if (board.castling.black_queenside) {
                if (board.pieceAt(.b8) == null and
                    board.pieceAt(.c8) == null and
                    board.pieceAt(.d8) == null and
                    !isSquareAttacked(board, .d8, .white) and
                    !isSquareAttacked(board, .c8, .white))
                {
                    list.append(Move{ .from = .e8, .to = .c8, .flag = .castle_queenside });
                }
            }
        },
    }
}

fn generateKnightMoves(board: Board, sq: Square, list: *MoveList) void {
    const piece = board.pieceAt(sq) orelse return;
    if (piece.kind != .knight) return;

    const file = @as(i8, sq.file());
    const rank = @as(i8, sq.rank());

    for (knight_offsets) |off| {
        const f = file + off[0];
        const r = rank + off[1];
        if (f < 0 or f > 7 or r < 0 or r > 7) continue;

        const target = Square.fromFileRank(@intCast(f), @intCast(r));
        if (board.pieceAt(target)) |occupant| {
            // square occupied by friendly piece — skip
            if (occupant.color == piece.color) continue;
            // square occupied by enemy — capture
            list.append(Move{ .from = sq, .to = target, .flag = .capture });
        } else {
            // empty square — quiet move
            list.append(Move{ .from = sq, .to = target, .flag = .quiet });
        }
    }
}

fn generateKingMoves(board: Board, sq: Square, list: *MoveList) void {
    const piece = board.pieceAt(sq) orelse return;
    if (piece.kind != .king) return;

    const file = @as(i8, sq.file());
    const rank = @as(i8, sq.rank());

    for (king_offsets) |off| {
        const f = file + off[0];
        const r = rank + off[1];
        if (f < 0 or f > 7 or r < 0 or r > 7) continue;

        const target = Square.fromFileRank(@intCast(f), @intCast(r));
        if (board.pieceAt(target)) |occupant| {
            if (occupant.color == piece.color) continue;
            list.append(Move{ .from = sq, .to = target, .flag = .capture });
        } else {
            list.append(Move{ .from = sq, .to = target, .flag = .quiet });
        }
    }

    // castling moves are king moves — generate them here
    generateCastlingMoves(board, list);
}

fn generatePawnMoves(board: Board, sq: Square, list: *MoveList) void {
    const piece = board.pieceAt(sq) orelse return;
    if (piece.kind != .pawn) return;

    const file = @as(i8, sq.file());
    const rank = @as(i8, sq.rank());
    const color = piece.color;

    // white pawns move up the board (increasing rank)
    // black pawns move down (decreasing rank)
    const dir: i8 = if (color == .white) 1 else -1;
    const start_rank: i8 = if (color == .white) 1 else 6;
    const promo_rank: i8 = if (color == .white) 6 else 1;

    // single push
    const push_rank = rank + dir;
    if (push_rank >= 0 and push_rank <= 7) {
        const push_sq = Square.fromFileRank(@intCast(file), @intCast(push_rank));

        if (board.pieceAt(push_sq) == null) {
            if (rank == promo_rank) {
                // pawn is on the rank before promotion — generate all 4
                appendPromotions(sq, push_sq, false, list);
            } else {
                list.append(Move{ .from = sq, .to = push_sq, .flag = .quiet });

                // double push only possible from starting rank and only
                // if the single push square was also empty
                if (rank == start_rank) {
                    const double_rank = rank + dir * 2;
                    const double_sq = Square.fromFileRank(@intCast(file), @intCast(double_rank));
                    if (board.pieceAt(double_sq) == null) {
                        list.append(Move{ .from = sq, .to = double_sq, .flag = .double_pawn_push });
                    }
                }
            }
        }
    }

    // diagonal captures
    for ([2]i8{ -1, 1 }) |file_off| {
        const cap_file = file + file_off;
        const cap_rank = rank + dir;
        if (cap_file < 0 or cap_file > 7 or cap_rank < 0 or cap_rank > 7) continue;

        const cap_sq = Square.fromFileRank(@intCast(cap_file), @intCast(cap_rank));

        // normal capture
        if (board.pieceAt(cap_sq)) |occupant| {
            if (occupant.color != color) {
                if (rank == promo_rank) {
                    appendPromotions(sq, cap_sq, true, list);
                } else {
                    list.append(Move{ .from = sq, .to = cap_sq, .flag = .capture });
                }
            }
        }

        // en passant
        if (board.en_passant_target) |ep_sq| {
            if (cap_sq == ep_sq) {
                list.append(Move{ .from = sq, .to = cap_sq, .flag = .en_passant });
            }
        }
    }
}

// appends all 4 promotion variants for a given from/to pair
fn appendPromotions(from: Square, to: Square, is_capture: bool, list: *MoveList) void {
    if (is_capture) {
        list.append(Move{ .from = from, .to = to, .flag = .promo_knight_capture });
        list.append(Move{ .from = from, .to = to, .flag = .promo_bishop_capture });
        list.append(Move{ .from = from, .to = to, .flag = .promo_rook_capture });
        list.append(Move{ .from = from, .to = to, .flag = .promo_queen_capture });
    } else {
        list.append(Move{ .from = from, .to = to, .flag = .promo_knight });
        list.append(Move{ .from = from, .to = to, .flag = .promo_bishop });
        list.append(Move{ .from = from, .to = to, .flag = .promo_rook });
        list.append(Move{ .from = from, .to = to, .flag = .promo_queen });
    }
}

fn generateSlidingMoves(board: Board, sq: Square, list: *MoveList) void {
    const piece = board.pieceAt(sq) orelse return;

    // determine which direction sets apply
    const diagonal = piece.kind == .bishop or piece.kind == .queen;
    const orthogonal = piece.kind == .rook or piece.kind == .queen;

    if (!diagonal and !orthogonal) return;

    const file = @as(i8, sq.file());
    const rank = @as(i8, sq.rank());

    if (diagonal) {
        for (bishop_dirs) |dir| {
            var f = file + dir[0];
            var r = rank + dir[1];
            while (f >= 0 and f <= 7 and r >= 0 and r <= 7) {
                const target = Square.fromFileRank(@intCast(f), @intCast(r));
                if (board.pieceAt(target)) |occupant| {
                    if (occupant.color != piece.color) {
                        list.append(Move{ .from = sq, .to = target, .flag = .capture });
                    }
                    break; // blocked regardless of color
                } else {
                    list.append(Move{ .from = sq, .to = target, .flag = .quiet });
                }
                f += dir[0];
                r += dir[1];
            }
        }
    }

    if (orthogonal) {
        for (rook_dirs) |dir| {
            var f = file + dir[0];
            var r = rank + dir[1];
            while (f >= 0 and f <= 7 and r >= 0 and r <= 7) {
                const target = Square.fromFileRank(@intCast(f), @intCast(r));
                if (board.pieceAt(target)) |occupant| {
                    if (occupant.color != piece.color) {
                        list.append(Move{ .from = sq, .to = target, .flag = .capture });
                    }
                    break;
                } else {
                    list.append(Move{ .from = sq, .to = target, .flag = .quiet });
                }
                f += dir[0];
                r += dir[1];
            }
        }
    }
}

pub fn generatePseudoLegalMoves(board: Board) MoveList {
    var list = MoveList{};
    const color = board.side_to_move;

    for (board.squares, 0..) |maybe_piece, i| {
        const piece = maybe_piece orelse continue;
        if (piece.color != color) continue;

        const sq: Square = @enumFromInt(i);
        switch (piece.kind) {
            .knight => generateKnightMoves(board, sq, &list),
            .king => generateKingMoves(board, sq, &list),
            .pawn => generatePawnMoves(board, sq, &list),
            .bishop, .rook, .queen => generateSlidingMoves(board, sq, &list),
        }
    }

    return list;
}

pub fn generateLegalMoves(board: *Board) MoveList {
    var pseudo = generatePseudoLegalMoves(board.*);
    var legal = MoveList{};

    for (pseudo.slice()) |move| {
        const undo = board.makeMove(move);
        // after making the move, side_to_move has flipped —
        // so the side that just moved is now the opponent
        const moved_side = board.side_to_move.opponent();
        if (!isInCheck(board.*, moved_side)) {
            legal.append(move);
        }
        board.unmakeMove(move, undo);
    }

    return legal;
}

// --- attack ---

test "starting position king is not in check" {
    const fen = @import("fen.zig");
    const board = try fen.parse(fen.start_position);
    try std.testing.expect(!isInCheck(board, .white));
    try std.testing.expect(!isInCheck(board, .black));
}

test "rook attacks along rank" {
    const fen = @import("fen.zig");
    // white rook on a1, black king on h1, nothing between them
    const board = try fen.parse("8/8/8/8/8/8/8/R6k w - - 0 1");
    try std.testing.expect(isSquareAttacked(board, .h1, .white));
}

test "rook attack blocked by intervening piece" {
    const fen = @import("fen.zig");
    // white rook on a1, white pawn on d1, black king on h1
    const board = try fen.parse("8/8/8/8/8/8/8/R2P3k w - - 0 1");
    try std.testing.expect(!isSquareAttacked(board, .h1, .white));
}

test "knight attack" {
    const fen = @import("fen.zig");
    // white knight on e4 attacks d6
    const board = try fen.parse("8/8/8/8/4N3/8/8/k6K w - - 0 1");
    try std.testing.expect(isSquareAttacked(board, .d6, .white));
    try std.testing.expect(!isSquareAttacked(board, .e6, .white));
}

test "pawn attacks correct direction" {
    const fen = @import("fen.zig");
    // white pawn on e4 attacks d5 and f5, not d3 or f3
    const board = try fen.parse("8/8/8/8/4P3/8/8/k6K w - - 0 1");
    try std.testing.expect(isSquareAttacked(board, .d5, .white));
    try std.testing.expect(isSquareAttacked(board, .f5, .white));
    try std.testing.expect(!isSquareAttacked(board, .d3, .white));
    try std.testing.expect(!isSquareAttacked(board, .f3, .white));
}

test "queen attacks diagonally and along rank" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/4Q3/8/8/k6K w - - 0 1");
    try std.testing.expect(isSquareAttacked(board, .h7, .white));
    try std.testing.expect(isSquareAttacked(board, .a4, .white));
    try std.testing.expect(isSquareAttacked(board, .e8, .white));
}

// --- knight ---

test "knight on e4 has 8 moves on empty board" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/4N3/8/8/k6K w - - 0 1");
    var list = MoveList{};
    generateKnightMoves(board, .e4, &list);
    try std.testing.expectEqual(@as(usize, 8), list.count);
}

test "knight on a1 has 2 moves" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/8/8/8/Nk5K w - - 0 1");
    var list = MoveList{};
    generateKnightMoves(board, .a1, &list);
    try std.testing.expectEqual(@as(usize, 2), list.count);
}

test "knight cannot capture friendly piece" {
    const fen = @import("fen.zig");
    // white knight on e4, white pawn on every square it could reach
    const board = try fen.parse("8/8/3P1P2/2P3P1/4N3/2P3P1/3P1P2/k6K w - - 0 1");
    var list = MoveList{};
    generateKnightMoves(board, .e4, &list);
    try std.testing.expectEqual(@as(usize, 0), list.count);
}

test "knight captures are flagged correctly" {
    const fen = @import("fen.zig");
    // white knight on e4, black pawn on d6 — only one reachable enemy
    const board = try fen.parse("8/8/3p4/8/4N3/8/8/k6K w - - 0 1");
    var list = MoveList{};
    generateKnightMoves(board, .e4, &list);
    var captures: usize = 0;
    var quiets: usize = 0;
    for (list.slice()) |m| {
        if (m.flag == .capture) captures += 1;
        if (m.flag == .quiet) quiets += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), captures);
    try std.testing.expectEqual(@as(usize, 7), quiets);
}

// --- king ---

test "king on e4 has 8 moves on empty board" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/4K3/8/8/7k w - - 0 1");
    var list = MoveList{};
    generateKingMoves(board, .e4, &list);
    try std.testing.expectEqual(@as(usize, 8), list.count);
}

test "king on a1 has 3 moves" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/8/8/8/K6k w - - 0 1");
    var list = MoveList{};
    generateKingMoves(board, .a1, &list);
    try std.testing.expectEqual(@as(usize, 3), list.count);
}

test "king cannot capture friendly piece" {
    const fen = @import("fen.zig");
    // white king surrounded by white pawns on every adjacent square
    const board = try fen.parse("8/8/8/8/8/1PPP4/1PKP4/1PPP3k w - - 0 1");
    var list = MoveList{};
    generateKingMoves(board, .c2, &list);
    try std.testing.expectEqual(@as(usize, 0), list.count);
}

// --- pawn ---

test "white pawn on e2 has 2 moves" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/8/8/4P3/k6K w - - 0 1");
    var list = MoveList{};
    generatePawnMoves(board, .e2, &list);
    try std.testing.expectEqual(@as(usize, 2), list.count);
}

test "white pawn on e3 has 1 move" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/8/4P3/8/k6K w - - 0 1");
    var list = MoveList{};
    generatePawnMoves(board, .e3, &list);
    try std.testing.expectEqual(@as(usize, 1), list.count);
}

test "white pawn blocked by piece directly ahead" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/4p3/4P3/8/k6K w - - 0 1");
    var list = MoveList{};
    generatePawnMoves(board, .e3, &list);
    try std.testing.expectEqual(@as(usize, 0), list.count);
}

test "white pawn double push blocked if intermediate square occupied" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/8/4p3/4P3/k6K w - - 0 1");
    var list = MoveList{};
    generatePawnMoves(board, .e2, &list);
    try std.testing.expectEqual(@as(usize, 0), list.count);
}

test "white pawn captures diagonally" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/8/3p1p2/4P3/k6K w - - 0 1");
    var list = MoveList{};
    generatePawnMoves(board, .e2, &list);
    // single push, double push, two captures
    try std.testing.expectEqual(@as(usize, 4), list.count);
}

test "white pawn promotion generates 4 moves" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/4P3/8/8/8/8/8/k6K w - - 0 1");
    var list = MoveList{};
    generatePawnMoves(board, .e7, &list);
    try std.testing.expectEqual(@as(usize, 4), list.count);
}

test "white pawn promotion capture generates 4 moves" {
    const fen = @import("fen.zig");
    const board = try fen.parse("3r4/4P3/8/8/8/8/8/k6K w - - 0 1");
    var list = MoveList{};
    generatePawnMoves(board, .e7, &list);
    // 4 push promotions + 4 capture promotions
    try std.testing.expectEqual(@as(usize, 8), list.count);
}

test "en passant capture generated" {
    const fen = @import("fen.zig");
    // white pawn on e5, black pawn just double-pushed to d5, ep target d6
    const board = try fen.parse("8/8/8/3pP3/8/8/8/k6K w - d6 0 1");
    var list = MoveList{};
    generatePawnMoves(board, .e5, &list);
    var found_ep = false;
    for (list.slice()) |m| {
        if (m.flag == .en_passant) found_ep = true;
    }
    try std.testing.expect(found_ep);
}

// --- sliding ---

test "rook on e4 open board has 14 moves" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/4R3/8/8/k6K w - - 0 1");
    var list = MoveList{};
    generateSlidingMoves(board, .e4, &list);
    try std.testing.expectEqual(@as(usize, 14), list.count);
}

test "bishop on e4 open board has 13 moves" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/4B3/8/8/2k3K1 w - - 0 1");
    var list = MoveList{};
    generateSlidingMoves(board, .e4, &list);
    try std.testing.expectEqual(@as(usize, 13), list.count);
}

test "queen on e4 open board has 27 moves" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/8/8/4Q3/8/8/2k3K1 w - - 0 11");
    var list = MoveList{};
    generateSlidingMoves(board, .e4, &list);
    try std.testing.expectEqual(@as(usize, 27), list.count);
}

test "rook blocked by friendly piece" {
    const fen = @import("fen.zig");
    // white rook on e4, white pawn on e6 — rook can go e5 but not beyond
    const board = try fen.parse("8/8/4P3/8/4R3/8/8/k6K w - - 0 1");
    var list = MoveList{};
    generateSlidingMoves(board, .e4, &list);
    var found_e5 = false;
    var found_e6 = false;
    var found_e7 = false;
    for (list.slice()) |m| {
        if (m.to == .e5) found_e5 = true;
        if (m.to == .e6) found_e6 = true;
        if (m.to == .e7) found_e7 = true;
    }
    try std.testing.expect(found_e5);
    try std.testing.expect(!found_e6);
    try std.testing.expect(!found_e7);
}

test "rook can capture enemy piece but not go past it" {
    const fen = @import("fen.zig");
    const board = try fen.parse("8/8/4p3/8/4R3/8/8/k6K w - - 0 1");
    var list = MoveList{};
    generateSlidingMoves(board, .e4, &list);
    var found_e6 = false;
    var found_e7 = false;
    for (list.slice()) |m| {
        if (m.to == .e6) found_e6 = true;
        if (m.to == .e7) found_e7 = true;
    }
    try std.testing.expect(found_e6);
    try std.testing.expect(!found_e7);
}

test "starting position has 20 legal moves" {
    const fen = @import("fen.zig");
    var board = try fen.parse(fen.start_position);
    const moves = generateLegalMoves(&board);
    // 16 pawn moves (each pawn has 2) + 4 knight moves
    try std.testing.expectEqual(@as(usize, 20), moves.count);
}

test "legal moves filter out moves that leave king in check" {
    const fen = @import("fen.zig");
    // white king on e1, black rook on e8 giving check along e file
    // white has only one piece — must move king or block
    const board_fen = "4r3/8/8/8/8/8/8/4K3 w - - 0 1";
    var board = try fen.parse(board_fen);
    const moves = generateLegalMoves(&board);
    // king can move to d1, d2, f1, f2 — e2 is still on the e file so attacked
    for (moves.slice()) |m| {
        try std.testing.expect(m.from == .e1);
        try std.testing.expect(m.to != .e2);
    }
}

test "pinned piece cannot move" {
    const fen = @import("fen.zig");
    // white king on e1, white rook on e4 pinned by black rook on e8
    // the white rook can only move along the e file, not off it
    var board = try fen.parse("4r3/8/8/8/4R3/8/8/4K3 w - - 0 1");
    const moves = generateLegalMoves(&board);
    for (moves.slice()) |m| {
        if (m.from == .e4) {
            // pinned rook must stay on e file
            try std.testing.expectEqual(@as(u3, 4), m.to.file());
        }
    }
}

test "stalemate position has zero legal moves" {
    const fen = @import("fen.zig");
    // classic stalemate — black king on a8, white queen on b6, white king on c6
    var board = try fen.parse("k7/8/1QK5/8/8/8/8/8 b - - 0 1");
    const moves = generateLegalMoves(&board);
    try std.testing.expectEqual(@as(usize, 0), moves.count);
}

test "checkmate position has zero legal moves" {
    const fen = @import("fen.zig");
    // scholars mate
    var board = try fen.parse("r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4");
    const moves = generateLegalMoves(&board);
    try std.testing.expectEqual(@as(usize, 0), moves.count);
}

test "board is unchanged after generateLegalMoves" {
    const fen = @import("fen.zig");
    var board = try fen.parse(fen.start_position);
    const before = try fen.toFen(board, std.testing.allocator);
    defer std.testing.allocator.free(before);
    _ = generateLegalMoves(&board);
    const after = try fen.toFen(board, std.testing.allocator);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings(before, after);
}
