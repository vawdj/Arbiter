const std = @import("std");

const Square = @import("square.zig").Square;
const Piece = @import("piece.zig").Piece;
const Color = @import("piece.zig").Color;
const Move = @import("move.zig").Move;
const Fen = @import("fen.zig");

pub const CastlingRights = packed struct {
    white_kingside: bool = false,
    white_queenside: bool = false,
    black_kingside: bool = false,
    black_queenside: bool = false,
};

pub const UndoInfo = struct {
    captured: ?Piece,
    castling: CastlingRights,
    en_passant_target: ?Square,
    halfmove_clock: u32,
};

pub const Board = struct {
    squares: [64]?Piece = [_]?Piece{null} ** 64,
    side_to_move: Color = .white,
    castling: CastlingRights = .{},
    en_passant_target: ?Square = null,
    halfmove_clock: u32 = 0,
    fullmove_number: u32 = 1,

    pub fn empty() Board {
        return Board{};
    }

    pub fn startPosition() Board {
        return Fen.parse(Fen.start_position) catch unreachable;
    }

    pub fn pieceAt(self: Board, sq: Square) ?Piece {
        return self.squares[@intFromEnum(sq)];
    }

    pub fn setPiece(self: *Board, sq: Square, piece: ?Piece) void {
        self.squares[@intFromEnum(sq)] = piece;
    }

    pub fn print(self: Board, writer: anytype) !void {
        // rank 8 down to rank 1, file a to h
        var rank: i8 = 7;
        while (rank >= 0) : (rank -= 1) {
            var file: u8 = 0;
            while (file < 8) : (file += 1) {
                const sq = Square.fromFileRank(@intCast(file), @intCast(rank));
                const piece = self.pieceAt(sq);
                const c: u8 = if (piece) |p| p.toChar() else '.';
                try writer.print("{c} ", .{c});
            }
            try writer.print("\n", .{});
        }
    }

    pub fn findKing(self: Board, color: Color) Square {
        for (self.squares, 0..) |piece, i| {
            if (piece) |p| {
                if (p.color == color and p.kind == .king) {
                    return @enumFromInt(i);
                }
            }
        }
        unreachable; // a valid board always has both kings
    }

    pub fn makeMove(self: *Board, move: Move) UndoInfo {
        const from = move.from;
        const to = move.to;
        const moving_piece = self.pieceAt(from).?;

        // snapshot everything that will be destroyed and cant be
        // recovered from the move struct alone
        var undo = UndoInfo{
            .captured = self.pieceAt(to),
            .castling = self.castling,
            .en_passant_target = self.en_passant_target,
            .halfmove_clock = self.halfmove_clock,
        };

        // clear en passant — will be re-set below if this is a double pawn push
        self.en_passant_target = null;

        // update halfmove clock
        if (move.flag.isCapture() or moving_piece.kind == .pawn) {
            self.halfmove_clock = 0;
        } else {
            self.halfmove_clock += 1;
        }

        switch (move.flag) {
            .quiet, .capture => {
                self.setPiece(to, moving_piece);
                self.setPiece(from, null);
            },

            .double_pawn_push => {
                self.setPiece(to, moving_piece);
                self.setPiece(from, null);
                // en passant target is the square the pawn skipped over
                const ep_rank: u3 = if (moving_piece.color == .white) 2 else 5;
                self.en_passant_target = Square.fromFileRank(from.file(), ep_rank);
            },

            .en_passant => {
                self.setPiece(to, moving_piece);
                self.setPiece(from, null);
                // the captured pawn is behind the destination square
                // not on it — fix up undo.captured and remove it
                const captured_rank: u3 = if (moving_piece.color == .white) 4 else 3;
                const captured_sq = Square.fromFileRank(to.file(), captured_rank);
                undo.captured = self.pieceAt(captured_sq);
                self.setPiece(captured_sq, null);
            },

            .castle_kingside => {
                self.setPiece(to, moving_piece);
                self.setPiece(from, null);
                // move the rook — kingside rook is always on the h file
                const rook_from = Square.fromFileRank(7, from.rank());
                const rook_to = Square.fromFileRank(5, from.rank());
                self.setPiece(rook_to, self.pieceAt(rook_from));
                self.setPiece(rook_from, null);
            },

            .castle_queenside => {
                self.setPiece(to, moving_piece);
                self.setPiece(from, null);
                // move the rook — queenside rook is always on the a file
                const rook_from = Square.fromFileRank(0, from.rank());
                const rook_to = Square.fromFileRank(3, from.rank());
                self.setPiece(rook_to, self.pieceAt(rook_from));
                self.setPiece(rook_from, null);
            },

            .promo_knight, .promo_knight_capture => {
                self.setPiece(to, Piece{ .color = moving_piece.color, .kind = .knight });
                self.setPiece(from, null);
            },

            .promo_bishop, .promo_bishop_capture => {
                self.setPiece(to, Piece{ .color = moving_piece.color, .kind = .bishop });
                self.setPiece(from, null);
            },

            .promo_rook, .promo_rook_capture => {
                self.setPiece(to, Piece{ .color = moving_piece.color, .kind = .rook });
                self.setPiece(from, null);
            },

            .promo_queen, .promo_queen_capture => {
                self.setPiece(to, Piece{ .color = moving_piece.color, .kind = .queen });
                self.setPiece(from, null);
            },
        }

        // update castling rights based on what moved or was captured
        // any king move revokes both rights for that side
        // any rook move or rook capture revokes that specific right
        if (moving_piece.kind == .king) {
            switch (moving_piece.color) {
                .white => {
                    self.castling.white_kingside = false;
                    self.castling.white_queenside = false;
                },
                .black => {
                    self.castling.black_kingside = false;
                    self.castling.black_queenside = false;
                },
            }
        }

        // rook moves revoke castling rights for their corner
        updateCastlingRightsForSquare(&self.castling, from);
        // rook captures also revoke — if a rook on a1 is captured,
        // white can no longer castle queenside
        updateCastlingRightsForSquare(&self.castling, to);

        // flip side to move
        self.side_to_move = self.side_to_move.opponent();

        // increment fullmove number after black moves
        if (self.side_to_move == .white) {
            self.fullmove_number += 1;
        }

        return undo;
    }

    // revokes castling rights if a rook's home square is involved in a move
    fn updateCastlingRightsForSquare(castling: *CastlingRights, sq: Square) void {
        switch (sq) {
            .a1 => castling.white_queenside = false,
            .h1 => castling.white_kingside = false,
            .a8 => castling.black_queenside = false,
            .h8 => castling.black_kingside = false,
            else => {},
        }
    }

    pub fn unmakeMove(self: *Board, move: Move, undo: UndoInfo) void {
        const from = move.from;
        const to = move.to;

        // flip side back — the piece that moved belongs to the side
        // that is now active after unmaking
        self.side_to_move = self.side_to_move.opponent();

        // restore state fields unconditionally from undo
        self.castling = undo.castling;
        self.en_passant_target = undo.en_passant_target;
        self.halfmove_clock = undo.halfmove_clock;
        if (self.side_to_move == .black) {
            self.fullmove_number -= 1;
        }

        const moving_piece = self.pieceAt(to);

        switch (move.flag) {
            .quiet, .capture => {
                self.setPiece(from, moving_piece);
                self.setPiece(to, undo.captured);
            },

            .double_pawn_push => {
                self.setPiece(from, moving_piece);
                self.setPiece(to, null);
            },

            .en_passant => {
                self.setPiece(from, moving_piece);
                self.setPiece(to, null);
                const captured_rank: u3 = if (self.side_to_move == .white) 4 else 3;
                const captured_sq = Square.fromFileRank(to.file(), captured_rank);
                self.setPiece(captured_sq, undo.captured);
            },

            .castle_kingside => {
                self.setPiece(from, moving_piece);
                self.setPiece(to, null);
                const rook_from = Square.fromFileRank(7, from.rank());
                const rook_to = Square.fromFileRank(5, from.rank());
                self.setPiece(rook_from, self.pieceAt(rook_to));
                self.setPiece(rook_to, null);
            },

            .castle_queenside => {
                self.setPiece(from, moving_piece);
                self.setPiece(to, null);
                const rook_from = Square.fromFileRank(0, from.rank());
                const rook_to = Square.fromFileRank(3, from.rank());
                self.setPiece(rook_from, self.pieceAt(rook_to));
                self.setPiece(rook_to, null);
            },

            // for promotions, the piece on `to` is the promoted piece,
            // not the pawn — so we restore the pawn explicitly
            .promo_knight, .promo_bishop, .promo_rook, .promo_queen => {
                self.setPiece(from, Piece{ .color = self.side_to_move, .kind = .pawn });
                self.setPiece(to, null);
            },

            .promo_knight_capture, .promo_bishop_capture, .promo_rook_capture, .promo_queen_capture => {
                self.setPiece(from, Piece{ .color = self.side_to_move, .kind = .pawn });
                self.setPiece(to, undo.captured);
            },
        }
    }
};

test "makemove quiet move" {
    const fen = @import("fen.zig");
    var board = try fen.parse(fen.start_position);
    const move = Move{ .from = .e2, .to = .e4, .flag = .double_pawn_push };
    const undo = board.makeMove(move);
    try std.testing.expectEqual(Color.black, board.side_to_move);
    try std.testing.expectEqual(@as(?Piece, null), board.pieceAt(.e2));
    try std.testing.expect(board.pieceAt(.e4) != null);
    try std.testing.expectEqual(Square.e3, board.en_passant_target.?);
    board.unmakeMove(move, undo);
    try std.testing.expectEqual(Color.white, board.side_to_move);
    try std.testing.expect(board.pieceAt(.e2) != null);
    try std.testing.expectEqual(@as(?Piece, null), board.pieceAt(.e4));
    try std.testing.expectEqual(@as(?Square, null), board.en_passant_target);
}

test "makemove revokes castling rights on king move" {
    const fen = @import("fen.zig");
    var board = try fen.parse("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    const move = Move{ .from = .e1, .to = .f1, .flag = .quiet };
    const undo = board.makeMove(move);
    try std.testing.expect(!board.castling.white_kingside);
    try std.testing.expect(!board.castling.white_queenside);
    try std.testing.expect(board.castling.black_kingside);
    try std.testing.expect(board.castling.black_queenside);
    board.unmakeMove(move, undo);
    try std.testing.expect(board.castling.white_kingside);
    try std.testing.expect(board.castling.white_queenside);
}

test "makemove and unmakemove round trip matches original fen" {
    const fen = @import("fen.zig");
    var board = try fen.parse(fen.start_position);
    const before = try fen.toFen(board, std.testing.allocator);
    defer std.testing.allocator.free(before);
    const move = Move{ .from = .e2, .to = .e4, .flag = .double_pawn_push };
    const undo = board.makeMove(move);
    board.unmakeMove(move, undo);
    const after = try fen.toFen(board, std.testing.allocator);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings(before, after);
}
