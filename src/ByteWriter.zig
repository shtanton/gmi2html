const std = @import("std");

const BUFFER_LEN = 2*1024;

pub const ByteWriter = struct {
    const Self = @This();

    buffer: [BUFFER_LEN]u8,
    writer: std.fs.File.Writer,
    len: usize,

    pub fn init(writer: std.fs.File.Writer) Self {
        return Self {
            .buffer = undefined,
            .writer = writer,
            .len = 0,
        };
    }

    pub fn flush(self: *Self) !void {
        if (self.len!=0) {
            try self.writer.writeAll(self.buffer[0..self.len]);
            self.len = 0;
        }
    }

    pub fn writeByte(self: *Self, byte: u8) !void {
        self.buffer[self.len] = byte;
        self.len += 1;
        if (self.len==BUFFER_LEN) {
            try self.writer.writeAll(&self.buffer);
            self.len = 0;
        }
    }

    pub fn writeEscapedByte(self: *Self, byte:u8) !void {
        try switch (byte) {
            '&' => self.writeBytes("&amp"),
            '<' => self.writeBytes("&lt"),
            '>' => self.writeBytes("&gt"),
            '"' => self.writeBytes("&quot"),
            '\'' => self.writeBytes("&#39"),
            else => self.writeByte(byte),
        };
    }

    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        for (bytes) |byte| {
            try self.writeByte(byte);
        }
    }

    pub fn writeEscapedBytes(self: *Self, bytes: []const u8) !void {
        for (bytes) |byte| {
            try self.writeEscapedByte(byte);
        }
    }
};
