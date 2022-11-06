const std = @import("std");
const clap = @import("clap");
const io = std.io;
const mem = std.mem;
const format = std.fmt.comptimePrint;

const DataType = enum {
    dec,
    hex,
    bin,
    str,
};

const ParsedValue = struct {
    value: []const u8,
    type: DataType,
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
        const firstByte = token[0];
        if (firstByte == '\'') {
            results[i] = ParsedValue{
                .value = token[1..],
                .type = DataType.str,
            };
            continue;
        }
        const firstTwoBytes = token[0..];
        if (mem.eql(u8, firstTwoBytes, "0x")) {
            results[i] = ParsedValue{
                .value = token[2..],
                .type = DataType.hex,
            };
        } else if (mem.eql(u8, firstTwoBytes, "0b")) {
            results[i] = ParsedValue{
                .value = token[2..],
                .type = DataType.bin,
            };
        } else {
            results[i] = ParsedValue{
                .value = token,
                .type = DataType.dec,
            };
        }
        i += 1;
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

    mem.reverse(BytePair, byte_pairs);
    const as_little_endian = try allocator.alloc(u8, (byte_pairs.len * 4));
    index = 0;
    for (byte_pairs) |*pair| {
        if (pair.right == null) {
            pair.right = '0';
            mem.swap(u8, &(pair.right.?), &pair.left);
        }

        mem.copy(u8, as_little_endian[index..], "\\x");
        as_little_endian[index + 2] = pair.left;
        as_little_endian[index + 3] = pair.right.?;
        index += 4;
    }

    return as_little_endian;
}

fn convert(allocator: mem.Allocator, values: []ParsedValue) ![]const u8 {
    var required_bytes: usize = 0;
    for (values) |value| {
        const len = value.value.len;
        required_bytes = len * 2;
    }

    var converted = try allocator.alloc(u8, required_bytes + (required_bytes % 4));
    var last: usize = 0;
    for (values) |value| {
        const this = try toLittleEndian(allocator, value);
        defer allocator.free(this);

        mem.copy(u8, converted[last..], this);
        last += value.value.len + 2;
    }

    return converted;
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
                defer alloc.free(parsed_values);

                const converted_val = try convert(alloc, parsed_values);
                defer alloc.free(converted_val);
                try stdout.writeAll(converted_val);
            },
            else => unreachable,
        }
    }
}
