const std = @import("std");
const chess = @import("Arbiter");

// first_line is the first line already read by main.zig
// before it knew which mode to enter — we process it before
// blocking for the next line so no input is lost
pub fn run(first_line: []const u8, stdin: anytype, stdout: anytype) !void {
    var board = chess.fen.parse(chess.fen.start_position) catch unreachable;

    try stdout.writeAll("Zig Chess\n");
    try stdout.writeAll("enter moves in format: e2e4, or 'quit' to exit\n\n");
    try stdout.flush();

    // the first line was already read in main — process it before looping
    var pending: ?[]const u8 = first_line;

    while (true) {
        try chess.Board.print(board, stdout);
        try stdout.writeAll("\n");

        const legal = chess.movegen.generateLegalMoves(&board);

        if (legal.count == 0) {
            if (chess.movegen.isInCheck(board, board.side_to_move)) {
                const winner = if (board.side_to_move == .white) "black" else "white";
                try stdout.print("checkmate — {s} wins\n", .{winner});
            } else {
                try stdout.writeAll("stalemate — draw\n");
            }
            try stdout.flush();
            break;
        }

        const side = if (board.side_to_move == .white) "white" else "black";
        try stdout.print("{s} to move: ", .{side});
        try stdout.flush();

        // use the pending line if we have one, otherwise read a new one
        const raw: []const u8 = if (pending) |p| blk: {
            pending = null;
            break :blk p;
        } else blk: {
            break :blk try stdin.takeDelimiter('\n') orelse break;
        };

        const trimmed = std.mem.trim(u8, raw, " \r\t");

        if (std.mem.eql(u8, trimmed, "quit")) break;

        const move = parseMove(trimmed, legal) orelse {
            try stdout.writeAll("invalid move, try again\n\n");
            try stdout.flush();
            continue;
        };

        _ = board.makeMove(move);

        // check game over after player move
        const response_moves = chess.movegen.generateLegalMoves(&board);
        if (response_moves.count == 0) {
            try chess.Board.print(board, stdout);
            if (chess.movegen.isInCheck(board, board.side_to_move)) {
                const winner = if (board.side_to_move == .white) "black" else "white";
                try stdout.print("\ncheckmate — {s} wins\n", .{winner});
            } else {
                try stdout.writeAll("\nstalemate — draw\n");
            }
            try stdout.flush();
            break;
        }

        try stdout.writeAll("engine thinking...\n");
        try stdout.flush();

        const result = chess.search.search(&board, 4);
        if (result.move) |engine_move| {
            const from = engine_move.from.toString();
            const to = engine_move.to.toString();
            try stdout.print("engine plays: {s}{s}\n\n", .{ from, to });
            try stdout.flush();
            _ = board.makeMove(engine_move);
        }
    }
}

fn parseMove(s: []const u8, legal: chess.MoveList) ?chess.Move {
    if (s.len < 4 or s.len > 5) return null;

    const from = chess.Square.fromString(s[0..2]) orelse return null;
    const to = chess.Square.fromString(s[2..4]) orelse return null;

    const promo: ?chess.PieceType = if (s.len == 5) switch (s[4]) {
        'q' => .queen,
        'r' => .rook,
        'b' => .bishop,
        'n' => .knight,
        else => return null,
    } else null;

    for (legal.slice()) |m| {
        if (m.from != from or m.to != to) continue;
        if (promo) |p| {
            const matches = switch (p) {
                .queen => m.flag == .promo_queen or m.flag == .promo_queen_capture,
                .rook => m.flag == .promo_rook or m.flag == .promo_rook_capture,
                .bishop => m.flag == .promo_bishop or m.flag == .promo_bishop_capture,
                .knight => m.flag == .promo_knight or m.flag == .promo_knight_capture,
                else => false,
            };
            if (matches) return m;
        } else {
            if (m.flag.isPromotion()) continue;
            return m;
        }
    }
    return null;
}
