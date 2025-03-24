const std: type = @import("std");
const rl: type = @import("raylib");

const STARPATCH_VERSION: u8 = 1;

const PatchType: type = enum(u8) {
    add,
    delete,
    modify,
};

const PatchError: type = error{
    OriginalCRC32Mismatched,
    OriginalFileSizeMismatched,
    PatchedCRC32Mismatched,
    PatchedFileSizeMismatched,
    ReadBufferFailed,
    SaveFailed,
    WrongByte,
    WrongHeader,
    WrongVersion,
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

    var buffer: std.ArrayListAligned(u8, null) = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    _ = try buffer.writer().write("STARPATCH");

    try buffer.append(STARPATCH_VERSION);

    try write32bits(&buffer, @as(u32, @intCast(originalData.len)));
    try write32bits(&buffer, @as(u32, @intCast(patchedData.len)));

    const originalCrc: u32 = std.hash.crc.Crc32.hash(originalData);
    const patchedCrc: u32 = std.hash.crc.Crc32.hash(patchedData);

    try write32bits(&buffer, originalCrc);
    try write32bits(&buffer, patchedCrc);

    var i: u32 = 0;

    while (i < originalData.len) {
        const byteOriginal: u8 = originalData[i];

        if (i < patchedData.len) {
            const bytePatched: u8 = patchedData[i];

            if (bytePatched != byteOriginal) {
                try write32bits(&buffer, i);

                try buffer.append(@intFromEnum(PatchType.modify));

                try buffer.append(byteOriginal);
                try buffer.append(bytePatched);
            }
        } else {
            try write32bits(&buffer, i);

            try buffer.append(@intFromEnum(PatchType.delete));

            try buffer.append(byteOriginal);
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

    var header: [10]u8 = .{0} ** 10;

    while (i < header.len) {
        header[i] = try read8bits(&patchData, &i);
    }

    if (std.mem.eql(u8, header[0..10], "STARPATCH")) {
        return PatchError.WrongHeader;
    }

    if (header[header.len - 1] != STARPATCH_VERSION) {
        return PatchError.WrongVersion;
    }

    const originalSize: u32 = try read32bits(&patchData, &i);
    const patchedSize: u32 = try read32bits(&patchData, &i);

    if (originalData.len != originalSize) {
        return PatchError.OriginalFileSizeMismatched;
    }

    const originalCrc: u32 = std.hash.crc.Crc32.hash(originalData);
    const originalCrcInPatch: u32 = try read32bits(&patchData, &i);

    if (originalCrc != originalCrcInPatch) {
        return PatchError.OriginalCRC32Mismatched;
    }

    const patchedCrcInPatch: u32 = try read32bits(&patchData, &i);

    var patchedData: std.ArrayListAligned(u8, null) = std.ArrayList(u8).init(allocator);
    defer patchedData.deinit();

    try patchedData.resize(originalData.len);

    @memcpy(patchedData.items, originalData);

    applyPatch: {
        while (i < patchData.len) {
            const address: u32 = try read32bits(&patchData, &i);
            const action: PatchType = @as(PatchType, @enumFromInt(try read8bits(&patchData, &i)));

            switch (action) {
                .add => {
                    try patchedData.append(try read8bits(&patchData, &i));
                },
                .delete => {
                    patchedData.shrinkAndFree(address);

                    break :applyPatch;
                },
                .modify => {
                    const originalByte: u8 = try read8bits(&patchData, &i);

                    if (patchedData.items[address] != originalByte) {
                        return PatchError.WrongByte;
                    }

                    patchedData.items[address] = try read8bits(&patchData, &i);
                },
            }
        }
    }

    if (patchedData.items.len != patchedSize) {
        return PatchError.PatchedFileSizeMismatched;
    }

    const patchedCrc: u32 = std.hash.crc.Crc32.hash(patchedData.items);

    if (patchedCrc != patchedCrcInPatch) {
        return PatchError.PatchedCRC32Mismatched;
    }

    if (!rl.saveFileData(patchedFileName, patchedData.items)) {
        return PatchError.SaveFailed;
    }
}

pub fn applyUnpatch(allocator: std.mem.Allocator, patchedFileName: [*:0]const u8, patchFileName: [*:0]const u8, originalFileName: [*:0]const u8) anyerror!void {
    const patchedData: []u8 = try rl.loadFileData(patchedFileName);
    defer rl.unloadFileData(patchedData);

    const patchData: []u8 = try rl.loadFileData(patchFileName);
    defer rl.unloadFileData(patchData);

    var i: u32 = 0;

    var header: [10]u8 = .{0} ** 10;

    while (i < header.len) {
        header[i] = try read8bits(&patchData, &i);
    }

    if (std.mem.eql(u8, header[0..10], "STARPATCH")) {
        return PatchError.WrongHeader;
    }

    if (header[header.len - 1] != STARPATCH_VERSION) {
        return PatchError.WrongVersion;
    }

    const originalSize: u32 = try read32bits(&patchData, &i);
    const patchedSize: u32 = try read32bits(&patchData, &i);

    if (patchedData.len != patchedSize) {
        return PatchError.PatchedFileSizeMismatched;
    }

    const originalCrcInPatch: u32 = try read32bits(&patchData, &i);

    const patchedCrc: u32 = std.hash.crc.Crc32.hash(patchedData);
    const patchedCrcInPatch: u32 = try read32bits(&patchData, &i);

    if (patchedCrc != patchedCrcInPatch) {
        return PatchError.PatchedCRC32Mismatched;
    }

    var originalData: std.ArrayListAligned(u8, null) = std.ArrayList(u8).init(allocator);
    defer originalData.deinit();

    try originalData.resize(patchedData.len);

    @memcpy(originalData.items, patchedData);

    applyUnpatch: {
        while (i < patchData.len) {
            const address: u32 = try read32bits(&patchData, &i);
            const action: PatchType = @as(PatchType, @enumFromInt(try read8bits(&patchData, &i)));

            switch (action) {
                .add => {
                    originalData.shrinkAndFree(address);

                    break :applyUnpatch;
                },
                .delete => {
                    try originalData.append(try read8bits(&patchData, &i));
                },
                .modify => {
                    const originalByte: u8 = try read8bits(&patchData, &i);
                    const patchedByte: u8 = try read8bits(&patchData, &i);

                    if (originalData.items[address] != patchedByte) {
                        return PatchError.WrongByte;
                    }

                    originalData.items[address] = originalByte;
                },
            }
        }
    }

    if (originalData.items.len != originalSize) {
        return PatchError.OriginalFileSizeMismatched;
    }

    const originalCrc: u32 = std.hash.crc.Crc32.hash(originalData.items);

    if (originalCrc != originalCrcInPatch) {
        return PatchError.OriginalCRC32Mismatched;
    }

    if (!rl.saveFileData(originalFileName, originalData.items)) {
        return PatchError.SaveFailed;
    }
}

pub fn help(args: [][:0]u8) anyerror!void {
    const fileName: [*:0]const u8 = rl.getFileName(args[0]);

    _ = try std.io.getStdOut().write("Usage:\n");

    try std.io.getStdOut().writer().print("\t{s} create  <original file> <patched file> <output patch file>\n", .{fileName});
    try std.io.getStdOut().writer().print("\t{s} patch   <original file> <patch file> <output patched file>\n", .{fileName});
    try std.io.getStdOut().writer().print("\t{s} unpatch <patched file> <patch file> <output original file>\n", .{fileName});
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
    const isUnpatch: bool = std.mem.eql(u8, args[1], "unpatch");

    if (!isCreate and !isPatch and !isUnpatch) {
        try help(args);

        return 1;
    }

    if (!rl.isPathFile(args[2]) or !rl.isPathFile(args[3])) {
        try help(args);

        return 1;
    }

    if (rl.isPathFile(args[4])) {
        _ = try std.io.getStdErr().write("Output file already exists\n");

        return 1;
    }

    rl.setTraceLogLevel(.err);

    if (isCreate) {
        createPatch(gpa_allocator, args[2], args[3], args[4]) catch |createError| switch (createError) {
            PatchError.SaveFailed => {
                _ = try std.io.getStdErr().write("Error saving patch file\n");
            },
            else => {
                _ = try std.io.getStdErr().writer().print("Error while creating patch: {any}\n", .{createError});
            },
        };
    } else if (isPatch) {
        applyPatch(gpa_allocator, args[2], args[3], args[4]) catch |patchError| switch (patchError) {
            PatchError.OriginalCRC32Mismatched => {
                _ = try std.io.getStdErr().write("Original file's CRC32 does not match the patch's expected CRC32\n");
            },
            PatchError.OriginalFileSizeMismatched => {
                _ = try std.io.getStdErr().write("Original file's size does not match the patch's expected file size\n");
            },
            PatchError.PatchedCRC32Mismatched => {
                _ = try std.io.getStdErr().write("Patched file's CRC32 does not match the patch's expected CRC32\n");
            },
            PatchError.PatchedFileSizeMismatched => {
                _ = try std.io.getStdErr().write("Patched file's size does not match the patch's expected file size\n");
            },
            PatchError.SaveFailed => {
                _ = try std.io.getStdErr().write("Error saving patched file\n");
            },
            PatchError.WrongByte => {
                _ = try std.io.getStdErr().write("Wrong original byte found while applying the patch\n");
            },
            PatchError.WrongHeader => {
                _ = try std.io.getStdErr().write("Patch file has wrong header\n");
            },
            PatchError.WrongVersion => {
                _ = try std.io.getStdErr().write("Patch file has wrong version\n");
            },
            else => {
                _ = try std.io.getStdErr().writer().print("Error while applying patch: {any}\n", .{patchError});
            },
        };
    } else if (isUnpatch) {
        applyUnpatch(gpa_allocator, args[2], args[3], args[4]) catch |patchError| switch (patchError) {
            PatchError.OriginalCRC32Mismatched => {
                _ = try std.io.getStdErr().write("Original file's CRC32 does not match the patch's expected CRC32\n");
            },
            PatchError.OriginalFileSizeMismatched => {
                _ = try std.io.getStdErr().write("Original file's size does not match the patch's expected file size\n");
            },
            PatchError.PatchedCRC32Mismatched => {
                _ = try std.io.getStdErr().write("Patched file's CRC32 does not match the patch's expected CRC32\n");
            },
            PatchError.PatchedFileSizeMismatched => {
                _ = try std.io.getStdErr().write("Patched file's size does not match the patch's expected file size\n");
            },
            PatchError.SaveFailed => {
                _ = try std.io.getStdErr().write("Error saving unpatched file\n");
            },
            PatchError.WrongByte => {
                _ = try std.io.getStdErr().write("Wrong patched byte found while applying the unpatch\n");
            },
            PatchError.WrongHeader => {
                _ = try std.io.getStdErr().write("Patch file has wrong header\n");
            },
            PatchError.WrongVersion => {
                _ = try std.io.getStdErr().write("Patch file has wrong version\n");
            },
            else => {
                _ = try std.io.getStdErr().writer().print("Error while applying unpatch: {any}\n", .{patchError});
            },
        };
    } else {
        unreachable;
    }

    return 0;
}
