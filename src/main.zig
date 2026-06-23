const std = @import("std");
const uci = @import("uci.zig");
const play = @import("play.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, stdout_buf[0..]);
    const stdout = &stdout_writer.interface;

    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, stdin_buf[0..]);
    const stdin = &stdin_reader.interface;

    const first = try stdin.takeDelimiter('\n') orelse return;
    const trimmed = std.mem.trim(u8, first, " \r\t");

    if (std.mem.eql(u8, trimmed, "uci")) {
        try uci.run(stdin, stdout);
    } else {
        try play.run(trimmed, stdin, stdout);
    }
}
