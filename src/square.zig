const std = @import("std");

pub const Square = enum(u6) {
    a1,
    b1,
    c1,
    d1,
    e1,
    f1,
    g1,
    h1,
    a2,
    b2,
    c2,
    d2,
    e2,
    f2,
    g2,
    h2,
    a3,
    b3,
    c3,
    d3,
    e3,
    f3,
    g3,
    h3,
    a4,
    b4,
    c4,
    d4,
    e4,
    f4,
    g4,
    h4,
    a5,
    b5,
    c5,
    d5,
    e5,
    f5,
    g5,
    h5,
    a6,
    b6,
    c6,
    d6,
    e6,
    f6,
    g6,
    h6,
    a7,
    b7,
    c7,
    d7,
    e7,
    f7,
    g7,
    h7,
    a8,
    b8,
    c8,
    d8,
    e8,
    f8,
    g8,
    h8,

    pub fn file(self: Square) u3 {
        return @intCast(@intFromEnum(self) % 8);
    }

    pub fn rank(self: Square) u3 {
        return @intCast(@intFromEnum(self) / 8);
    }

    pub fn fromFileRank(f: u3, r: u3) Square {
        return @enumFromInt(@as(u6, r) * 8 + f);
    }

    pub fn toString(self: Square) [2]u8 {
        return .{ 'a' + @as(u8, file(self)), '1' + @as(u8, rank(self)) };
    }

    pub fn fromString(s: []const u8) ?Square {
        if (s.len != 2) {
            return null;
        }

        const f = s[0] -% 'a';
        const r = s[1] -% '1';

        if (f > 7 or r > 7) {
            return null;
        }

        return fromFileRank(@truncate(f), @truncate(r));
    }
};

test "file and rank extraction" {
    try std.testing.expectEqual(@as(u3, 0), Square.a1.file());
    try std.testing.expectEqual(@as(u3, 0), Square.a1.rank());
    try std.testing.expectEqual(@as(u3, 7), Square.h8.file());
    try std.testing.expectEqual(@as(u3, 7), Square.h8.rank());
}

test "string round-trip" {
    try std.testing.expectEqual(Square.e4, Square.fromString("e4").?);
    try std.testing.expectEqualStrings("e4", &Square.e4.toString());
}
