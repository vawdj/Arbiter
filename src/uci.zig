const std = @import("std");
const chess = @import("Arbiter");

pub fn run(stdin: anytype, stdout: anytype) !void {
    var board = chess.fen.parse(chess.fen.start_position) catch unreachable;
    var state = chess.search.SearchState{};

    try stdout.writeAll("id name Arbiter\n");
    try stdout.writeAll("id author YourName\n");
    try stdout.writeAll("uciok\n");
    try stdout.flush();

    while (true) {
        const line = try stdin.takeDelimiter('\n') orelse break;
        const cmd = std.mem.trim(u8, line, " \r\t");
        if (cmd.len == 0) continue;

        if (std.mem.eql(u8, cmd, "isready")) {
            try stdout.writeAll("readyok\n");
            try stdout.flush();
        } else if (std.mem.eql(u8, cmd, "ucinewgame")) {
            board = chess.fen.parse(chess.fen.start_position) catch unreachable;
            state = chess.search.SearchState{};
        } else if (std.mem.startsWith(u8, cmd, "position")) {
            board = parsePosition(cmd) catch continue;
        } else if (std.mem.startsWith(u8, cmd, "go")) {
            state = chess.search.SearchState{};
            const max_depth = parseGo(cmd);
            const result = chess.search.searchWithState(&board, max_depth, &state);

            if (result.move) |m| {
                const from = m.from.toString();
                const to = m.to.toString();
                try stdout.print("info depth {d} score cp {d}\n", .{
                    result.depth,
                    result.score,
                });
                try stdout.print("bestmove {s}{s}{s}\n", .{
                    from,
                    to,
                    promotionSuffix(m),
                });
            } else {
                try stdout.writeAll("bestmove 0000\n");
            }
            try stdout.flush();
        } else if (std.mem.eql(u8, cmd, "stop")) {
            state.stop = true;
        } else if (std.mem.eql(u8, cmd, "quit")) {
            break;
        }
    }
}

fn parsePosition(cmd: []const u8) !chess.Board {
    // cmd is "position startpos" or "position startpos moves e2e4 ..."
    // or "position fen <fenstring>" or "position fen <fenstring> moves ..."
    var board: chess.Board = undefined;

    // skip "position "
    if (cmd.len < 9) return error.InvalidPosition;
    var rest = cmd[9..];

    if (std.mem.startsWith(u8, rest, "startpos")) {
        board = chess.fen.parse(chess.fen.start_position) catch unreachable;
        rest = rest[@min(rest.len, 8)..];
    } else if (std.mem.startsWith(u8, rest, "fen ")) {
        rest = rest[4..];
        const moves_idx = std.mem.indexOf(u8, rest, " moves");
        const fen_str = if (moves_idx) |i| rest[0..i] else rest;
        board = try chess.fen.parse(fen_str);
        rest = if (moves_idx) |i| rest[i..] else rest[rest.len..];
    } else {
        return error.InvalidPosition;
    }

    // apply move list if present
    const trimmed_rest = std.mem.trim(u8, rest, " ");
    if (std.mem.startsWith(u8, trimmed_rest, "moves")) {
        var it = std.mem.splitScalar(u8, trimmed_rest, ' ');
        _ = it.next(); // skip "moves"
        while (it.next()) |move_str| {
            const m = parseMoveStr(move_str, &board) orelse continue;
            _ = board.makeMove(m);
        }
    }

    return board;
}

fn parseMoveStr(s: []const u8, board: *chess.Board) ?chess.Move {
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

    const legal = chess.movegen.generateLegalMoves(board);
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

fn parseGo(cmd: []const u8) u32 {
    if (std.mem.indexOf(u8, cmd, "depth ")) |i| {
        const rest = std.mem.trim(u8, cmd[i + 6 ..], " ");
        var it = std.mem.splitScalar(u8, rest, ' ');
        if (it.next()) |n| {
            return std.fmt.parseInt(u32, n, 10) catch 6;
        }
    }
    // movetime/wtime/btime — fixed depth for now, replace with timer later
    return 6;
}

fn promotionSuffix(m: chess.Move) []const u8 {
    return switch (m.flag) {
        .promo_queen, .promo_queen_capture => "q",
        .promo_rook, .promo_rook_capture => "r",
        .promo_bishop, .promo_bishop_capture => "b",
        .promo_knight, .promo_knight_capture => "n",
        else => "",
    };
}
