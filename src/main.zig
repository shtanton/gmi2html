const std = @import("std");
const LineReader = @import("LineReader.zig").LineReader;
const ByteWriter = @import("ByteWriter.zig").ByteWriter;

const imageExtensions = [_][]const u8{
    ".png",
    ".jpeg",
    ".jpg",
    ".gif",
    ".webp",
};
const videoExtensions = [_][]const u8{
    ".mp4",
};
const audioExtensions = [_][]const u8{
    ".mp3",
    ".wav",
    ".ogg",
};
const HTTPS_SCHEME = "https";

fn trimLeft(str: []const u8) []const u8 {
    return std.mem.trimLeft(u8, str, &[_]u8{' ', '\t'});
}

fn isWebUrl(url: []const u8) bool {
    const scheme = for (url) |char, i| {
        if (char == ':') {
            break url[0..i];
        } else if (char == '/') {
            return true;
        }
    } else return true;
    if (scheme.len > 5 or scheme.len < 4) {
        return false;
    }
    for (scheme) |char, i| {
        if (std.ascii.toLower(char) != HTTPS_SCHEME[i]) {
            return false;
        }
    }
    return true;
}

fn matchesExtension(url: []const u8, extensions: []const []const u8) bool {
    for (extensions) |extension| {
        if (url.len >= extension.len and std.mem.eql(u8, url[url.len-extension.len..], extension)) {
            return true;
        }
    }
    return false;
}

const State = struct {
    bullets: bool = false,
    preformatted: bool = false,
    inlineImages: bool = false,
    inlineVideo: bool = false,
    inlineAudio: bool = false,
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
            while (spaceIndex < contents.len) : (spaceIndex += 1) {
                if (contents[spaceIndex] == ' ' or contents[spaceIndex] == '\t') break;
            }
            const url = contents[0..spaceIndex];
            var text = trimLeft(contents[spaceIndex..]);
            if (text.len == 0) {
                text = url;
            }
            if (state.inlineImages and isWebUrl(url) and matchesExtension(url, &imageExtensions)) {
                try writer.writeBytes("<a style=\"display: block;\" href=\"");
                try writer.writeEscapedBytes(url);
                try writer.writeBytes("\">");
                try writer.writeBytes("<img src=\"");
                try writer.writeEscapedBytes(url);
                try writer.writeBytes("\" alt=\"");
                try writer.writeEscapedBytes(text);
                try writer.writeBytes("\"/>");
                try writer.writeBytes("</a>\n");
            } else if (state.inlineVideo and isWebUrl(url) and matchesExtension(url, &videoExtensions)) {
                try writer.writeBytes("<video style=\"display: block;\" controls src=\"");
                try writer.writeEscapedBytes(url);
                try writer.writeBytes("\"><a src=\"");
                try writer.writeEscapedBytes(url);
                try writer.writeBytes("\">");
                try writer.writeEscapedBytes(text);
                try writer.writeBytes("</a></video>\n");
            } else if (state.inlineAudio and isWebUrl(url) and matchesExtension(url, &audioExtensions)) {
                try writer.writeBytes("<audio style=\"display: block;\" controls src=\"");
                try writer.writeEscapedBytes(url);
                try writer.writeBytes("\"><a src=\"");
                try writer.writeEscapedBytes(url);
                try writer.writeBytes("\">");
                try writer.writeEscapedBytes(text);
                try writer.writeBytes("</a></audio>\n");
            } else if (isWebUrl(url)) {
                try writer.writeBytes("<a style=\"display: block;\" href=\"");
                try writer.writeEscapedBytes(url);
                try writer.writeBytes("\">");
                try writer.writeEscapedBytes(text);
                try writer.writeBytes("</a>\n");
            } else {
                try writer.writeBytes("<p>");
                try writer.writeEscapedBytes(line);
                return writer.writeBytes("</p>\n");
            }
            return;
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
    try writer.writeBytes("<p>");
    if (line.len == 0) {
        try writer.writeBytes("<br/>");
    } else {
        try writer.writeEscapedBytes(line);
    }
    return writer.writeBytes("</p>\n");
}

const help =
    \\Usage: gmi2html [options]
    \\
    \\Reads text/gemini from stdin and writes HTML to stdout.
    \\
    \\Options:
    \\--inline-images        Translate links to images as <img> elements
    \\--inline-video         Translate links to videos as <video> elements
    \\--inline-audio         Translate links to audio as <audio> elements
    \\--inline-all           Short for --inline-images --inline-video --inline-audio
    \\--help                 Display this message
    \\--version              Display version
    \\
;

pub fn main() anyerror!u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    var args = std.process.args();
    defer args.deinit();
    _ = args.skip();
    var state = State {};
    const stderr = std.io.getStdErr().writer();
    const stdout = std.io.getStdOut().writer();

    while (args.next(allocator)) |maybeArg| {
        const arg = try maybeArg;
        if (std.mem.eql(u8, arg, "--inline-images")) {
            state.inlineImages = true;
        } else if (std.mem.eql(u8, arg, "--inline-video")) {
            state.inlineVideo = true;
        } else if (std.mem.eql(u8, arg, "--inline-audio")) {
            state.inlineAudio = true;
        } else if (std.mem.eql(u8, arg, "--inline-all")) {
            state.inlineImages = true;
            state.inlineVideo = true;
            state.inlineAudio = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(help);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.writeAll("gmi2html v0.4.0\n");
            return 0;
        } else {
            try stderr.print("Unrecognized option: {s}\n\n", .{arg});
            try stderr.writeAll(help);
            return 1;
        }
    }

    var reader = try LineReader.init(allocator, std.io.getStdIn().reader());
    var writer = ByteWriter.init(stdout);

    while (try reader.readLine()) |line| {
        try handleLine(line, &writer, &state);
    }
    try writer.flush();
    return 0;
}
