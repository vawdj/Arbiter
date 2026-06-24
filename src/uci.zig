const std = @import("std");
const chess = @import("Arbiter");

const GoParams = struct {
    wtime: ?i64 = null,
    btime: ?i64 = null,
    winc: i64 = 0,
    binc: i64 = 0,
    movestogo: ?u32 = null,
    movetime: ?i64 = null,
    depth: ?u32 = null,
    infinite: bool = false,
};

pub fn run(stdin: anytype, stdout: anytype) !void {
    var board = chess.fen.parse(chess.fen.start_position) catch unreachable;

    try stdout.writeAll("id name Arbiter\n");
    try stdout.writeAll("id author Jayden_Vawdrey\n");
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
        } else if (std.mem.startsWith(u8, cmd, "position")) {
            board = parsePosition(cmd) catch continue;
        } else if (std.mem.startsWith(u8, cmd, "go")) {
            const params = parseGo(cmd);

            var state = if (shouldUseTimer(params)) blk: {
                const budget = calculateMoveTime(params, board.side_to_move);
                break :blk chess.search.SearchState.initTimed(@intCast(@max(1, budget)));
            } else chess.search.SearchState.init();

            const max_depth = params.depth orelse 100;

            // CHANGED: record the clock before search and pass stdout so
            // searchWithWriter can flush one info line per depth in real time.
            // The old manual `info depth … score cp …` print is now gone;
            // searchWithWriter handles it with nodes/time/nps/pv included.
            const result = chess.search.searchWithWriter(&board, max_depth, &state, stdout);

            if (result.move) |m| {
                const from = m.from.toString();
                const to = m.to.toString();
                try stdout.print("bestmove {s}{s}{s}\n", .{
                    from,
                    to,
                    promotionSuffix(m),
                });
            } else {
                try stdout.writeAll("bestmove 0000\n");
            }
            try stdout.flush();
        } else if (std.mem.eql(u8, cmd, "quit")) {
            break;
        }
    }
}

// ── helpers (all unchanged) ──────────────────────────────────────────────────

fn parsePosition(cmd: []const u8) !chess.Board {
    if (cmd.len < 9) return error.InvalidPosition;
    var rest = cmd[9..];
    var board: chess.Board = undefined;

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

    const trimmed_rest = std.mem.trim(u8, rest, " ");
    if (std.mem.startsWith(u8, trimmed_rest, "moves")) {
        var it = std.mem.splitScalar(u8, trimmed_rest, ' ');
        _ = it.next();
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

fn parseGo(cmd: []const u8) GoParams {
    var params = GoParams{};
    var it = std.mem.splitScalar(u8, cmd, ' ');
    _ = it.next();

    while (it.next()) |token| {
        if (std.mem.eql(u8, token, "wtime")) {
            if (it.next()) |v| params.wtime = std.fmt.parseInt(i64, v, 10) catch null;
        } else if (std.mem.eql(u8, token, "btime")) {
            if (it.next()) |v| params.btime = std.fmt.parseInt(i64, v, 10) catch null;
        } else if (std.mem.eql(u8, token, "winc")) {
            if (it.next()) |v| params.winc = std.fmt.parseInt(i64, v, 10) catch 0;
        } else if (std.mem.eql(u8, token, "binc")) {
            if (it.next()) |v| params.binc = std.fmt.parseInt(i64, v, 10) catch 0;
        } else if (std.mem.eql(u8, token, "movestogo")) {
            if (it.next()) |v| params.movestogo = std.fmt.parseInt(u32, v, 10) catch null;
        } else if (std.mem.eql(u8, token, "movetime")) {
            if (it.next()) |v| params.movetime = std.fmt.parseInt(i64, v, 10) catch null;
        } else if (std.mem.eql(u8, token, "depth")) {
            if (it.next()) |v| params.depth = std.fmt.parseInt(u32, v, 10) catch null;
        } else if (std.mem.eql(u8, token, "infinite")) {
            params.infinite = true;
        }
    }

    return params;
}

fn shouldUseTimer(params: GoParams) bool {
    if (params.infinite) return false;
    if (params.depth != null) return false;
    return params.movetime != null or params.wtime != null or params.btime != null;
}

fn calculateMoveTime(params: GoParams, color: chess.Color) i64 {
    if (params.movetime) |mt| return mt;

    const my_time = if (color == .white) params.wtime orelse return 1000 else params.btime orelse return 1000;
    const my_inc = if (color == .white) params.winc else params.binc;

    if (params.movestogo) |mtg| {
        const moves_left: i64 = @max(1, @as(i64, @intCast(mtg)));
        return @divTrunc(my_time, moves_left) + @divTrunc(my_inc, 2);
    }

    const budget = @divTrunc(my_time, 30) + @divTrunc(my_inc, 2);
    const capped = @min(budget, @divTrunc(my_time, 2));
    return @max(1, capped - 50);
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
