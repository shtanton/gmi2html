const std = @import("std");
const process = std.process;
const Allocator = std.mem.Allocator;

const READ_BUFFER_INITIAL_LEN = 8192;
const WRITE_BUFFER_LEN = 8192;

fn trimLeft(str: []const u8) []const u8 {
    return std.mem.trimLeft(u8, str, &[_]u8{' ', '\t'});
}

const LineReader = struct {
    const Self = @This();

    buffer: []u8,
    reader: std.fs.File.Reader,
    allocator: *Allocator,
    nextLineStart: usize,
    len: usize,

    fn init(allocator: *Allocator, reader: std.fs.File.Reader) !Self {
        return Self {
            .buffer = try allocator.alloc(u8, READ_BUFFER_INITIAL_LEN),
            .reader = reader,
            .allocator = allocator,
            .nextLineStart = 0,
            .len = 0,
        };
    }

    fn deinit(self: Self) void {
        self.allocator.free(self.buffer);
    }

    fn readLine(self: *Self) !?[]const u8 {
        var newlineIndex = self.nextLineStart;
        while (true) : (newlineIndex += 1) {
            if (newlineIndex >= self.len) {
                if (self.len == self.buffer.len) {
                    if (self.nextLineStart==0) {
                        self.buffer = try self.allocator.realloc(self.buffer, self.buffer.len*2);
                    } else {
                        std.mem.copy(u8, self.buffer, self.buffer[self.nextLineStart..self.len]);
                        self.len -= self.nextLineStart;
                        newlineIndex -= self.nextLineStart;
                        self.nextLineStart = 0;
                    }
                }
                self.len += try self.reader.read(self.buffer[self.len..]);
            }
            if (self.len == self.nextLineStart) {
                return null;
            }
            if (newlineIndex >= self.len) {
                const line = self.buffer[self.nextLineStart..newlineIndex];
                self.nextLineStart = newlineIndex;
                return line;
            } else if (self.buffer[newlineIndex]=='\n') {
                const line = self.buffer[self.nextLineStart..newlineIndex];
                self.nextLineStart = newlineIndex+1;
                return line;
            }
        }
    }
};

const BufferedWriter = struct {
    const Self = @This();

    buffer: [WRITE_BUFFER_LEN]u8,
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
        if (self.len==WRITE_BUFFER_LEN) {
            try self.writer.writeAll(&self.buffer);
            self.len = 0;
        }
    }

    fn writeEscapedByte(self: *Self, byte:u8) !void {
        try switch (byte) {
            '&' => self.writeBytes("&amp"),
            '<' => self.writeBytes("&lt"),
            '>' => self.writeBytes("&gt"),
            '"' => self.writeBytes("&quot"),
            '\'' => self.writeBytes("&#39"),
            else => self.writeByte(byte),
        };
    }

    fn writeBytes(self: *Self, bytes: []const u8) !void {
        for (bytes) |byte| {
            try self.writeByte(byte);
        }
    }

    fn writeEscapedBytes(self: *Self, bytes: []const u8) !void {
        for (bytes) |byte| {
            try self.writeEscapedByte(byte);
        }
    }
};

const State = struct {
    bullets: bool = false,
    preformatted: bool = false,
};

fn handleLine(line: []const u8, writer: *BufferedWriter, state: *State) !void {
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
    var reader = try LineReader.init(allocator, inputFile.reader());
    var writer = BufferedWriter.init(std.io.getStdOut().writer());
    var state = State {};

    // Loops through lines
    while (try reader.readLine()) |line| {
        try handleLine(line, &writer, &state);
    }
    try writer.flush();
}
