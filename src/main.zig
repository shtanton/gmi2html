const std = @import("std");
const process = std.process;

fn trimLeft(str: []const u8) []const u8 {
    return std.mem.trimLeft(u8, str, &[_]u8{' ', '\t'});
}

const State = struct {
    bullets: bool,
    preformatted: bool,

    fn init() State {
        return State {
            .bullets = false,
            .preformatted = false,
        };
    }
};

const BufferedWriter = struct {
    const Self = @This();

    buffer: [256]u8,
    writer: std.fs.File.Writer,
    len: usize,

    fn init(writer: std.fs.File.Writer) Self {
        return Self {
            .buffer = undefined,
            .writer = writer,
            .len = 0,
        };
    }

    fn flush(self: *Self) !void {
        if (self.len!=0) {
            try self.writer.writeAll(self.buffer[0..self.len]);
            self.len = 0;
        }
    }

    fn writeByte(self: *Self, byte: u8) !void {
        self.buffer[self.len] = byte;
        self.len += 1;
        if (self.len==256) {
            try self.writer.writeAll(&self.buffer);
            self.len = 0;
        }
    }

    fn writeBytes(self: *Self, bytes: []const u8) !void {
        for (bytes) |byte| {
            try self.writeByte(byte);
        }
    }

    fn writeEscapedBytes(self: *Self, bytes: []const u8) !void {
        for (bytes) |byte| {
            try switch (byte) {
                '&' => self.writeBytes("&amp"),
                '<' => self.writeBytes("&lt"),
                '>' => self.writeBytes("&gt"),
                '"' => self.writeBytes("&quot"),
                '\'' => self.writeBytes("&#39"),
                else => self.writeByte(byte),
            };
        }
    }
};

fn handleLine(line: []u8, writer: *BufferedWriter, state: *State) !void {
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

    var args = process.args();
    defer args.deinit();
    _ = args.skip();

    const inputFile = if (args.next(allocator)) |arg| blk: {
        break :blk try std.fs.cwd().openFile(try arg, .{.read = true});
    }
    else
        std.io.getStdIn();
    defer inputFile.close();

    const inputContents = try inputFile.reader().readAllAlloc(allocator, 512*1024*1024);

    var progress: usize = 0;
    var lineEnd: usize = 0;
    var state = State.init();
    const stdout = std.io.getStdOut();
    var writer = BufferedWriter.init(stdout.writer());
    while (progress < inputContents.len) : ({
        progress = lineEnd + 1;
        lineEnd = progress;
    }) {
        while (lineEnd < inputContents.len and inputContents[lineEnd] != '\n') : (lineEnd += 1) {}

        try handleLine(inputContents[progress..lineEnd], &writer, &state);
    }
    try writer.flush();
}
