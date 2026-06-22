const std = @import("std");
const Board = @import("board.zig").Board;
const Move = @import("move.zig").Move;
const movegen = @import("movegen.zig");

pub fn perft(board: *Board, depth: u32) u64 {
    if (depth == 0) return 1;

    var nodes: u64 = 0;
    var moves = movegen.generateLegalMoves(board);

    for (moves.slice()) |move| {
        const undo = board.makeMove(move);
        nodes += perft(board, depth - 1);
        board.unmakeMove(move, undo);
    }

    return nodes;
}

// divide breaks down the node count by each root move —
// essential for isolating which move has wrong node counts
// when your total doesnt match the expected value
pub fn perftDivide(board: *Board, depth: u32, writer: anytype) !void {
    var total: u64 = 0;
    var moves = movegen.generateLegalMoves(board);

    for (moves.slice()) |move| {
        const undo = board.makeMove(move);
        const nodes = perft(board, depth - 1);
        board.unmakeMove(move, undo);

        total += nodes;

        // print move in algebraic notation then node count
        const from = move.from.toString();
        const to = move.to.toString();
        try writer.print("{s}{s}: {d}\n", .{ from, to, nodes });
    }

    try writer.print("\nTotal: {d}\n", .{total});
}

test "perft start position depth 1" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse(fen_mod.start_position);
    try std.testing.expectEqual(@as(u64, 20), perft(&board, 1));
}

test "perft start position depth 2" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse(fen_mod.start_position);
    try std.testing.expectEqual(@as(u64, 400), perft(&board, 2));
}

test "perft start position depth 3" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse(fen_mod.start_position);
    try std.testing.expectEqual(@as(u64, 8902), perft(&board, 3));
}

test "perft start position depth 4" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse(fen_mod.start_position);
    try std.testing.expectEqual(@as(u64, 197281), perft(&board, 4));
}

// kiwipete — the standard stress test position, designed specifically
// to exercise every edge case: castling, en passant, promotions,
// pins, double check. if depth 1-3 pass from the start position
// but kiwipete fails, the bug is almost certainly in one of those
// edge cases rather than basic piece movement
test "perft kiwipete depth 1" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    try std.testing.expectEqual(@as(u64, 48), perft(&board, 1));
}

test "perft kiwipete depth 2" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    try std.testing.expectEqual(@as(u64, 2039), perft(&board, 2));
}

test "perft kiwipete depth 3" {
    const fen_mod = @import("fen.zig");
    var board = try fen_mod.parse("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    try std.testing.expectEqual(@as(u64, 97862), perft(&board, 3));
}
