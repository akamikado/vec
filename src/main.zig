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

fn get_head(vec_dir: std.fs.Dir) !?[]u8 {
    var head_file_buf: [32]u8 = undefined;
    const head_file = try vec_dir.openFile("HEAD", .{});
    var r1 = head_file.reader(&head_file_buf);
    var reader1 = &r1.interface;
    const head = try reader1.takeDelimiter('\n');
    return head;
}

fn get_tree_for_commit(objs_dir: std.fs.Dir, commit: ?[]const u8) !?[]u8 {
    if (commit) |c| {
        var commit_file_buf: [128]u8 = undefined;
        var commit_file = try objs_dir.openFile(c, .{ .mode = .read_only });
        var r2 = commit_file.reader(&commit_file_buf);
        var reader2 = &r2.interface;

        _ = try reader2.takeDelimiter('\n');
        const tree_obj = try reader2.takeDelimiter('\n');
        return tree_obj;
    }
    return null;
}

const ObjectKind = enum {
    blob,
    tree
};

const Object = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: [256]u8,
    hash: [20]u8,
    kind: ObjectKind,

    children: []Self = &[0]Self{},
    parent: ?*Self = null,

    fn deinit(self: *Self) void {
        for (self.children) |*c| {
            c.deinit();
        }
        if (self.children.len > 0) self.allocator.free(self.children);
    }

    fn add_child(self: *Self, child: Object) !void {
        self.children = try self.allocator.realloc(self.children, self.children.len+1);
        self.children[self.children.len-1] = child;
    }

    fn delete_child(self: *Self, index: usize) !bool {
        if (index >= self.children.len) return false;
        self.children[index].deinit();
        var new_children = try self.allocator.alloc(Object, self.children.len-1);
        @memcpy(new_children[0..index], self.children[0..index]);
        @memcpy(new_children[index..], self.children[index+1..]);
        self.allocator.free(self.children);
        self.children = new_children;
        return true;
    }
};

const ObjectStatusKind = enum {
    unchanged,
    untracked,
    modified,
    deleted,
};

const ObjectStatus = struct {
    name: []const u8,
    status: ObjectStatusKind = .unchanged,
};


fn check_status(allocator: std.mem.Allocator, cwd: std.fs.Dir) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    var all_status = try std.ArrayList(ObjectStatus).initCapacity(allocator, 8);
    defer all_status.deinit(allocator);

    const head = try get_head(vec_dir);
    const tree = try get_tree_for_commit(objs_dir, head);

    var commit_tree = try construct_tree_from_hash(allocator, objs_dir, tree); 
    defer if (commit_tree) |*c| {
        c.deinit();
    };

    var current_tree = try construct_tree_from_dir(allocator, null, objs_dir, "", root_dir);
    defer current_tree.deinit();

    try compare_current_tree_with_commit_tree(allocator, commit_tree, current_tree, &all_status);

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
            std.debug.print("   {s}\n", .{all_status.items[i].name});
        }
    }

    if (untracked_objs.items.len > 0) {
        std.debug.print("Untracked files:\n", .{});
        for (untracked_objs.items) |i| {
            std.debug.print("   {s}\n", .{all_status.items[i].name});
        }
    }

    if (deleted_objs.items.len > 0) {
        std.debug.print("Deleted files:\n", .{});
        for (deleted_objs.items) |i| {
            std.debug.print("   {s}\n", .{all_status.items[i].name});
        }
    }
}

fn construct_tree_from_hash(allocator: std.mem.Allocator, objs_dir: std.fs.Dir, hash: ?[]u8) !?Object {
    if (hash) |h| {
        var root_node = Object {.allocator = allocator, .hash = [1]u8{0} ** 20, .name = [1]u8{0} ** 256, .kind = .tree };

        var tree_file = try objs_dir.openFile(h, .{ .mode = .read_only });
        defer tree_file.close();

        var file_buf: [1024]u8 = undefined;
        var r = tree_file.reader(&file_buf);
        var reader = &r.interface;

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

                if (obj_kind == .blob) {
                    const obj = Object {.allocator = allocator, .name = [1]u8{0} ** 256, .kind = obj_kind, .hash = [1]u8{0} ** 20};
                    _ = try std.fmt.bufPrint(@constCast(&obj.name), "{s}", .{obj_name});
                    _ = try std.fmt.bufPrint(@constCast(&obj.hash), "{s}", .{obj_hash});
                    try root_node.add_child(obj);
                } else {
                    const obj = try construct_tree_from_hash(allocator, objs_dir, @constCast(obj_hash));
                    if (obj) |o| {
                        try root_node.add_child(o);
                    }
                }
            }
        } else |err| {
            _ = err catch {};
        }
    }
    return null;
}

fn construct_tree_from_dir(allocator: std.mem.Allocator, parent: ?*Object, objs_dir: std.fs.Dir, name: []const u8, d: std.fs.Dir) !Object {
    var hasher = std.crypto.hash.Sha1.init(.{});

    var root_obj = Object {
        .allocator = allocator,
        .name = [1]u8{0} ** 256,
        .kind = .tree,
        .hash = [1]u8{0} ** 20,
    };

    if (parent) |_| {
        _ = try std.fmt.bufPrint(@constCast(&root_obj.name), "{s}/", .{name});
    } else {
        @memset(@constCast(&root_obj.name), 0);
    }

    var it = d.iterate();
    var entry = try it.next();
    while (entry) |e| {
        if (std.mem.eql(u8, e.name, ".vec")) {
            entry = try it.next();
            continue;
        }
        if (e.kind == .directory) {
            var subdir = try d.openDir(e.name, .{.iterate = true});
            defer subdir.close();
            const obj = try construct_tree_from_dir(allocator, &root_obj, objs_dir, e.name, subdir);
            hasher.update(&obj.hash);
            try root_obj.add_child(obj);
        } else if (e.kind == .file) {
            var f = try d.openFile(e.name, .{ .mode = .read_only });
            defer f.close();
            const obj = try get_file_obj(allocator, &root_obj, e.name, f);
            hasher.update(&obj.hash);
            try root_obj.add_child(obj);
        }

        entry = try it.next();
    }

    const hash = hasher.finalResult();
    _ = try std.fmt.bufPrint(@constCast(&root_obj.hash), "{s}", .{hash});
    root_obj.parent = parent;

    return root_obj;
}

fn get_file_obj(allocator: std.mem.Allocator, parent: ?*Object, name: []const u8, f: std.fs.File) !Object {
    var hasher = std.crypto.hash.Sha1.init(.{});

    var file_buf: [1024]u8 = undefined;
    var r = f.reader(&file_buf);
    var reader = &r.interface;

    while (true) {
        if (reader.fill(1024)) {
            hasher.update(reader.buffer);
            reader.toss(1024);
        } else |err| {
            if (err == error.EndOfStream) break;
            return err;
        }
    }
    const remaining = reader.buffered();
    hasher.update(remaining);

    const hash = hasher.finalResult();

    var obj = Object {
        .allocator = allocator,
        .name = [1]u8{0} ** 256,
        .kind = .blob,
        .hash = [1]u8{0} ** 20,
        .parent = parent,
    };
    _ = try std.fmt.bufPrint(@constCast(&obj.name), "{s}", .{name});
    _ = try std.fmt.bufPrint(@constCast(&obj.hash), "{s}", .{hash});

    return obj;
}

fn dump_obj(t: Object) void {
    std.debug.print("name: {s}\thash: {s}\n", .{t.name, std.fmt.bytesToHex(t.hash, .upper)});
    for (t.children) |c| {
        dump_obj(c);
    }
}

fn compare_current_tree_with_commit_tree(allocator: std.mem.Allocator, commit_tree: ?Object, current_tree: Object, all_status: *std.ArrayList(ObjectStatus)) !void {
    if (commit_tree) |ct| {
        if (std.mem.eql(u8, &ct.hash, &current_tree.hash)) return;

        const m = ct.children.len;
        const n = current_tree.children.len;
        var dp = try allocator.alloc([]u32, m+1);
        for (0..dp.len) |i| {
            dp[i] = try allocator.alloc(u32, n+1);
            @memset(dp[i], 0);
        }

        for (1..m+1) |i| {
            for (1..n+1) |j| {
                if (std.mem.eql(u8, &ct.children[i-1].name, &current_tree.children[j-1].name) and ct.children[i-1].kind == current_tree.children[j-1].kind) {
                    dp[i][j] = dp[i-1][j-1] + 1;
                } else {
                    dp[i][j] = @max(dp[i-1][j], dp[i][j-1]);
                }
            }
        }

        var i = m;
        var j = n;
        while (i > 0 and j > 0) {
            if (i > 0 and j > 0 and std.mem.eql(u8, &ct.children[i-1].name, &current_tree.children[j-1].name) and ct.children[i-1].kind == current_tree.children[j-1].kind) {
                if (!std.mem.eql(u8, &ct.children[i-1].hash, &current_tree.children[j-1].hash)) {
                    if (current_tree.children[j-1].kind == .blob) {
                        try all_status.append(allocator, .{ .name = &current_tree.children[j-1].name, .status = .modified });
                    } else if (current_tree.children[j-1].kind == .tree) {
                        if (current_tree.children[j-1].children.len > 0) {
                            try compare_current_tree_with_commit_tree(allocator, ct.children[i-1], current_tree.children[j-1], all_status);
                        } else {
                            try all_status.append(allocator, .{ .name = &current_tree.children[j-1].name, .status = .deleted });
                        }
                    }
                }
                i -= 1;
                j -= 1;
            } else if (j > 0 and (i == 0 or dp[i][j-1] >= dp[i-1][j])) {
                try all_status.append(allocator, .{ .name = &current_tree.children[j-1].name, .status = .untracked });
                j -= 1;
            } else {
                try all_status.append(allocator, .{ .name = &ct.children[i-1].name, .status = .deleted });
                i -= 1;
            }
        }
    } else {
        for (current_tree.children) |*c| {
            if (c.kind == .blob) {
                try all_status.append(allocator, .{ .name = &c.name, .status = .untracked });
            } else if (c.kind == .tree) {
                if (c.children.len > 0) try all_status.append(allocator, .{ .name = &c.name, .status = .untracked });
            }
        }
    }
}
