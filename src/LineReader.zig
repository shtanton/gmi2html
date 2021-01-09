const std = @import("std");
const Allocator = std.mem.Allocator;

const INITIAL_BUFFER_LEN = 2*1024;

pub const LineReader = struct {
    const Self = @This();

    buffer: []u8,
    reader: std.fs.File.Reader,
    allocator: *Allocator,
    nextLineStart: usize,
    len: usize,

    pub fn init(allocator: *Allocator, reader: std.fs.File.Reader) !Self {
        return Self {
            .buffer = try allocator.alloc(u8, INITIAL_BUFFER_LEN),
            .reader = reader,
            .allocator = allocator,
            .nextLineStart = 0,
            .len = 0,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.buffer);
    }

    pub fn readLine(self: *Self) !?[]const u8 {
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
