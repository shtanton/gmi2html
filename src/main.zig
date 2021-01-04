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

fn handleLine(line: []u8, writer: std.io.Writer(std.fs.File, std.os.WriteError, std.fs.File.write), state: *State) !void {
    if (line.len >= 1 and line[0] == '*' and !state.bullets) {
        state.bullets = true;
        try writer.print("<ul>\n", .{});
    } else if (state.bullets and (line.len == 0 or line[0] != '*')) {
        state.bullets = false;
        try writer.print("</ul>\n", .{});
    }
    if (state.preformatted) {
        if (line.len >= 3 and line[0] == '`' and line[1] == '`' and line[2] == '`') {
            state.preformatted = false;
            return writer.print("</pre>\n", .{});
        } else {
            return writer.print("{}\n", .{line});
        }
    }
    if (line.len >= 3) {
        if (line[0] == '#' and line[1] == '#' and line[2] == '#') {
            return writer.print("<h3>{}</h3>\n", .{trimLeft(line[3..])});
        }
        if (line[0] == '`' and line[1] == '`' and line[2] == '`') {
            state.preformatted = true;
            const altText = trimLeft(line[3..]);
            if (altText.len == 0) {
                return writer.print("<pre>\n", .{});
            } else {
                return writer.print("<pre alt=\"{}\">\n", .{altText});
            }
        }
    }
    if (line.len >= 2) {
        if (line[0] == '#' and line[1] == '#') {
            return writer.print("<h2>{}</h2>\n", .{trimLeft(line[2..])});
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
            return writer.print("<a href=\"{}\">{}</a><br/>\n", .{url, text});
        }
    }
    if (line.len >= 1) {
        if (line[0] == '#') {
            return writer.print("<h1>{}</h1>\n", .{trimLeft(line[1..])});
        }
        if (line[0] == '*') {
            return writer.print("<li>{}</li>\n", .{trimLeft(line[1..])});
        }
        if (line[0] == '>') {
            return writer.print("<blockquote>{}</blockquote>\n", .{trimLeft(line[1..])});
        }
    }
    return writer.print("{}<br/>\n", .{trimLeft(line)});
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
    while (progress < inputContents.len) : ({
        progress = lineEnd + 1;
        lineEnd = progress;
    }) {
        while (lineEnd < inputContents.len and inputContents[lineEnd] != '\n') : (lineEnd += 1) {}

        try handleLine(inputContents[progress..lineEnd], stdout.writer(), &state);
    }
}
