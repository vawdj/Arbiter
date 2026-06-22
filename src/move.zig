const std = @import("std");
const Square = @import("square.zig").Square;

pub const MoveFlag = enum(u4) {
    quiet,
    double_pawn_push,
    castle_kingside,
    castle_queenside,
    capture,
    en_passant,
    promo_knight,
    promo_bishop,
    promo_rook,
    promo_queen,
    promo_knight_capture,
    promo_bishop_capture,
    promo_rook_capture,
    promo_queen_capture,

    pub fn isPromotion(self: MoveFlag) bool {
        return @intFromEnum(self) >= @intFromEnum(MoveFlag.promo_knight);
    }

    pub fn isCapture(self: MoveFlag) bool {
        return self == .capture or self == .en_passant or
            @intFromEnum(self) >= @intFromEnum(MoveFlag.promo_knight_capture);
    }
};

pub const Move = packed struct(u16) {
    from: Square,
    to: Square,
    flag: MoveFlag,
};

pub const MoveList = struct {
    moves: [256]Move = undefined,
    count: usize = 0,

    pub fn append(self: *MoveList, move: Move) void {
        self.moves[self.count] = move;
        self.count += 1;
    }

    pub fn slice(self: *const MoveList) []const Move {
        return self.moves[0..self.count];
    }
};

test "move is exactly 2 bytes" {
    try std.testing.expectEqual(2, @sizeOf(Move));
}

test "move field access" {
    const m = Move{ .from = .e2, .to = .e4, .flag = .double_pawn_push };
    try std.testing.expectEqual(Square.e2, m.from);
    try std.testing.expectEqual(Square.e4, m.to);
}

test "movelist move survives packed struct round-trip" {
    var list = MoveList{};
    list.append(Move{ .from = .h8, .to = .a1, .flag = .promo_queen_capture });
    const m = list.slice()[0];
    try std.testing.expectEqual(Square.h8, m.from);
    try std.testing.expectEqual(Square.a1, m.to);
    try std.testing.expectEqual(MoveFlag.promo_queen_capture, m.flag);
}

test "movelist move survives packed struct round-trip for all flags" {
    var list = MoveList{};
    const flags = [_]MoveFlag{
        .quiet,              .double_pawn_push,    .castle_kingside,      .castle_queenside,
        .capture,            .en_passant,          .promo_knight,         .promo_bishop,
        .promo_rook,         .promo_queen,         .promo_knight_capture, .promo_bishop_capture,
        .promo_rook_capture, .promo_queen_capture,
    };
    for (flags) |flag| {
        list.append(Move{ .from = .a1, .to = .h8, .flag = flag });
    }
    for (flags, 0..) |flag, i| {
        try std.testing.expectEqual(flag, list.slice()[i].flag);
    }
}
