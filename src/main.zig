const std = @import("std");
const clap = @import("clap");

const io = std.io;
const mem = std.mem;
const format = std.fmt.comptimePrint;

const Allocator = mem.Allocator;

var pad_style = "\\x00";

fn trimSize(allocator: Allocator, data: []u8) ![]u8 {
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

    if (index != 0) {
        return allocator.realloc(data, index);
    } else {
        return data;
    }
}

fn removeZeroes(allocator: Allocator, data: []u8) ![]u8 {
    var len: usize = data.len - 1;
    while (len != 0) : (len -= 1) {
        if (data[len] == '0') {
            break;
        }
    }

    return try allocator.realloc(data, len);
}

fn formatStringToHex(allocator: Allocator, data: []const u8) ![]const u8 {
    const as_int: ?usize = std.fmt.parseUnsigned(usize, data, 0) catch null;

    if (as_int) |int| {
        const new_str = try std.fmt.allocPrint(allocator, "{s}", .{mem.toBytes(int)});
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
    allocator: Allocator,

    pub fn init(allocator: Allocator, data: []const u8) !Self {
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

fn getValues(alloc: Allocator, values: ?[]const u8) !ParsedValue {
    if (values == null) {
        return error.NoValues;
    }
    return try ParsedValue.init(alloc, values.?);
}

fn toLittleEndian(allocator: Allocator, data: ParsedValue) ![]u8 {
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

fn convert(allocator: Allocator, value: ParsedValue) ![]u8 {
    const this = try toLittleEndian(allocator, value);
    return trimSize(allocator, this);
}

fn addPad(allocator: Allocator, buffer: []u8, size: usize) ![]u8 {
    defer allocator.free(buffer);
    var new = try allocator.alloc(u8, buffer.len + 4 * size);
    mem.copyForwards(u8, new[0..(buffer.len)], buffer);
    mem.copyForwards(u8, new[buffer.len..], pad_style);
    return new;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    const param_list =
        \\-h, --help                    Display this help and exit.
        \\-v, --version                 Output version information and exit.
        \\-p, --padding                 The padding of \x00 before the conversion bytes.
        \\-b, --base                    The length of the cyclic "base" pattern.
        \\    [<str>|<hex>|<dec>|<bin>] The input to be converted, radix is decided on prefix.
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
            .id = 'n',
            .names = .{ .short = 'n', .long = "use_nop" },
        },
        .{
            .id = 'p',
            .names = .{ .short = 'p', .long = "padding" },
        },
        .{
            .id = 'b',
            .names = .{ .short = 'b', .long = "base" },
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
    var went_through = false;
    var padding: usize = 0;
    var cyclic: usize = 0;
    var res: []u8 = undefined;
    defer stdout.writeAll("\n") catch {};
    while (parser.next() catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    }) |arg| {
        switch (arg.param.id) {
            'h' => {
                try stdout.print("{s}\n", .{param_list});
                std.os.exit(0);
            },
            'v' => try stdout.print("Version is currently: {s}\n", .{"0.0.2"}), // cba with versioning just yet...
            'p' => {
                if (padding != 0) {
                    std.log.err("Please put the conversion value at last.", .{});
                    std.os.exit(1);
                }
                std.debug.print("Reached padding: {}", .{went_through});
                padding = try std.fmt.parseUnsigned(usize, arg.value.?, 0);
                continue;
            },
            'b' => {
                if (cyclic != 0) {
                    std.log.err("Please put the conversion value at last.", .{});
                    std.os.exit(1);
                }
                std.debug.print("Reached cyclic: {}", .{cyclic});
                cyclic = try std.fmt.parseUnsigned(usize, arg.value.?, 0);
                continue;
            },
            'n' => {
                std.debug.print("Reached style: {}", .{cyclic});
                pad_style = if (mem.eql(u8, pad_style, arg.value.?)) pad_style else "\\x90";
                continue;
            },
            'x' => {
                var parsed_value = try getValues(alloc, arg.value.?);
                defer parsed_value.deinit();

                const converted = try convert(alloc, parsed_value);
                res = converted;
                continue;
            },
            else => unreachable,
        }

        try stdout.print("{s}\n", .{res});
    }
}
