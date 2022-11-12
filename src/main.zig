const std = @import("std");
const clap = @import("clap");
const io = std.io;
const mem = std.mem;
const format = std.fmt.comptimePrint;

fn trimSize(allocator: std.mem.Allocator, data: []u8) ![]u8 {
    var zero_counter: usize = 0;
    var index = data.len - 1;
    while (index != 0) : (index -= 1) {
        if (data[index] == '0') {
            zero_counter += 1;
        } else if (zero_counter > 1 and data[index] != 'x') {
            zero_counter = 0;
        } else if (data[index] == 'x' and zero_counter > 1) {
            index -= 1;
            break;
        }
    }

    return allocator.realloc(data, index);
}

fn removeZeroes(allocator: std.mem.Allocator, data: []u8) ![]u8 {
    var len: usize = data.len - 1;
    while (len != 0) : (len -= 1) {
        if (data[len] == '0') {
            break;
        }
    }

    return try allocator.realloc(data, len);
}

fn formatStringToHex(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    const as_int: ?usize = std.fmt.parseUnsigned(usize, data, 0) catch null;

    if (as_int) |int| {
        const new_str = try std.fmt.allocPrint(allocator, "{s}", .{std.mem.toBytes(int)});
        defer allocator.free(new_str);
        const this = try std.fmt.allocPrint(allocator, "{d}", .{std.fmt.fmtSliceHexUpper(new_str)});
        return try removeZeroes(allocator, this);
    } else {
        const this = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexUpper(data)});
        return this;
    }
}

const ParsedValue = struct {
    const Self = @This();
    value: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) !Self {
        return Self{
            .value = try formatStringToHex(allocator, data),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.value);
    }
};

const BytePair = struct {
    left: u8,
    right: ?u8 = null,
};

fn getValues(alloc: mem.Allocator, values: ?[]const u8) ![]ParsedValue {
    if (values == null) {
        return error.NoValues;
    }
    const len = mem.count(u8, values.?, " ") + 1;

    var tokens = mem.tokenize(u8, values.?, " ");
    var results = try alloc.alloc(ParsedValue, len);

    var i: usize = 0;
    while (tokens.next()) |token| {
        results[i] = try ParsedValue.init(alloc, token);
    }
    return results[0..];
}

fn toLittleEndian(allocator: mem.Allocator, data: ParsedValue) ![]const u8 {
    if (data.value.len < 1) {
        return error.NoData;
    }

    const byte_pair_size = data.value.len / 2 + (data.value.len % 2);
    const byte_pairs = try allocator.alloc(BytePair, byte_pair_size);
    defer allocator.free(byte_pairs);

    var index = @as(usize, 0);
    var pair_idx = @as(usize, 0);
    const upper = std.ascii.toUpper;
    while (index < data.value.len) : ({
        index += 2;
        pair_idx += 1;
    }) {
        const current_pair = &byte_pairs[pair_idx];
        current_pair.left = upper(data.value[index]);
        current_pair.right = if (index + 1 < data.value.len) upper(data.value[index + 1]) else null;
    }

    const as_little_endian = try allocator.alloc(u8, (byte_pairs.len * 4));
    index = 0;
    for (byte_pairs) |*pair| {
        if (pair.left == '0' and pair.right orelse '1' == '0') {
            continue;
        }
        if (pair.right == null) {
            pair.right = '0';
        }

        mem.copy(u8, as_little_endian[index..], "\\x");
        as_little_endian[index + 2] = pair.left;
        as_little_endian[index + 3] = pair.right.?;
        index += 4;
    }
    return allocator.realloc(as_little_endian, byte_pairs.len * 4);
}

fn convert(allocator: mem.Allocator, values: []ParsedValue) ![]const u8 {
    var required_bytes: usize = 0;
    for (values) |value, i| {
        const len = value.value.len;
        required_bytes = len * 2 + (@boolToInt(i > 0) * 1);
    }

    var converted = try allocator.alloc(u8, required_bytes + (required_bytes % 4));
    var last: usize = 0;
    for (values) |value, i| {
        const this = try toLittleEndian(allocator, value);
        defer allocator.free(this);

        mem.copy(u8, converted[last..], this);
        if (i + 1 < values.len) {
            last += this.len - 1;
            converted[last] = ' ';
            last += 1;
        }
    }

    return try trimSize(allocator, converted);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    const param_list =
        \\-h, --help                    Display this help and exit.
        \\-v, --version                 Output version information and exit.
        \\    [<str>|<hex>|<dec>|<bin>] The input to be converted.
        \\
    ;

    const params = [_]clap.Param(u8){
        .{
            .id = 'h',
            .names = .{ .short = 'h', .long = "help" },
        },
        .{
            .id = 'v',
            .names = .{ .short = 'v', .long = "version" },
        },
        .{
            .id = 'x',
            .names = .{},
            .takes_value = .many,
        },
    };
    var iter = try std.process.ArgIterator.initWithAllocator(alloc);
    defer iter.deinit();

    // skip filepath
    _ = iter.next();

    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    const stdout = std.io.getStdOut().writer();
    defer stdout.writeAll("\n") catch {};
    while (parser.next() catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    }) |arg| {
        switch (arg.param.id) {
            'h' => try stdout.writeAll(param_list),
            'v' => try stdout.writeAll(format("Version is currently: {s}\n", .{"0.0.0a"})),
            'x' => {
                const parsed_values = try getValues(alloc, arg.value.?);
                defer for (parsed_values) |*elem| elem.deinit();

                const converted = try convert(alloc, parsed_values);
                try stdout.writeAll(converted);
            },
            else => unreachable,
        }
    }
}
