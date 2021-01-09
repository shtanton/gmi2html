const std = @import("std");
const process = std.process;
const Allocator = std.mem.Allocator;

const READ_BUFFER_LEN = 256;
const WRITE_BUFFER_LEN = 256;

fn trimLeft(str: []const u8) []const u8 {
    return std.mem.trimLeft(u8, str, &[_]u8{' ', '\t'});
}

const BufferedReader = struct {
    const Self = @This();

    buffer: [READ_BUFFER_LEN]u8,
    reader: std.fs.File.Reader,
    index: usize,
    len: usize,

    fn init(reader: std.fs.File.Reader) Self {
        return Self {
            .buffer = undefined,
            .reader = reader,
            .index = READ_BUFFER_LEN,
            .len = 0,
        };
    }

    fn readByte(self: *Self) !?u8 {
        if (self.index >= self.len) {
            self.len = try self.reader.readAll(&self.buffer);
            if (self.len == 0) {
                return null;
            }
            self.index = 0;
        }
        self.index += 1;
        return self.buffer[self.index-1];
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

const State = enum {
    LineStart,
    BulletLineStart,
};

/// Copies reader into writer while escaping it until it finds a \n or EOF
/// returns true if \n and false if EOF
fn handleLine(reader: *BufferedReader, writer: *BufferedWriter) !bool {
    while (try reader.readByte()) |byte| {
        if (byte=='\n') {
            return true;
        } else {
            try writer.writeEscapedByte(byte);
        }
    }
    return false;
}

/// Ignore any whitespace and return the first non-whitespace character
/// returns null if there is only whitespace
fn skipWhitespace(reader: *BufferedReader) !?u8 {
    while (try reader.readByte()) |byte| {
        if (byte!=' ' and byte!='\t') {
            return byte;
        }
    }
    return null;
}

/// Like handleLine but ignores whitespace at the start
fn handleLineSkippingWhitespace(reader: *BufferedReader, writer: *BufferedWriter) !bool {
    if (try skipWhitespace(reader)) |firstByte| {
        if (firstByte=='\n') {
            return true;
        } else {
            try writer.writeEscapedByte(firstByte);
            return handleLine(reader, writer);
        }
    } else {
        return false;
    }
}

/// Translates a link starting with the reader positioned after =>
/// Returns false if eof is reached during execution
fn handleLink(allocator: *Allocator, reader: *BufferedReader, writer: *BufferedWriter) !bool {
    var addressBuffer = try allocator.alloc(u8, 64);
    defer allocator.free(addressBuffer);
    var bytesRead: usize = 0;
    try writer.writeBytes("<a href=\"");
    if (try skipWhitespace(reader)) |firstByte| {
        if (firstByte=='\n') {
            try writer.writeBytes("\"></a>\n");
            return true;
        }
        bytesRead = 1;
        try writer.writeEscapedByte(firstByte);
        addressBuffer[0] = firstByte;
    } else {
        try writer.writeBytes("\"></a>");
        return false;
    }
    while (try reader.readByte()) |byte| {
        switch (byte) {
            ' ', '\t' => {
                break;
            },
            '\n' => {
                try writer.writeBytes("\">");
                try writer.writeEscapedBytes(addressBuffer[0..bytesRead]);
                try writer.writeBytes("</a>\n");
                return true;
            },
            else => {
                try writer.writeEscapedByte(byte);
                if (bytesRead >= addressBuffer.len) {
                    addressBuffer = try allocator.realloc(addressBuffer, addressBuffer.len*2);
                }
                addressBuffer[bytesRead] = byte;
                bytesRead += 1;
            },
        }
    } else {
        try writer.writeBytes("\">");
        try writer.writeEscapedBytes(addressBuffer[0..bytesRead]);
        try writer.writeBytes("</a>");
        return false;
    }
    try writer.writeBytes("\">");
    if (try skipWhitespace(reader)) |firstByte| {
        if (firstByte=='\n') {
            try writer.writeEscapedBytes(addressBuffer[0..bytesRead]);
            try writer.writeBytes("</a>\n");
            return true;
        } else {
            try writer.writeEscapedByte(firstByte);
        }
    } else {
        try writer.writeEscapedBytes(addressBuffer[0..bytesRead]);
        try writer.writeBytes("</a>");
        return false;
    }
    const newline = try handleLine(reader, writer);
    try writer.writeBytes("</a>");
    if (newline) {
        try writer.writeByte('\n');
    }
    return newline;
}

fn handlePreformat(reader: *BufferedReader, writer: *BufferedWriter) !void {
}

fn handleHeader(n: u8, reader: *BufferedReader, writer: *BufferedWriter) !void {
}

fn handleBullet(reader: *BufferedReader, writer: *BufferedWriter) !void {
}

fn handleQuote(reader: *BufferedReader, writer: *BufferedWriter) !void {
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
    var reader = BufferedReader.init(inputFile.reader());
    var writer = BufferedWriter.init(std.io.getStdOut().writer());
    var state: State = .LineStart;

    while (try reader.readByte()) |byte| {
        switch (state) {
            .LineStart => switch (byte) {
                '\n' => {
                    try writer.writeBytes("<br/>\n");
                },
                '=' => {
                    if (try reader.readByte()) |nextByte| {
                        if (nextByte == '>') {
                            if (!try handleLink(allocator, &reader, &writer)) {
                                break;
                            }
                        } else if (nextByte == '\n') {
                            try writer.writeBytes("=<br/>\n");
                        } else {
                            try writer.writeByte('=');
                            try writer.writeEscapedByte(nextByte);
                            if (!try handleLine(&reader, &writer)) {
                                break;
                            }
                        }
                    } else {
                        try writer.writeByte('=');
                        break;
                    }
                },
                '`' => {
                    if (try reader.readByte()) |nextByte1| {
                        if (nextByte1=='`') {
                            if (try reader.readByte()) |nextByte2| {
                                if (nextByte2=='`') {
                                    try handlePreformat(&reader, &writer);
                                } else if (nextByte2=='\n') {
                                    try writer.writeBytes("``<br/>");
                                } else {
                                    try writer.writeBytes("``");
                                    try writer.writeEscapedByte(nextByte2);
                                    if (!try handleLine(&reader, &writer)) {
                                        break;
                                    }
                                }
                            } else {
                                try writer.writeBytes("``");
                                break;
                            }
                        } else if (nextByte1=='\n') {
                            try writer.writeBytes("`<br/>");
                        } else {
                            try writer.writeByte('`');
                            try writer.writeEscapedByte(nextByte1);
                            if (!try handleLine(&reader, &writer)) {
                                break;
                            }
                        }
                    } else {
                        try writer.writeByte('`');
                        break;
                    }
                },
                '#' => {
                    if (try reader.readByte()) |nextByte1| {
                        if (nextByte1=='#') {
                            if (try reader.readByte()) |nextByte2| {
                                if (nextByte2=='#') {
                                    try handleHeader('3', &reader, &writer);
                                } else {
                                    try handleHeader('2', &reader, &writer);
                                }
                            } else {
                                try writer.writeBytes("<h2></h2>");
                                break;
                            }
                        } else {
                            try handleHeader('1', &reader, &writer);
                        }
                    } else {
                        try writer.writeBytes("<h1></h1>");
                        break;
                    }
                },
                '*' => {
                    try writer.writeBytes("<ul>\n<li>");
                    const newline = try handleLine(&reader, &writer);
                    try writer.writeBytes("</li>\n");
                    if (!newline) {
                        try writer.writeBytes("</ul>");
                        break;
                    }
                    state = .BulletLineStart;
                },
                '>' => {
                    try handleQuote(&reader, &writer);
                },
                else => {
                    try writer.writeEscapedByte(byte);
                    if (!try handleLineSkippingWhitespace(&reader, &writer)) {
                        break;
                    }
                    try writer.writeBytes("<br/>\n");
                },
            },
            .BulletLineStart => {
                if (byte=='*') {
                    try writer.writeBytes("<li>");
                    const newline = try handleLineSkippingWhitespace(&reader, &writer);
                    try writer.writeBytes("</li>\n");
                    if (!newline) {
                        try writer.writeBytes("</ul>");
                        break;
                    }
                } else if (byte=='\n') {
                    try writer.writeBytes("</ul>\n<br/>\n");
                    state = .LineStart;
                } else {
                    try writer.writeBytes("</ul>\n");
                    try writer.writeEscapedByte(byte);
                    if (!try handleLine(&reader, &writer)) {
                        break;
                    }
                }
            },
        }
    }
    try writer.flush();
}
