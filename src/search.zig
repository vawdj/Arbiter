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
    nodes: u64 = 0,
};

pub const SearchState = struct {
    stop: std.atomic.Value(bool),
    search_done: std.atomic.Value(bool),
    limit_ms: ?u64,
    nodes: std.atomic.Value(u64),

    pub fn init() SearchState {
        return .{
            .stop = std.atomic.Value(bool).init(false),
            .search_done = std.atomic.Value(bool).init(false),
            .limit_ms = null,
            .nodes = std.atomic.Value(u64).init(0),
        };
    }

    pub fn initTimed(limit_ms: u64) SearchState {
        return .{
            .stop = std.atomic.Value(bool).init(false),
            .search_done = std.atomic.Value(bool).init(false),
            .limit_ms = limit_ms,
            .nodes = std.atomic.Value(u64).init(0),
        };
    }
};

fn timerThread(state: *SearchState, io: std.Io) void {
    const limit_ms = state.limit_ms orelse return;
    const interval = std.Io.Duration.fromMilliseconds(10);
    var elapsed_ms: u64 = 0;
    while (elapsed_ms < limit_ms) {
        if (state.search_done.load(.acquire)) return;
        io.sleep(interval, .awake) catch return;
        elapsed_ms += 10;
    }
    state.stop.store(true, .release);
}

pub fn negamax(board: *Board, depth: u32, alpha_init: i32, beta: i32, state: *SearchState) i32 {
    if (state.stop.load(.acquire)) return 0;
    _ = state.nodes.fetchAdd(1, .monotonic);

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

        if (state.stop.load(.acquire)) return alpha;
        if (score >= beta) return beta;
        if (score > alpha) alpha = score;
    }

    return alpha;
}

pub fn searchDepth(board: *Board, depth: u32, state: *SearchState) SearchResult {
    var best_move: ?Move = null;
    var best_score: i32 = -CHECKMATE_SCORE - 1;
    var alpha: i32 = -CHECKMATE_SCORE - 1;
    const beta: i32 = CHECKMATE_SCORE + 1;

    var moves = movegen.generateLegalMoves(board);

    for (moves.slice()) |move| {
        const undo = board.makeMove(move);
        const score = -negamax(board, depth - 1, -beta, -alpha, state);
        board.unmakeMove(move, undo);

        if (state.stop.load(.acquire)) break;

        if (score > best_score) {
            best_score = score;
            best_move = move;
            if (score > alpha) alpha = score;
        }
    }

    return SearchResult{
        .move = best_move,
        .score = best_score,
        .depth = depth,
        .nodes = state.nodes.load(.acquire),
    };
}

fn promoChar(m: Move) []const u8 {
    return switch (m.flag) {
        .promo_queen, .promo_queen_capture => "q",
        .promo_rook, .promo_rook_capture => "r",
        .promo_bishop, .promo_bishop_capture => "b",
        .promo_knight, .promo_knight_capture => "n",
        else => "",
    };
}

const NullWriter = struct {
    pub fn print(_: @This(), comptime fmt: []const u8, args: anytype) !void {
        _ = fmt;
        _ = args;
    }
    pub fn flush(_: @This()) !void {}
};

pub fn searchWithWriter(board: *Board, max_depth: u32, state: *SearchState, writer: anytype) SearchResult {
    var best = SearchResult{ .move = null, .score = 0, .depth = 0 };

    var threaded_io: std.Io.Threaded = .init_single_threaded;
    defer threaded_io.deinit();
    const io = threaded_io.io();

    const start_ts: std.Io.Timestamp = std.Io.Clock.now(.awake, io);

    const maybe_thread: ?std.Thread = if (state.limit_ms != null)
        std.Thread.spawn(.{}, timerThread, .{ state, io }) catch null
    else
        null;

    var depth: u32 = 1;
    while (depth <= max_depth) : (depth += 1) {
        const result = searchDepth(board, depth, state);
        if (state.stop.load(.acquire)) break;
        best = result;

        const now_ts: std.Io.Timestamp = std.Io.Clock.now(.awake, io);
        const elapsed_ms: u64 = @intCast(start_ts.durationTo(now_ts).toMilliseconds());
        const nps: u64 = if (elapsed_ms > 0) result.nodes * 1000 / elapsed_ms else result.nodes;

        // SAFE CLAMPING TO PREVENT PANIC ON NEGATIVE CASTS
        if (result.score > CHECKMATE_SCORE - 500) {
            const plies: u32 = @intCast(@max(0, CHECKMATE_SCORE - result.score));
            writer.print("info depth {d} score mate {d} time {d} nodes {d} nps {d}", .{
                result.depth, (plies + 1) / 2, elapsed_ms, result.nodes, nps,
            }) catch {};
        } else if (result.score < -(CHECKMATE_SCORE - 500)) {
            const clamped = @max(result.score, -CHECKMATE_SCORE);
            const plies: u32 = @intCast(CHECKMATE_SCORE + clamped);
            writer.print("info depth {d} score mate -{d} time {d} nodes {d} nps {d}", .{
                result.depth, (plies + 1) / 2, elapsed_ms, result.nodes, nps,
            }) catch {};
        } else {
            writer.print("info depth {d} score cp {d} time {d} nodes {d} nps {d}", .{
                result.depth, result.score, elapsed_ms, result.nodes, nps,
            }) catch {};
        }

        if (result.move) |m| {
            writer.print(" pv {s}{s}{s}", .{
                m.from.toString(), m.to.toString(), promoChar(m),
            }) catch {};
        }
        writer.print("\n", .{}) catch {};
        writer.flush() catch {};
    }

    state.search_done.store(true, .release);
    if (maybe_thread) |t| t.join();

    return best;
}

pub fn searchWithState(board: *Board, max_depth: u32, state: *SearchState) SearchResult {
    return searchWithWriter(board, max_depth, state, NullWriter{});
}

pub fn search(board: *Board, max_depth: u32) SearchResult {
    var state = SearchState.init();
    return searchWithState(board, max_depth, &state);
}
