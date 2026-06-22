const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // 1. Initialise the stdout writer (Slicing the buffer with [0..])
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, stdout_buf[0..]);
    const stdout = &stdout_writer.interface;

    // 2. Setup the stdin reader (Slicing the buffer with [0..])
    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, stdin_buf[0..]);
    const stdin = &stdin_reader.interface;

    while (true) {
        try stdout.writeAll("enter moves in format: e2e4, or 'quit' to exit: ");
        try stdout.flush(); // Force the terminal to show the prompt immediately

        // 3. takeDelimiter() consumes the '\n' and cleanly blocks for new input
        const line = try stdin.takeDelimiter('\n') orelse break;

        // 4. Strip any padding or Windows carriage returns safely
        const trimmed = std.mem.trim(u8, line, " \r\t");

        // 5. Echo processing back to the user
        try stdout.print("Processed: '{s}' (Length: {d})\n\n", .{ trimmed, trimmed.len });
        try stdout.flush();

        if (std.mem.eql(u8, trimmed, "quit")) {
            break;
        }
    }
}
