const std = @import("std");
const LineReader = @import("LineReader.zig").LineReader;
const ByteWriter = @import("ByteWriter.zig").ByteWriter;

fn trimLeft(str: []const u8) []const u8 {
    return std.mem.trimLeft(u8, str, &[_]u8{' ', '\t'});
}

const State = struct {
    bullets: bool = false,
    preformatted: bool = false,
};

fn handleLine(line: []const u8, writer: *ByteWriter, state: *State) !void {
    if (line.len >= 1 and line[0] == '*' and !state.bullets) {
        state.bullets = true;
        try writer.writeBytes("<ul>\n");
    } else if (state.bullets and (line.len == 0 or line[0] != '*')) {
        state.bullets = false;
        try writer.writeBytes("</ul>\n");
    }
    if (state.preformatted) {
        if (line.len >= 3 and line[0] == '`' and line[1] == '`' and line[2] == '`') {
            state.preformatted = false;
            return writer.writeBytes("</pre>\n");
        } else {
            try writer.writeEscapedBytes(line);
            return writer.writeByte('\n');
        }
    }
    if (line.len >= 3) {
        if (line[0] == '#' and line[1] == '#' and line[2] == '#') {
            try writer.writeBytes("<h3>");
            try writer.writeEscapedBytes(trimLeft(line[3..]));
            return writer.writeBytes("</h3>\n");
        }
        if (line[0] == '`' and line[1] == '`' and line[2] == '`') {
            state.preformatted = true;
            const altText = trimLeft(line[3..]);
            if (altText.len == 0) {
                return writer.writeBytes("<pre>\n");
            } else {
                try writer.writeBytes("<pre alt=\"");
                try writer.writeEscapedBytes(altText);
                return writer.writeBytes("\">\n");
            }
        }
    }
    if (line.len >= 2) {
        if (line[0] == '#' and line[1] == '#') {
            try writer.writeBytes("<h2>");
            try writer.writeEscapedBytes(trimLeft(line[2..]));
            return writer.writeBytes("</h2>\n");
        }
        if (line[0] == '=' and line[1] == '>') {
            const contents = trimLeft(line[2..]);
            var spaceIndex: usize = 0;
            while (spaceIndex < contents.len and !(contents[spaceIndex] == ' ' or contents[spaceIndex] == '\t')) : (spaceIndex += 1) {}
            const url = contents[0..spaceIndex];
            var text = trimLeft(contents[spaceIndex..]);
            if (text.len == 0) {
                text = url;
            }
            try writer.writeBytes("<a href=\"");
            try writer.writeEscapedBytes(url);
            try writer.writeBytes("\">");
            try writer.writeEscapedBytes(text);
            return writer.writeBytes("</a><br/>\n");
        }
    }
    if (line.len >= 1) {
        if (line[0] == '#') {
            try writer.writeBytes("<h1>");
            try writer.writeEscapedBytes(trimLeft(line[1..]));
            return writer.writeBytes("</h1>\n");
        }
        if (line[0] == '*') {
            try writer.writeBytes("<li>");
            try writer.writeEscapedBytes(trimLeft(line[1..]));
            return writer.writeBytes("</li>\n");
        }
        if (line[0] == '>') {
            try writer.writeBytes("<blockquote>");
            try writer.writeEscapedBytes(trimLeft(line[1..]));
            return writer.writeBytes("</blockquote>\n");
        }
    }
    try writer.writeEscapedBytes(line);
    return writer.writeBytes("<br/>\n");
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    var args = std.process.args();
    defer args.deinit();
    _ = args.skip();

    const inputFile = if (args.next(allocator)) |arg| blk: {
        break :blk try std.fs.cwd().openFile(try arg, .{.read = true});
    }
    else
        std.io.getStdIn();
    defer inputFile.close();
    var reader = try LineReader.init(allocator, inputFile.reader());
    var writer = ByteWriter.init(std.io.getStdOut().writer());
    var state = State {};

    while (try reader.readLine()) |line| {
        try handleLine(line, &writer, &state);
    }
    try writer.flush();
}
