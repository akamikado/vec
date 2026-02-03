const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    var cwd = try std.fs.cwd().openDir(".", .{.iterate = true});
    defer cwd.close();

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "init")) {
            try init_vec_dir(cwd);
        } else if (std.mem.eql(u8, arg, "status")) {
            try check_status(allocator, cwd);
        } else {
            std.debug.print("fatal: unknown argument: {s}\n", .{arg});
            return;
        }
    }
}

fn get_root_dir(cwd: std.fs.Dir) !std.fs.Dir {
    var dir = cwd;
    var path_buf: [1024]u8 = undefined;
    var cwd_path = try dir.realpath(".", &path_buf);

    var found_root_dir = if(cwd.access(".vec/", .{.mode = .read_only})) |_| true else |_| false;
    while (!found_root_dir and !std.mem.eql(u8, cwd_path, "/")) {
        dir = try dir.openDir("..", .{});
        cwd_path = try dir.realpath(".", &path_buf);
        found_root_dir = if(dir.access(".vec/", .{.mode = .read_only})) |_| true else |_| false;
    }
    if (!found_root_dir) {
        std.debug.print("fatal: not found in current directory (or any of the parent directories): .vec\n", .{});
        return error.NotInitialized;
    } 

    return dir;
}

fn init_vec_dir(root_dir: std.fs.Dir) !void {
    root_dir.makeDir(".vec") catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err
        }
    };
    root_dir.makeDir(".vec/objects/") catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err
        }
    };
    _ = root_dir.createFile(".vec/HEAD", .{}) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err
        }
    };
}

const ObjectKind = enum {
    blob,
    tree
};

const Object = struct {
    name: []const u8,
    hash: []const u8,
    kind: ObjectKind,
};

const ObjectStatusKind = enum {
    unchanged,
    untracked,
    modified,
    deleted,
};

const ObjectStatus = struct {
    name: []const u8,
    kind: ObjectKind,
    status: ObjectStatusKind = .unchanged,
};


fn check_status(allocator: std.mem.Allocator, cwd: std.fs.Dir) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    var tree_obj: ?[]u8 = null;

    var head_file_buf: [32]u8 = undefined;
    const head_file = try vec_dir.openFile("HEAD", .{});
    var r1 = head_file.reader(&head_file_buf);
    var reader1 = &r1.interface;
    const head = try reader1.takeDelimiter('\n');
    if (head) |h| {
        std.debug.print("{s}\n", .{h});
        var commit_file_buf: [128]u8 = undefined;
        var commit_file = try objs_dir.openFile(h, .{ .mode = .read_only });
        var r2 = commit_file.reader(&commit_file_buf);
        var reader2 = &r2.interface;

        _ = try reader2.takeDelimiter('\n');
        tree_obj = try reader2.takeDelimiter('\n');
    }

    var all_status = try std.ArrayList(ObjectStatus).initCapacity(allocator, 8);
    defer all_status.deinit(allocator);

    try compare_objects(allocator, root_dir, objs_dir, tree_obj, &all_status);

    var untracked_objs = try std.ArrayList(usize).initCapacity(allocator, 8);
    defer untracked_objs.deinit(allocator);

    var modified_objs = try std.ArrayList(usize).initCapacity(allocator, 8);
    defer modified_objs.deinit(allocator);

    var deleted_objs = try std.ArrayList(usize).initCapacity(allocator, 8);
    defer deleted_objs.deinit(allocator);

    for (0..all_status.items.len) |i| {
        switch (all_status.items[i].status) {
            .untracked => try untracked_objs.append(allocator, i),
            .modified => try modified_objs.append(allocator, i),
            .deleted => try deleted_objs.append(allocator, i),
            else => {}
        }
    }

    if (modified_objs.items.len > 0) {
        std.debug.print("Modified files:\n", .{});
        for (modified_objs.items) |i| {
            std.debug.print("   {s}", .{all_status.items[i].name});
            if (all_status.items[i].kind == .tree) {
                std.debug.print("/", .{});
            }
            std.debug.print("\n", .{});
        }
    }

    if (untracked_objs.items.len > 0) {
        std.debug.print("Untracked files:\n", .{});
        for (untracked_objs.items) |i| {
            std.debug.print("   {s}", .{all_status.items[i].name});
            if (all_status.items[i].kind == .tree) {
                std.debug.print("/", .{});
            }
            std.debug.print("\n", .{});
        }
    }

    if (deleted_objs.items.len > 0) {
        std.debug.print("Deleted files:\n", .{});
        for (deleted_objs.items) |i| {
            std.debug.print("   {s}", .{all_status.items[i].name});
            if (all_status.items[i].kind == .tree) {
                std.debug.print("/", .{});
            }
            std.debug.print("\n", .{});
        }
    }
}

fn get_file_hash(f: std.fs.File) ![std.crypto.hash.Sha1.digest_length]u8 {
    var hasher = std.crypto.hash.Sha1.init(.{});

    var file_buf: [1024]u8 = undefined;
    var r = f.reader(&file_buf);
    var reader = &r.interface;

    while (reader.takeDelimiter('\n')) |line| {
        if (line) |l| {
            hasher.update(l);
        } else {
            break;
        }
    } else |err| {
        return err;
    }

    const hash = hasher.finalResult();
    return hash;
}

fn has_files(dir: std.fs.Dir) !bool {
    var it = dir.iterate();
    var entry = it.next() catch null;
    while (entry) |e| {
        if (e.kind == .file) {
            return true;
        } else if (e.kind == .directory) {
            var subdir = try dir.openDir(e.name, .{ .iterate = true });
            defer subdir.close();
            if (has_files(subdir)) |b| {
                if (b) return true;
            } else |err| {
                return err;
            }
        }
        entry = it.next() catch null;
    }
    return false;
}

fn compare_objects(allocator: std.mem.Allocator, root_dir: std.fs.Dir, objs_dir: std.fs.Dir, tree_obj_name: ?[]u8, all_status: *std.ArrayList(ObjectStatus)) !void {
    if (tree_obj_name) |name| {
        var tree_obj = try objs_dir.openFile(name, .{});
        defer tree_obj.close();

        var file_buf: [1024]u8 = undefined;
        var r = tree_obj.reader(&file_buf);
        var reader = &r.interface;

        var objects = try std.ArrayList(Object).initCapacity(allocator, 16);
        defer objects.deinit(allocator);

        var visited = try std.ArrayList(bool).initCapacity(allocator, 16);
        defer visited.deinit(allocator);

        while (reader.takeDelimiter('\n')) |line| {
            if (line) |l| {
                var it = std.mem.splitScalar(u8, l, ' ');
                const obj_type_name = it.next().?;
                var obj_kind: ObjectKind = undefined;
                if (std.mem.eql(u8, obj_type_name, "blob")) {
                    obj_kind = .blob;
                } else if (std.mem.eql(u8, obj_type_name, "tree")) {
                    obj_kind = .tree;
                }
                const obj_name = it.next().?;
                const obj_hash = it.next().?;

                const obj = Object {.name = obj_name, .kind = obj_kind, .hash = obj_hash};
                try objects.append(allocator, obj);
                try visited.append(allocator, false);
            }
        } else |err| {
            _ = err catch {};
        }

        var it = root_dir.iterate();
        var entry = try it.next();
        while (entry) |e| {
            if (std.mem.eql(u8, e.name, ".vec")) {
                entry = try it.next();
                continue;
            }
            if (e.kind == .directory) {
                var idx: ?usize = null;
                for (0..all_status.items.len) |i| {
                    if (std.mem.eql(u8, e.name, objects.items[i].name) and objects.items[i].kind == .tree) {
                        idx = i;
                        break;
                    }
                }

                var dir = try root_dir.openDir(e.name, .{.iterate = true});
                defer dir.close();

                var path_buf: [1024]u8 = undefined;
                const path = try dir.realpath(".", &path_buf);
                if (idx) |i| {
                    if (has_files(dir)) |b| {
                        if (!b) {
                            try all_status.append(allocator, .{ .name =  path, .kind = .tree, .status = .deleted });
                            continue;
                        }

                        try compare_objects(allocator, root_dir, objs_dir, @constCast(objects.items[i].hash), all_status);
                    } else |err| { return err; }
                } else {
                    try all_status.append(allocator, .{ .name =  path, .kind = .tree, .status = .untracked });
                }
            } else if (e.kind == .file) {
                var idx: ?usize = null;
                for (0..all_status.items.len) |i| {
                    if (std.mem.eql(u8, e.name, objects.items[i].name) and objects.items[i].kind == .blob) {
                        idx = i;
                        break;
                    }
                }
                if (idx) |i| {
                    visited.items[i] = true;

                    var file = try root_dir.openFile(e.name, .{});
                    defer file.close();

                    const cur_hash = try get_file_hash(file);
                    if (!std.mem.eql(u8, &cur_hash, objects.items[i].hash)) {
                        var path_buf: [1024]u8 = undefined;
                        const path = try root_dir.realpath(e.name, &path_buf);
                        try all_status.append(allocator, .{ .name =  path, .kind = .blob, .status = .modified });
                    }
                } else {
                    try all_status.append(allocator, .{ .name =  e.name, .kind = .blob, .status = .untracked });
                }
            }

            entry = try it.next();
        }

        for (0..objects.items.len) |i| {
            if (!visited.items[i]) {
                try all_status.append(allocator, .{ .name =  objects.items[i].name, .kind = .tree, .status = .deleted });
            }
        }
    } else {
        var it = root_dir.iterate();
        var entry = try it.next();
        while (entry) |e| {
            if (std.mem.eql(u8, e.name, ".vec")) {
                entry = try it.next();
                continue;
            }
            if (e.kind == .directory) {
                var dir = try root_dir.openDir(e.name, .{.iterate = true});
                defer dir.close();
                if (has_files(dir)) |b| {
                    if (b) try all_status.append(allocator, .{ .name =  e.name, .kind = .tree, .status = .untracked });
                } else |err| {
                    return err;
                }
            } else if (e.kind == .file) {
                try all_status.append(allocator, .{ .name =  e.name, .kind = .blob, .status = .untracked });
            }

            entry = try it.next();
        }
    }
}
