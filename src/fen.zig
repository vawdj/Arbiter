const std = @import("std");
const Board = @import("board.zig").Board;
const CastlingRights = @import("board.zig").CastlingRights;
const Square = @import("square.zig").Square;
const Piece = @import("piece.zig").Piece;
const Color = @import("piece.zig").Color;

pub const FenError = error{
    InvalidFieldCount,
    InvalidPiecePlacement,
    InvalidSideToMove,
    InvalidCastlingRights,
    InvalidEnPassant,
    InvalidNumber,
};

pub fn parse(fen: []const u8) FenError!Board {
    var board = Board.empty();

    var fields = std.mem.splitScalar(u8, fen, ' ');

    const placement = fields.next() orelse return FenError.InvalidFieldCount;
    try parsePlacement(&board, placement);

    const stm = fields.next() orelse return FenError.InvalidFieldCount;
    board.side_to_move = try parseSideToMove(stm);

    const castling = fields.next() orelse return FenError.InvalidFieldCount;
    board.castling = try parseCastling(castling);

    const ep = fields.next() orelse return FenError.InvalidFieldCount;
    board.en_passant_target = try parseEnPassant(ep);

    const halfmove = fields.next() orelse return FenError.InvalidFieldCount;
    board.halfmove_clock = std.fmt.parseInt(u32, halfmove, 10) catch return FenError.InvalidNumber;

    const fullmove = fields.next() orelse return FenError.InvalidFieldCount;
    board.fullmove_number = std.fmt.parseInt(u32, fullmove, 10) catch return FenError.InvalidNumber;

    return board;
}

fn parsePlacement(board: *Board, placement: []const u8) FenError!void {
    var rank: i8 = 7;
    var file: u8 = 0;

    for (placement) |c| {
        if (c == '/') {
            if (file != 8) return FenError.InvalidPiecePlacement;
            rank -= 1;
            file = 0;
            continue;
        }

        if (c >= '1' and c <= '8') {
            file += c - '0';
            continue;
        }

        if (file >= 8 or rank < 0) return FenError.InvalidPiecePlacement;

        const piece = Piece.fromChar(c) orelse return FenError.InvalidPiecePlacement;
        const sq = Square.fromFileRank(@intCast(file), @intCast(rank));
        board.setPiece(sq, piece);
        file += 1;
    }

    if (rank != 0 or file != 8) return FenError.InvalidPiecePlacement;
}

fn parseSideToMove(s: []const u8) FenError!Color {
    if (Color.fromString(s)) |c| {
        return c;
    } else {
        return FenError.InvalidSideToMove;
    }
}

fn parseCastling(s: []const u8) FenError!CastlingRights {
    var rights = CastlingRights{};
    if (std.mem.eql(u8, s, "-")) return rights;

    for (s) |c| {
        switch (c) {
            'K' => rights.white_kingside = true,
            'Q' => rights.white_queenside = true,
            'k' => rights.black_kingside = true,
            'q' => rights.black_queenside = true,
            else => return FenError.InvalidCastlingRights,
        }
    }
    return rights;
}

fn parseEnPassant(s: []const u8) FenError!?Square {
    if (std.mem.eql(u8, s, "-")) return null;
    return Square.fromString(s) orelse FenError.InvalidEnPassant;
}

pub fn toFen(board: Board, allocator: std.mem.Allocator) ![]u8 {
    var buf: [128]u8 = undefined;
    var index: usize = 0;

    var rank: i8 = 7;
    while (rank >= 0) : (rank -= 1) {
        var empty_count: u8 = 0;
        var file: u8 = 0;
        while (file < 8) : (file += 1) {
            const sq = Square.fromFileRank(@intCast(file), @intCast(rank));
            if (board.pieceAt(sq)) |piece| {
                if (empty_count > 0) {
                    const printed = try std.fmt.bufPrint(buf[index..], "{d}", .{empty_count});
                    index += printed.len;
                    empty_count = 0;
                }
                const printed = try std.fmt.bufPrint(buf[index..], "{c}", .{piece.toChar()});
                index += printed.len;
            } else {
                empty_count += 1;
            }
        }
        if (empty_count > 0) {
            const printed = try std.fmt.bufPrint(buf[index..], "{d}", .{empty_count});
            index += printed.len;
        }
        if (rank > 0) {
            const printed = try std.fmt.bufPrint(buf[index..], "/", .{});
            index += printed.len;
        }
    }

    {
        const side_char: u8 = if (board.side_to_move == .white) 'w' else 'b';
        const printed = try std.fmt.bufPrint(buf[index..], " {c}", .{side_char});
        index += printed.len;
    }

    {
        const printed = try std.fmt.bufPrint(buf[index..], " ", .{});
        index += printed.len;
    }

    const c = board.castling;
    if (!c.white_kingside and !c.white_queenside and !c.black_kingside and !c.black_queenside) {
        const printed = try std.fmt.bufPrint(buf[index..], "-", .{});
        index += printed.len;
    } else {
        if (c.white_kingside) {
            const printed = try std.fmt.bufPrint(buf[index..], "K", .{});
            index += printed.len;
        }
        if (c.white_queenside) {
            const printed = try std.fmt.bufPrint(buf[index..], "Q", .{});
            index += printed.len;
        }
        if (c.black_kingside) {
            const printed = try std.fmt.bufPrint(buf[index..], "k", .{});
            index += printed.len;
        }
        if (c.black_queenside) {
            const printed = try std.fmt.bufPrint(buf[index..], "q", .{});
            index += printed.len;
        }
    }

    {
        const printed = try std.fmt.bufPrint(buf[index..], " ", .{});
        index += printed.len;
    }

    if (board.en_passant_target) |sq| {
        const sq_str = sq.toString();
        const printed = try std.fmt.bufPrint(buf[index..], "{s}", .{&sq_str});
        index += printed.len;
    } else {
        const printed = try std.fmt.bufPrint(buf[index..], "-", .{});
        index += printed.len;
    }

    {
        const printed = try std.fmt.bufPrint(buf[index..], " {d} {d}", .{ board.halfmove_clock, board.fullmove_number });
        index += printed.len;
    }

    return allocator.dupe(u8, buf[0..index]);
}

pub const start_position = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

test "parse starting position" {
    const board = try parse(start_position);
    try std.testing.expectEqual(Color.white, board.side_to_move);
    try std.testing.expectEqual(@as(?Square, null), board.en_passant_target);
    try std.testing.expect(board.castling.white_kingside);
    try std.testing.expect(board.castling.black_queenside);

    const a1_piece = board.pieceAt(.a1).?;
    try std.testing.expectEqual(Color.white, a1_piece.color);
    try std.testing.expectEqual(@import("piece.zig").PieceType.rook, a1_piece.kind);

    const e8_piece = board.pieceAt(.e8).?;
    try std.testing.expectEqual(Color.black, e8_piece.color);
    try std.testing.expectEqual(@import("piece.zig").PieceType.king, e8_piece.kind);

    try std.testing.expectEqual(@as(?Piece, null), board.pieceAt(.e4));
}

test "parse position with en passant and partial castling" {
    const board = try parse("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w Kq e6 0 2");
    try std.testing.expectEqual(Square.e6, board.en_passant_target.?);
    try std.testing.expect(board.castling.white_kingside);
    try std.testing.expect(!board.castling.white_queenside);
    try std.testing.expect(!board.castling.black_kingside);
    try std.testing.expect(board.castling.black_queenside);
}

test "round trip start position through toFen" {
    const board = try parse(start_position);
    const fen = try toFen(board, std.testing.allocator);
    defer std.testing.allocator.free(fen);
    try std.testing.expectEqualStrings(start_position, fen);
}

test "invalid fen rejected" {
    try std.testing.expectError(FenError.InvalidFieldCount, parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"));
    try std.testing.expectError(FenError.InvalidSideToMove, parse("8/8/8/8/8/8/8/8 x - - 0 1"));
}
