const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    const program_name = args.next().?;

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
        } else if (std.mem.eql(u8, arg, "commit")) {
            if (args.next()) |msg| {
                try commit_full_working_dir(allocator, cwd, msg);
            } else {
                std.debug.print("fatal: missing message\n", .{});
                std.debug.print("usage: {s} commit <message>\n", .{program_name});
                return;
            }
        } else if (std.mem.eql(u8, arg, "log")) {
            try list_commits(allocator, cwd);
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

fn get_head(_: std.mem.Allocator, vec_dir: std.fs.Dir) !?[40]u8 {
    var head_file_buf: [64]u8 = undefined;
    const head_file = try vec_dir.openFile("HEAD", .{});
    var r = head_file.reader(&head_file_buf);
    var reader = &r.interface;
    const head = reader.peekArray(40) catch |err| {
        switch (err) {
            error.EndOfStream => { return null; },
            else => return err,
        }
    };
    var buf: [40]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    reader.toss(40);
    try w.print("{s}", .{head});
    try w.flush();
    return buf;
}

fn get_parent_commit(objs_dir: std.fs.Dir, commit: [40]u8) !?[40]u8 {
    var commit_file_buf: [128]u8 = undefined;
    var commit_file = try objs_dir.openFile(&commit, .{ .mode = .read_only });
    var r = commit_file.reader(&commit_file_buf);
    var reader = &r.interface;

    switch (try reader.peekByte()) {
        '\n' => return null,
        else => {}
    }
    const parent_commit = reader.peekArray(40) catch |err| {
        switch (err) {
            error.EndOfStream => { return null; },
            else => return err,
        }
    };
    var buf: [40]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    reader.toss(40);
    try w.print("{s}", .{parent_commit});
    try w.flush();
    return buf;
}

fn get_tree_for_commit(allocator: std.mem.Allocator, objs_dir: std.fs.Dir, commit: ?[40]u8) !?[]u8 {
    if (commit) |c| {
        var commit_file_buf: [128]u8 = undefined;
        var commit_file = try objs_dir.openFile(&c, .{ .mode = .read_only });
        var r = commit_file.reader(&commit_file_buf);
        var reader = &r.interface;

        _ = try reader.takeDelimiter('\n');
        if (try reader.takeDelimiter('\n')) |t| {
            return try allocator.dupe(u8, t);
        }
    }
    return null;
}

fn get_commit_message(allocator: std.mem.Allocator, objs_dir: std.fs.Dir, commit: [40]u8) ![]u8 {
    var commit_file_buf: [128]u8 = undefined;
    var commit_file = try objs_dir.openFile(&commit, .{ .mode = .read_only });
    var r = commit_file.reader(&commit_file_buf);
    var reader = &r.interface;

    _ = try reader.takeDelimiter('\n');
    _ = try reader.takeDelimiter('\n');
    return try reader.allocRemaining(allocator, .unlimited);
}

const ObjectKind = enum {
    blob,
    tree
};

const Object = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []u8,
    hash: [40]u8 = [1]u8{0} ** 40,
    kind: ObjectKind,

    children: []Self = &[0]Self{},
    parent: ?*Self = null,

    fn deinit(self: *Self) void {
        for (self.children) |*c| {
            c.deinit();
        }
        if (self.children.len > 0) self.allocator.free(self.children);
        if (self.name.len > 0) self.allocator.free(self.name);
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

    const head = try get_head(allocator, vec_dir);
    const tree = try get_tree_for_commit(allocator, objs_dir, head);
    defer if (tree) |t| allocator.free(t);

    var commit_tree = try construct_tree_from_hash(allocator, objs_dir, tree); 
    defer if (commit_tree) |*c| c.deinit();

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
        var root_obj = Object {.allocator = allocator, .name = &[0]u8{}, .kind = .tree };
        _ = try std.fmt.bufPrint(&root_obj.hash, "{s}", .{h});

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
                    var obj = Object {.allocator = allocator, .name = &[0]u8{}, .kind = obj_kind};
                    obj.name = try std.fmt.allocPrint(obj.allocator, "{s}", .{obj_name});
                    _ = try std.fmt.bufPrint(&obj.hash, "{s}", .{obj_hash});
                    try root_obj.add_child(obj);
                } else {
                    var obj = try construct_tree_from_hash(allocator, objs_dir, @constCast(obj_hash));
                    if (obj) |*o| {
                        o.name = try std.fmt.allocPrint(o.allocator, "{s}", .{obj_name});
                        try root_obj.add_child(o.*);
                    }
                }
            } else {
                break;
            }
        } else |err| {
            _ = err catch {};
        }
        return root_obj;
    }
    return null;
}

fn construct_tree_from_dir(allocator: std.mem.Allocator, parent: ?*Object, objs_dir: std.fs.Dir, name: []const u8, d: std.fs.Dir) !Object {
    var hasher = std.crypto.hash.Sha1.init(.{});

    var root_obj = Object {
        .allocator = allocator,
        .name = &[0]u8{},
        .kind = .tree,
    };

    if (parent) |_| {
        root_obj.name = try std.fmt.allocPrint(root_obj.allocator, "{s}/", .{name});
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
            if (obj.children.len > 0) {
                hasher.update(&obj.hash);
                try root_obj.add_child(obj);
            }
        } else if (e.kind == .file) {
            var f = try d.openFile(e.name, .{ .mode = .read_only });
            defer f.close();
            const obj = try get_file_obj(allocator, &root_obj, e.name, f);
            hasher.update(&obj.hash);
            try root_obj.add_child(obj);
        }

        entry = try it.next();
    }

    const hash_bytes = hasher.finalResult();
    const hash = std.fmt.bytesToHex(hash_bytes, .lower);
    _ = try std.fmt.bufPrint(&root_obj.hash, "{s}", .{hash});
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

    const hash_bytes = hasher.finalResult();
    const hash = std.fmt.bytesToHex(hash_bytes, .lower);

    var obj = Object {
        .allocator = allocator,
        .name = &[0]u8{},
        .kind = .blob,
        .parent = parent,
    };
    obj.name = try std.fmt.allocPrint(obj.allocator, "{s}", .{name});
    _ = try std.fmt.bufPrint(&obj.hash, "{s}", .{hash});

    return obj;
}

fn dump_obj(t: Object) void {
    std.debug.print("name: {s}\thash: {s}\n", .{t.name, t.hash});
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
        defer allocator.free(dp);
        for (0..dp.len) |i| {
            dp[i] = try allocator.alloc(u32, n+1);
            @memset(dp[i], 0);
        }
        defer for (0..dp.len) |i| allocator.free(dp[i]);

        for (1..m+1) |i| {
            for (1..n+1) |j| {
                if (std.mem.eql(u8, ct.children[i-1].name, current_tree.children[j-1].name)) {
                    dp[i][j] = dp[i-1][j-1] + 1;
                } else {
                    dp[i][j] = @max(dp[i-1][j], dp[i][j-1]);
                }
            }
        }

        var i = m;
        var j = n;
        while (i > 0 and j > 0) {
            if (i > 0 and j > 0 and std.mem.eql(u8, ct.children[i-1].name, current_tree.children[j-1].name)) {
                if (!std.mem.eql(u8, &ct.children[i-1].hash, &current_tree.children[j-1].hash)) {
                    if (current_tree.children[j-1].kind == .blob) {
                        try all_status.append(allocator, .{ .name = current_tree.children[j-1].name, .status = .modified });
                    } else if (current_tree.children[j-1].kind == .tree) {
                            try compare_current_tree_with_commit_tree(allocator, ct.children[i-1], current_tree.children[j-1], all_status);
                    }
                }
                i -= 1;
                j -= 1;
            } else if (j > 0 and (i == 0 or dp[i][j-1] >= dp[i-1][j])) {
                try all_status.append(allocator, .{ .name = current_tree.children[j-1].name, .status = .untracked });
                j -= 1;
            } else {
                try all_status.append(allocator, .{ .name = ct.children[i-1].name, .status = .deleted });
                i -= 1;
            }
        }
    } else {
        for (current_tree.children) |*c| {
            if (c.kind == .blob) {
                try all_status.append(allocator, .{ .name = c.name, .status = .untracked });
            } else if (c.kind == .tree) {
                try all_status.append(allocator, .{ .name = c.name, .status = .untracked });
            }
        }
    }
}

fn commit_full_working_dir(allocator: std.mem.Allocator, cwd: std.fs.Dir, msg: []const u8) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    var all_status = try std.ArrayList(ObjectStatus).initCapacity(allocator, 8);
    defer all_status.deinit(allocator);

    const head = try get_head(allocator, vec_dir);
    const tree = try get_tree_for_commit(allocator, objs_dir, head);
    defer if (tree) |t| allocator.free(t);

    var commit_tree = try construct_tree_from_hash(allocator, objs_dir, tree); 
    defer if (commit_tree) |*c| c.deinit();

    var current_tree = try construct_tree_from_dir(allocator, null, objs_dir, "", root_dir);
    defer current_tree.deinit();

    if (head) |h| if (std.mem.eql(u8, &h, &current_tree.hash)) return;
    try store_tree(root_dir, objs_dir, current_tree);
    const new_commit = try write_commit_obj(objs_dir, head, current_tree.hash, msg);
    try set_head(vec_dir, new_commit);
}

fn store_tree(working_dir: std.fs.Dir, objs_dir: std.fs.Dir, tree: Object) !void {
    const tree_file_name = tree.hash;
    if (objs_dir.access(&tree_file_name, .{})) {
        return;
    } else |err| {
        switch (err) {
            error.FileNotFound => {},
            else => return err
        }
    }
    var tree_file = try objs_dir.createFile(&tree_file_name, .{});
    tree_file.close();
    tree_file = try objs_dir.openFile(&tree_file_name, .{ .mode = .read_write });
    defer tree_file.close();
    var tree_buf: [1024]u8 = undefined;
    var tree_writer = tree_file.writer(&tree_buf);
    var tw = &tree_writer.interface;

    for (tree.children) |c| {
        try tw.print("{s} {s} {s}\n", .{@tagName(c.kind), c.name, c.hash});
        try tw.flush();
        if (c.kind == .tree) {
            var subdir = try working_dir.openDir(c.name, .{ .iterate = true });
            defer subdir.close();
            try store_tree(subdir, objs_dir, c);
        } else {
            const blob_file_name = c.hash;
            if (objs_dir.access(&blob_file_name, .{})) {
                return;
            } else |err| {
                switch (err) {
                    error.FileNotFound => {},
                    else => return err
                }
            }
            try std.fs.Dir.copyFile(working_dir, c.name, objs_dir, &blob_file_name, .{});
        }
    }
}

fn write_commit_obj(objs_dir: std.fs.Dir, prev_commit_hash: ?[40]u8, tree_hash: [40]u8, msg: []const u8) ![40]u8 {
    var hasher = std.crypto.hash.Sha1.init(.{});
    if (prev_commit_hash) |ph| hasher.update(&ph) else hasher.update(&[1]u8{0});
    hasher.update(&tree_hash);
    hasher.update(msg);
    const hash_bytes = hasher.finalResult();
    const hash = std.fmt.bytesToHex(hash_bytes, .lower);

    const file_name = hash;
    var f = try objs_dir.createFile(&file_name, .{});
    f.close();
    f = try objs_dir.openFile(&file_name, .{ .mode = .read_write });
    defer f.close();

    var buf: [1024]u8 = undefined;
    var writer = f.writer(&buf);
    var w = &writer.interface;

    if (prev_commit_hash) |ph| 
        try w.print("{s}\n", .{ph}) 
    else 
        try w.print("\n", .{});
    try w.print("{s}\n", .{tree_hash});
    try w.flush();
    try w.print("{s}\n", .{msg});
    try w.flush();
    return hash;
}

fn set_head(vec_dir: std.fs.Dir, new_head: [40]u8) !void {
    var head_file = try vec_dir.openFile("HEAD", .{ .mode = .read_write });
    defer head_file.close();

    var buf: [1024]u8 = undefined;
    var w = head_file.writer(&buf);
    var writer = &w.interface;

    try writer.print("{s}", .{new_head});
    try writer.flush();
}

fn list_commits(allocator: std.mem.Allocator, cwd: std.fs.Dir) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    const head = try get_head(allocator, vec_dir);
    if (head) |h| {
        var msg = try get_commit_message(allocator, objs_dir, h);
        std.debug.print("commit {s} (HEAD)\n", .{h});
        std.debug.print("   {s}\n", .{msg});
        allocator.free(msg);

        var it = try get_parent_commit(objs_dir, h);
        while (it) |commit| {
            msg = try get_commit_message(allocator, objs_dir, commit);
            defer allocator.free(msg);
            std.debug.print("commit {s}\n", .{commit});
            std.debug.print("   {s}\n", .{msg});
            it = try get_parent_commit(objs_dir, commit);
        } else {}
    }
}
