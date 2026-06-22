const std = @import("std");

pub const Color = enum(u1) {
    white,
    black,

    pub fn opponent(self: Color) Color {
        return switch (self) {
            .white => .black,
            .black => .white,
        };
    }

    pub fn fromString(s: []const u8) ?Color {
        if (s.len != 1) {
            return null;
        }

        return switch (s[0]) {
            'w' => .white,
            'b' => .black,
            else => null,
        };
    }
};

pub const PieceType = enum(u3) {
    pawn,
    knight,
    bishop,
    rook,
    queen,
    king,
};

pub const Piece = struct {
    color: Color,
    kind: PieceType,

    pub fn toChar(self: Piece) u8 {
        const c: u8 = switch (self.kind) {
            .pawn => 'p',
            .knight => 'n',
            .bishop => 'b',
            .rook => 'r',
            .queen => 'q',
            .king => 'k',
        };
        return switch (self.color) {
            .white => std.ascii.toUpper(c),
            .black => c,
        };
    }

    pub fn fromChar(c: u8) ?Piece {
        const color: Color = if (std.ascii.isUpper(c)) .white else .black;
        const kind: PieceType = switch (std.ascii.toLower(c)) {
            'p' => .pawn,
            'n' => .knight,
            'b' => .bishop,
            'r' => .rook,
            'q' => .queen,
            'k' => .king,
            else => return null,
        };
        return Piece{ .color = color, .kind = kind };
    }
};

test "piece char round-trip" {
    const p = Piece{ .color = .white, .kind = .knight };
    try std.testing.expectEqual(@as(u8, 'N'), p.toChar());
    try std.testing.expectEqual(p, Piece.fromChar('N').?);

    const b = Piece{ .color = .black, .kind = .queen };
    try std.testing.expectEqual(@as(u8, 'q'), b.toChar());
}
