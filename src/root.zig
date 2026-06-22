const std = @import("std");

pub const Board = @import("board.zig").Board;
pub const CastlingRights = @import("board.zig").CastlingRights;

pub const Square = @import("square.zig").Square;

pub const Piece = @import("piece.zig").Piece;
pub const Color = @import("piece.zig").Color;
pub const PieceType = @import("piece.zig").PieceType;

pub const Move = @import("move.zig").Move;
pub const MoveFlag = @import("move.zig").MoveFlag;
pub const MoveList = @import("move.zig").MoveList;

pub const fen = @import("fen.zig");
pub const movegen = @import("movegen.zig");
pub const perft = @import("perft.zig");
pub const evaluate = @import("eval.zig").evaluate;
pub const search = @import("search.zig").search;

pub const SearchResult = @import("search.zig").SearchResult;

test {
    std.testing.refAllDecls(@This());
}
