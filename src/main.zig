const std: type = @import("std");
const rl: type = @import("raylib");

const PatchType: type = enum(u8) {
    add,
    delete,
    modify,
};

const PatchError: type = error{
    SaveFailed,
    ReadBufferFailed,
    CRC32Mismatched,
    FileSizeMismatched,
};

pub fn read8bits(buffer: *const []u8, i: *u32) anyerror!u8 {
    var result: u8 = 0;

    if (i.* >= buffer.len) {
        return PatchError.ReadBufferFailed;
    }

    result = buffer.*[i.*];

    i.* += 1;

    return result;
}

pub fn read32bits(buffer: *const []u8, i: *u32) anyerror!u32 {
    var result: u32 = 0;

    if (i.* + 4 >= buffer.len) {
        return PatchError.ReadBufferFailed;
    }

    result |= @as(u32, buffer.*[i.* + 0]) << 24;
    result |= @as(u32, buffer.*[i.* + 1]) << 16;
    result |= @as(u32, buffer.*[i.* + 2]) << 8;
    result |= @as(u32, buffer.*[i.* + 3]) << 0;

    i.* += 4;

    return result;
}

pub fn write32bits(buffer: *std.ArrayListAligned(u8, null), number: u32) anyerror!void {
    try buffer.append(@as(u8, @intCast((number >> 24) & 0xFF)));
    try buffer.append(@as(u8, @intCast((number >> 16) & 0xFF)));
    try buffer.append(@as(u8, @intCast((number >> 8) & 0xFF)));
    try buffer.append(@as(u8, @intCast((number >> 0) & 0xFF)));
}

pub fn createPatch(allocator: std.mem.Allocator, originalFileName: [*:0]const u8, patchedFileName: [*:0]const u8, patchFileName: [*:0]const u8) anyerror!void {
    const originalData: []u8 = try rl.loadFileData(originalFileName);
    defer rl.unloadFileData(originalData);

    const patchedData: []u8 = try rl.loadFileData(patchedFileName);
    defer rl.unloadFileData(patchedData);

    const originalCrc: u32 = std.hash.crc.Crc32.hash(originalData);

    var buffer: std.ArrayListAligned(u8, null) = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try write32bits(&buffer, originalCrc);
    try write32bits(&buffer, @as(u32, @intCast(originalData.len)));

    var i: u32 = 0;

    while (i < originalData.len) {
        const byteOriginal: u8 = originalData[i];

        if (i < patchedData.len) {
            const bytePatched: u8 = patchedData[i];

            if (bytePatched != byteOriginal) {
                try write32bits(&buffer, i);

                try buffer.append(@intFromEnum(PatchType.modify));

                try buffer.append(bytePatched);
            }
        } else {
            try write32bits(&buffer, i);

            try buffer.append(@intFromEnum(PatchType.delete));

            break;
        }

        i += 1;
    }

    while (i < patchedData.len) {
        const byteToAdd: u8 = patchedData[i];

        try write32bits(&buffer, i);

        try buffer.append(@intFromEnum(PatchType.add));
        try buffer.append(byteToAdd);

        i += 1;
    }

    if (!rl.saveFileData(patchFileName, buffer.items)) {
        return PatchError.SaveFailed;
    }
}

pub fn applyPatch(allocator: std.mem.Allocator, originalFileName: [*:0]const u8, patchFileName: [*:0]const u8, patchedFileName: [*:0]const u8) anyerror!void {
    const originalData: []u8 = try rl.loadFileData(originalFileName);
    defer rl.unloadFileData(originalData);

    const patchData: []u8 = try rl.loadFileData(patchFileName);
    defer rl.unloadFileData(patchData);

    var i: u32 = 0;

    const originalCrc: u32 = std.hash.crc.Crc32.hash(originalData);
    const patchCrc: u32 = try read32bits(&patchData, &i);

    if (originalCrc != patchCrc) {
        return PatchError.CRC32Mismatched;
    }

    const originalSize: u32 = try read32bits(&patchData, &i);

    if (originalData.len != originalSize) {
        return PatchError.FileSizeMismatched;
    }

    var patchedData: std.ArrayListAligned(u8, null) = std.ArrayList(u8).init(allocator);
    defer patchedData.deinit();

    try patchedData.resize(originalData.len);

    @memcpy(patchedData.items, originalData);

    while (i < patchData.len) {
        const address: u32 = try read32bits(&patchData, &i);
        const action: PatchType = @as(PatchType, @enumFromInt(try read8bits(&patchData, &i)));

        switch (action) {
            .add => {
                try patchedData.append(try read8bits(&patchData, &i));
            },
            .delete => {
                patchedData.shrinkAndFree(address);
            },
            .modify => {
                patchedData.items[address] = try read8bits(&patchData, &i);
            },
        }
    }

    if (!rl.saveFileData(patchedFileName, patchedData.items)) {
        return PatchError.SaveFailed;
    }
}

pub fn help(args: [][:0]u8) anyerror!void {
    const fileName: [*:0]const u8 = rl.getFileName(args[0]);

    _ = try std.io.getStdOut().write("Usage:\n");

    try std.io.getStdOut().writer().print("\t{s} create <original file> <patched file> <output patch file>\n", .{fileName});
    try std.io.getStdOut().writer().print("\t{s} patch  <original file> <patch file> <output patched file>\n", .{fileName});
}

pub fn main() anyerror!u8 {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const gpa_allocator: std.mem.Allocator = gpa.allocator();

    const args: [][:0]u8 = try std.process.argsAlloc(gpa_allocator);
    defer std.process.argsFree(gpa_allocator, args);

    if (args.len != 5) {
        try help(args);

        return 1;
    }

    const isCreate: bool = std.mem.eql(u8, args[1], "create");
    const isPatch: bool = std.mem.eql(u8, args[1], "patch");

    if (!isCreate and !isPatch) {
        try help(args);

        return 1;
    }

    if (!rl.isPathFile(args[2]) or !rl.isPathFile(args[3])) {
        try help(args);

        return 1;
    }

    if (rl.isPathFile(args[4])) {
        _ = try std.io.getStdOut().write("Output file already exists\n");

        return 1;
    }

    rl.setTraceLogLevel(.err);

    if (isCreate) {
        try createPatch(gpa_allocator, args[2], args[3], args[4]);
    } else if (isPatch) {
        try applyPatch(gpa_allocator, args[2], args[3], args[4]);
    } else {
        unreachable;
    }

    return 0;
}
