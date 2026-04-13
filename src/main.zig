const std     = @import("std");
const debug   = std.debug;
const mem     = std.mem;
const fs      = std.fs;
const heap    = std.heap;
const crypto  = std.crypto;
const process = std.process;
const fmt     = std.fmt;
const math    = std.math;
const sort    = std.sort;

pub fn main() !void {
    var args = process.args();
    _ = args.next();

    var cwd = try fs.cwd().openDir(".", .{.iterate = true});
    defer cwd.close();

    var gpa = heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (args.next()) |arg| {
        if (mem.eql(u8, arg, "init")) {
            if (args.next()) |cmd| {
                if (!mem.eql(u8, cmd, "-h") and !mem.eql(u8, cmd, "--help")) 
                    debug.print("fatal: unknown command {s}\n", .{cmd});
                debug.print("usage: vec init\n", .{});
                return;
            }
            try init_vec_dir(cwd);
        } else if (mem.eql(u8, arg, "status")) {
            if (args.next()) |cmd| {
                if (!mem.eql(u8, cmd, "-h") and !mem.eql(u8, cmd, "--help")) 
                    debug.print("fatal: unknown command {s}\n", .{cmd});
                debug.print("usage: vec status\n", .{});
                return;
            }
            try check_status(allocator, cwd);
        } else if (mem.eql(u8, arg, "diff")) {
            if (args.next()) |arg2| {
                if (args.next()) |arg3| {
                    try compare_commits(allocator, cwd, arg2, arg3);
                } else {
                    if (mem.eql(u8, arg2, "-h") or mem.eql(u8, arg2, "--help")) {
                        debug.print("usage: vec diff <file>\n", .{});
                        debug.print("       vec diff <commit> <commit>\n", .{});
                        return;
                    }
                    _ = try compare_path_with_index(allocator, cwd, arg2, false);
                }
            } else {
                debug.print("fatal: missing file path argument\n", .{});
                debug.print("usage: vec diff <file>\n", .{});
                debug.print("       vec diff <commit> <commit>\n", .{});
                return;
            }
        } else if (mem.eql(u8, arg, "add")) {
            const arg2 = args.next();
            if (arg2) |cmd| {
                if (mem.eql(u8, cmd, "-h") or mem.eql(u8, cmd, "--help")) {
                    debug.print("usage: vec add <path>\n", .{});
                    return;
                }
                try add_to_index(allocator, cwd, cmd);
            } else {
                debug.print("fatal: missing path argument\n", .{});
                debug.print("usage: vec add <path>\n", .{});
                return;
            }
        } else if (mem.eql(u8, arg, "restore")) {
            if (args.next()) |arg2| {
                if (mem.eql(u8, arg2, "-h") or mem.eql(u8, arg2, "--help")) {
                    debug.print("usage: vec restore <file>\n", .{});
                    debug.print("       vec restore --staged <file>\n", .{});
                    return;
                } else if (mem.eql(u8, arg2, "--staged")) {
                    if (args.next()) |arg3| {
                        // TODO: allow for directories
                        try restore_index_for_file(allocator, cwd, arg3);
                    } else {
                        debug.print("fatal: missing file path argument\n", .{});
                        debug.print("usage: vec restore --staged <file>\n", .{});
                    }
                    return;
                } else {
                    // TODO: allow for restore of directories
                    try restore_file(allocator, cwd, arg2);
                }
            } else {
                debug.print("fatal: missing file path argument\n", .{});
                debug.print("usage: vec restore <file>\n", .{});
                debug.print("       vec restore --staged <file>\n", .{});
                return;
            }
        } else if (mem.eql(u8, arg, "commit")) {
            if (args.next()) |arg2| {
                if (mem.eql(u8, arg2, "-h") or mem.eql(u8, arg2, "--help")) {
                    debug.print("usage: vec log\n", .{});
                    return;
                }
                try snapshot_index(allocator, cwd, arg2);
            } else {
                debug.print("fatal: missing message\n", .{});
                debug.print("usage: vec commit <message>\n", .{});
                return;
            }
        } else if (mem.eql(u8, arg, "log")) {
            if (args.next()) |cmd| {
                if (!mem.eql(u8, cmd, "-h") and !mem.eql(u8, cmd, "--help")) 
                    debug.print("fatal: unknown command {s}\n", .{cmd});
                debug.print("usage: vec log\n", .{});
                return;
            }
            try list_commits(allocator, cwd);
        } else if (mem.eql(u8, arg, "reset")) {
            if (args.next()) |arg2| {
                if (mem.eql(u8, arg2, "-h") or mem.eql(u8, arg2, "--help")) {
                    debug.print("usage: vec reset <commit hash>\n", .{});
                    debug.print("       vec reset --soft <commit hash>\n", .{});
                    debug.print("       vec reset --mixed <commit hash>\n", .{});
                    debug.print("       vec reset --hard <commit hash>\n", .{});
                    return;
                } else if (mem.eql(u8, arg2, "--soft")) {
                    if (args.next()) |arg3| {
                        try reset_soft(cwd, arg3);
                    } else {
                        debug.print("fatal: missing commit hash argument\n", .{});
                        debug.print("usage: vec reset --soft <commit hash>\n", .{});
                        return;
                    }
                } else if (mem.eql(u8, arg2, "--hard")) {
                    if (args.next()) |arg3| {
                        try reset_hard(allocator, cwd, arg3);
                    } else {
                        debug.print("fatal: missing commit hash argument\n", .{});
                        debug.print("usage: vec reset --hard <commit hash>\n", .{});
                        return;
                    }
                } else {
                    try reset_mixed(allocator, cwd, arg2);
                }
            } else {
                debug.print("fatal: missing commit hash argument\n", .{});
                debug.print("usage: vec reset <commit hash>\n", .{});
                return;
            }
        } else if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "help")) {
            const help_str = 
                \\usage: vec <command> [<args>]
                \\
                \\Available commands:
                \\  init:    Create a working area
                \\  status:  Show the working tree status
                \\  diff:    Show changes between working tree and commit
                \\  add:     Add file contents to index
                \\  restore: Restore working tree files
                \\  commit:  Record changes to the working area
                \\  log:     Show commit logs
                \\  reset:   Reset current HEAD to specified state
            ;
            debug.print("{s}\n", .{help_str});
        } else {
            debug.print("fatal: unknown argument: {s}\n", .{arg});
            return;
        }
    }
}

fn get_root_dir(cwd: fs.Dir) !fs.Dir {
    var dir = cwd;
    var path_buf: [1024]u8 = undefined;
    var cwd_path = try dir.realpath(".", &path_buf);

    var found_root_dir = if(cwd.access(".vec/", .{.mode = .read_only})) |_| true else |_| false;
    while (!found_root_dir and !mem.eql(u8, cwd_path, "/")) {
        dir = try dir.openDir("..", .{.iterate = true});
        cwd_path = try dir.realpath(".", &path_buf);
        found_root_dir = if(dir.access(".vec/", .{.mode = .read_only})) |_| true else |_| false;
    }
    if (!found_root_dir) {
        debug.print("fatal: not found in current directory (or any of the parent directories): .vec\n", .{});
        return error.NotInitialized;
    } 

    return dir;
}

fn init_vec_dir(root_dir: fs.Dir) !void {
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
    _ = root_dir.createFile(".vec/INDEX", .{}) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err
        }
    };
}

fn get_head(vec_dir: fs.Dir) !?[40]u8 {
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

fn get_parent_commit(objs_dir: fs.Dir, commit: [40]u8) !?[40]u8 {
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

fn get_tree_for_commit(allocator: mem.Allocator, objs_dir: fs.Dir, commit: ?[40]u8) !?[]u8 {
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

fn get_commit_message(allocator: mem.Allocator, objs_dir: fs.Dir, commit: [40]u8) ![]u8 {
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

    allocator: mem.Allocator,
    name: []u8,
    hash: [40]u8 = [1]u8{0} ** 40,
    kind: ObjectKind,

    children: []Self = &[0]Self{},
    parent: ?*Self = null,

    fn deinit(self: *Self) void {
        if (self.kind == .tree) for (self.children) |*c| c.deinit();
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

    fn compare_objs_by_name(ctx: @This(), item: @This()) math.Order {
        return mem.order(u8, ctx.name, item.name);
    }

    fn compare_obj_to_name(ctx: []const u8, item: @This()) math.Order {
        return mem.order(u8, ctx, item.name);
    }

    fn lessThanFn(_: void, a: @This(), b: @This()) bool {
        return mem.order(u8, a.name, b.name) == .lt;
    }
};

fn update_hashes(obj: *Object) !void {
    var hasher = crypto.hash.Sha1.init(.{});
    for (obj.children) |*c| {
        if (c.kind == .tree) try update_hashes(c);
        hasher.update(&c.hash);
    }
    const hash_bytes = hasher.finalResult();
    const hash = fmt.bytesToHex(hash_bytes, .lower);
    _ = try fmt.bufPrint(&obj.hash, "{s}", .{hash});
}


const ObjectStatusKind = enum {
    unchanged,
    untracked,
    modified,
    deleted,
};

const ObjectStatus = struct {
    // If modified, obj1 is old object, obj2 is new object
    obj1: Object,
    obj2: ?Object = null,
    status: ObjectStatusKind = .unchanged,
};

// TODO: print full path of objects
fn check_status(allocator: mem.Allocator, cwd: fs.Dir) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    const head = try get_head(vec_dir);
    const tree = try get_tree_for_commit(allocator, objs_dir, head);
    defer if (tree) |t| allocator.free(t);

    var commit_tree = try construct_tree_from_hash(allocator, objs_dir, tree); 
    defer if (commit_tree) |*t| t.deinit();

    var current_tree = try construct_tree_from_dir(allocator, null, "", root_dir);
    defer current_tree.deinit();

    var index_file = try vec_dir.openFile("INDEX", .{ .mode = .read_only });
    defer index_file.close();

    var index_tree = try construct_tree_from_index(allocator, index_file);
    defer if (index_tree) |*t| t.deinit();

    var staged_changes = try std.ArrayList(ObjectStatus).initCapacity(allocator, 8);
    defer staged_changes.deinit(allocator);

    var unstaged_changes = try std.ArrayList(ObjectStatus).initCapacity(allocator, 8);
    defer unstaged_changes.deinit(allocator);

    if (index_tree) |t| try compare_index_tree_with_commit_tree(allocator, t, commit_tree, &staged_changes);
    try compare_index_tree_with_current_tree(allocator, index_tree, current_tree, &unstaged_changes);

    var staged_untracked_objs = try std.ArrayList(usize).initCapacity(allocator, 8);
    defer staged_untracked_objs.deinit(allocator);

    var staged_modified_objs = try std.ArrayList(usize).initCapacity(allocator, 8);
    defer staged_modified_objs.deinit(allocator);

    var staged_deleted_objs = try std.ArrayList(usize).initCapacity(allocator, 8);
    defer staged_deleted_objs.deinit(allocator);


    for (0..staged_changes.items.len) |i| {
        switch (staged_changes.items[i].status) {
            .untracked => try staged_untracked_objs.append(allocator, i),
            .modified  => try staged_modified_objs.append(allocator, i),
            .deleted   => try staged_deleted_objs.append(allocator, i),
            else       => {}
        }
    }

    if (staged_changes.items.len > 0) debug.print("Staged changes:\n", .{});
    for (staged_modified_objs.items) |i| {
        debug.print("\tmodified:\t{s}\n", .{staged_changes.items[i].obj1.name});
    }

    for (staged_untracked_objs.items) |i| {
        debug.print("\tuntracked:\t{s}\n", .{staged_changes.items[i].obj1.name});
    }

    for (staged_deleted_objs.items) |i| {
        debug.print("\tdeleted:\t{s}\n", .{staged_changes.items[i].obj1.name});
    }

    var unstaged_untracked_objs = try std.ArrayList(usize).initCapacity(allocator, 8);
    defer unstaged_untracked_objs.deinit(allocator);

    var unstaged_modified_objs = try std.ArrayList(usize).initCapacity(allocator, 8);
    defer unstaged_modified_objs.deinit(allocator);

    var unstaged_deleted_objs = try std.ArrayList(usize).initCapacity(allocator, 8);
    defer unstaged_deleted_objs.deinit(allocator);


    for (0..unstaged_changes.items.len) |i| {
        switch (unstaged_changes.items[i].status) {
            .untracked => try unstaged_untracked_objs.append(allocator, i),
            .modified  => try unstaged_modified_objs.append(allocator, i),
            .deleted   => try unstaged_deleted_objs.append(allocator, i),
            else       => {}
        }
    }

    if (unstaged_changes.items.len > 0) debug.print("Unstaged changes:\n", .{});
    for (unstaged_modified_objs.items) |i| {
        debug.print("\tmodified:\t{s}\n", .{unstaged_changes.items[i].obj1.name});
    }

    for (unstaged_untracked_objs.items) |i| {
        debug.print("\tuntracked:\t{s}\n", .{unstaged_changes.items[i].obj1.name});
    }

    for (unstaged_deleted_objs.items) |i| {
        debug.print("\tdeleted:\t{s}\n", .{unstaged_changes.items[i].obj1.name});
    }
}

fn construct_tree_from_hash(allocator: mem.Allocator, objs_dir: fs.Dir, hash: ?[]u8) !?Object {
    if (hash) |h| {
        var root_obj = Object {.allocator = allocator, .name = &[0]u8{}, .kind = .tree };
        _ = try fmt.bufPrint(&root_obj.hash, "{s}", .{h});

        var tree_file = try objs_dir.openFile(h, .{ .mode = .read_only });
        defer tree_file.close();

        var file_buf: [1024]u8 = undefined;
        var r = tree_file.reader(&file_buf);
        var reader = &r.interface;

        while (reader.takeDelimiter('\n')) |line| {
            if (line) |l| {
                var it = mem.splitScalar(u8, l, ' ');
                const obj_type_name = it.next().?;
                var obj_kind: ObjectKind = undefined;
                if (mem.eql(u8, obj_type_name, "blob")) {
                    obj_kind = .blob;
                } else if (mem.eql(u8, obj_type_name, "tree")) {
                    obj_kind = .tree;
                }
                const obj_name = it.next().?;
                const obj_hash = it.next().?;

                if (obj_kind == .blob) {
                    var obj = Object {.allocator = allocator, .name = &[0]u8{}, .kind = obj_kind};
                    obj.name = try fmt.allocPrint(obj.allocator, "{s}", .{obj_name});
                    _ = try fmt.bufPrint(&obj.hash, "{s}", .{obj_hash});
                    try root_obj.add_child(obj);
                } else {
                    var obj = try construct_tree_from_hash(allocator, objs_dir, @constCast(obj_hash));
                    if (obj) |*o| {
                        o.name = try fmt.allocPrint(o.allocator, "{s}", .{obj_name});
                        try root_obj.add_child(o.*);
                    }
                }
            } else {
                break;
            }
        } else |err| {
            _ = err catch {};
        }
        mem.sort(Object, root_obj.children, {}, Object.lessThanFn);
        return root_obj;
    }
    return null;
}

fn construct_tree_from_dir(allocator: mem.Allocator, parent: ?*Object, name: []const u8, d: fs.Dir) !Object {
    var hasher = crypto.hash.Sha1.init(.{});

    var root_obj = Object {
        .allocator = allocator,
        .name = &[0]u8{},
        .kind = .tree,
    };

    if (parent) |_| {
        root_obj.name = try fmt.allocPrint(root_obj.allocator, "{s}/", .{name});
    }

    var it = d.iterate();
    var entry = try it.next();
    while (entry) |e| {
        if (mem.eql(u8, e.name, ".vec")) {
            entry = try it.next();
            continue;
        }
        if (e.kind == .directory) {
            var subdir = try d.openDir(e.name, .{.iterate = true});
            defer subdir.close();
            const obj = try construct_tree_from_dir(allocator, &root_obj, e.name, subdir);
            if (obj.children.len > 0) {
                try root_obj.add_child(obj);
            }
        } else if (e.kind == .file) {
            var f = try d.openFile(e.name, .{ .mode = .read_only });
            defer f.close();
            const obj = try get_file_obj(allocator, &root_obj, e.name, f);
            try root_obj.add_child(obj);
        }

        entry = try it.next();
    }
    mem.sort(Object, root_obj.children, {}, Object.lessThanFn);

    for (root_obj.children) |c| {
        hasher.update(&c.hash);
    }

    const hash_bytes = hasher.finalResult();
    const hash = fmt.bytesToHex(hash_bytes, .lower);
    _ = try fmt.bufPrint(&root_obj.hash, "{s}", .{hash});
    root_obj.parent = parent;

    return root_obj;
}

fn construct_tree_from_index(allocator: mem.Allocator, index_file: fs.File) !?Object {
    var root_obj = Object {.allocator = allocator, .name = &[0]u8{}, .kind = .tree };

    var file_buf: [1024]u8 = undefined;
    var r = index_file.reader(&file_buf);
    var reader = &r.interface;

    while (reader.takeDelimiter('\n')) |line| {
        // TODO: make this logic simpler, because lines are sorted by name
        if (line) |l| {
            var it = mem.splitScalar(u8, l, ' ');
            const obj_hash = it.next().?;
            const obj_name = it.next().?;

            var parent_obj = &root_obj;
            var it2 = mem.splitScalar(u8, obj_name, '/');
            name_iter: while (it2.next()) |path| {
                for (parent_obj.children) |*c| {
                    if (c.kind == .blob) {
                        if (mem.eql(u8, c.name, path)) {
                            parent_obj = c;
                            continue :name_iter;
                        }
                    } else {
                        if (mem.eql(u8, c.name[0..c.name.len-1], path)) {
                            parent_obj = c;
                            continue :name_iter;
                        }
                    }
                }
                const kind: ObjectKind = if (it2.peek()) |_| .tree else .blob;
                var obj = Object {.allocator = allocator, .name = &[0]u8{}, .kind = kind};
                if (kind == .blob) obj.name = try fmt.allocPrint(obj.allocator, "{s}", .{path})
                else obj.name = try fmt.allocPrint(obj.allocator, "{s}/", .{path});
                if (kind == .blob) _ = try fmt.bufPrint(&obj.hash, "{s}", .{obj_hash});
                obj.parent = parent_obj;

                try parent_obj.add_child(obj);
                if (kind == .tree) parent_obj = &parent_obj.children[parent_obj.children.len-1];
            }
        } else {
            break;
        }
    } else |err| {
        _ = err catch {};
    }

    try update_hashes(&root_obj);

    if (root_obj.children.len == 0) return null;

    return root_obj;
}

fn get_obj_from_path(allocator: mem.Allocator, cwd: fs.Dir, path: []const u8) !Object {
    const s = try cwd.statFile(path);
    if (s.kind == .file) {
        var f = try cwd.openFile(path, .{ .mode = .read_only });
        defer f.close();
        const obj = try get_file_obj(allocator, null, path, f);
        return obj;
    } else if (s.kind == .directory) {
        const subdir = try cwd.openDir(path, .{ .iterate = true });

        const obj = construct_tree_from_dir(allocator, null, path, subdir);
        return obj;
    }
    return error.InvalidFileType;
}

fn get_file_obj(allocator: mem.Allocator, parent: ?*Object, name: []const u8, f: fs.File) !Object {
    var hasher = crypto.hash.Sha1.init(.{});

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
    const hash = fmt.bytesToHex(hash_bytes, .lower);

    var obj = Object {
        .allocator = allocator,
        .name = &[0]u8{},
        .kind = .blob,
        .parent = parent,
    };
    obj.name = try fmt.allocPrint(obj.allocator, "{s}", .{name});
    _ = try fmt.bufPrint(&obj.hash, "{s}", .{hash});

    return obj;
}

// TODO: print full path of objects
fn dump_obj(t: Object) void {
    debug.print("kind: {s}\thash: {s}\tname: {s}\n", .{@tagName(t.kind), t.hash, t.name});
    for (t.children) |c| {
        debug.print("\t", .{});
        dump_obj(c);
    }
}

fn compare_trees(allocator: mem.Allocator, tree1: Object, tree2: Object, changes: *std.ArrayList(ObjectStatus)) !void {
    if (mem.eql(u8, &tree1.hash, &tree2.hash)) return;

    const m = tree1.children.len;
    const n = tree2.children.len;

    outer: for (0..m) |i| {
        for (0..n) |j| {
            if (mem.eql(u8, tree1.children[i].name, tree2.children[j].name)) {
                if (!mem.eql(u8, &tree1.children[i].hash, &tree2.children[j].hash)) {
                    if (tree1.children[i].kind == .blob) try changes.append(allocator, .{ .obj1 = tree1.children[i], .obj2 = tree2.children[j], .status = .modified })
                    else try compare_index_tree_with_commit_tree(allocator, tree1.children[i], tree2.children[j], changes);
                }
                continue :outer;
            }
        }
        try changes.append(allocator, .{ .obj1 = tree1.children[i], .status = .deleted });
    }
    outer: for (0..n) |j| {
        for (0..m) |i| {
            if (mem.eql(u8, tree1.children[i].name, tree2.children[j].name)) continue :outer;
        }
        try changes.append(allocator, .{ .obj1 = tree2.children[j], .status = .untracked });
    }
}

fn compare_index_tree_with_commit_tree(allocator: mem.Allocator, index_tree: Object, commit_tree: ?Object, changes: *std.ArrayList(ObjectStatus)) !void {
    if (commit_tree) |commit_tree_obj| {
        if (mem.eql(u8, &commit_tree_obj.hash, &index_tree.hash)) return;

        const m = commit_tree_obj.children.len;
        const n = index_tree.children.len;

        outer: for (0..m) |i| {
            for (0..n) |j| {
                if (mem.eql(u8, commit_tree_obj.children[i].name, index_tree.children[j].name)) {
                    if (!mem.eql(u8, &commit_tree_obj.children[i].hash, &index_tree.children[j].hash)) {
                        if (commit_tree_obj.children[i].kind == .blob) try changes.append(allocator, .{ .obj1 = commit_tree_obj.children[i], .obj2 = index_tree.children[j], .status = .modified })
                        else try compare_index_tree_with_commit_tree(allocator, index_tree.children[j], commit_tree_obj.children[i], changes);
                    }
                    continue :outer;
                }
            }
            try changes.append(allocator, .{ .obj1 = commit_tree_obj.children[i], .status = .deleted });
        }
        outer: for (0..n) |j| {
            for (0..m) |i| {
                if (mem.eql(u8, commit_tree_obj.children[i].name, index_tree.children[j].name)) continue :outer;
            }
            try changes.append(allocator, .{ .obj1 = index_tree.children[j], .status = .untracked });
        }
    } else {
        for (index_tree.children) |c| {
            if (c.kind == .blob) try changes.append(allocator, .{ .obj1 = c, .status = .untracked })
            else try compare_index_tree_with_commit_tree(allocator, c, null, changes);

        }
    }
}

fn compare_index_tree_with_current_tree(allocator: mem.Allocator, index_tree: ?Object, current_tree: Object, changes: *std.ArrayList(ObjectStatus)) !void {
    if (index_tree) |index_tree_obj| {
        if (mem.eql(u8, &index_tree_obj.hash, &current_tree.hash)) return;

        const m = index_tree_obj.children.len;
        const n = current_tree.children.len;

        outer: for (0..m) |i| {
            for (0..n) |j| {
                if (mem.eql(u8, index_tree_obj.children[i].name, current_tree.children[j].name)) {
                    if (!mem.eql(u8, &index_tree_obj.children[i].hash, &current_tree.children[j].hash)) {
                        if (index_tree_obj.children[i].kind == .blob) try changes.append(allocator, .{ .obj1 = index_tree_obj.children[i], .obj2 = current_tree.children[j], .status = .modified })
                        else try compare_index_tree_with_current_tree(allocator, index_tree_obj.children[i], current_tree.children[j], changes);
                    }
                    continue :outer;
                }
            }
            try changes.append(allocator, .{ .obj1 = index_tree_obj.children[i], .status = .deleted });
        }
        outer: for (0..n) |j| {
            for (0..m) |i| {
                if (mem.eql(u8, index_tree_obj.children[i].name, current_tree.children[j].name)) continue :outer;
            }
            try changes.append(allocator, .{ .obj1 = current_tree.children[j], .status = .untracked });
        }
    } else {
        for (current_tree.children) |c| {
            try changes.append(allocator, .{ .obj1 = c, .status = .untracked });
        }
    }
}

fn snapshot_index(allocator: mem.Allocator, cwd: fs.Dir, msg: []const u8) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var index_file = try vec_dir.openFile("INDEX", .{ .mode = .read_only });
    defer index_file.close();

    var index_tree = try construct_tree_from_index(allocator, index_file);
    defer if (index_tree) |*t| t.deinit();
    
    if (index_tree) |t| {
        try snapshot_tree(allocator, cwd, t, msg);
    } else {
        try check_status(allocator, cwd);
        debug.print("no changes to commit\n", .{});
        return;
    }

}

fn snapshot_tree(allocator: mem.Allocator, cwd:fs.Dir, tree: Object, msg: []const u8) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    const head = try get_head(vec_dir);
    const head_tree = try get_tree_for_commit(allocator, objs_dir, head);
    defer if (head_tree) |t| allocator.free(t);

    if (head_tree) |ht| 
        if (mem.eql(u8, ht, &tree.hash)) {
            try check_status(allocator, cwd);
            debug.print("no changes to commit\n", .{});
            return;
        };
    try store_tree_obj(root_dir, objs_dir, tree);
    const new_commit = try write_commit_obj(objs_dir, head, tree.hash, msg);
    try set_head(vec_dir, new_commit);
}

fn store_blob_obj(root_dir: fs.Dir, objs_dir: fs.Dir, blob_obj: Object) !void {
    const blob_file_name = blob_obj.hash;
    if (objs_dir.access(&blob_file_name, .{})) {
        return;
    } else |err| {
        switch (err) {
            error.FileNotFound => {
                try fs.Dir.copyFile(root_dir, blob_obj.name, objs_dir, &blob_file_name, .{});
            },
            else => return err
        }
    }
}

fn store_tree_obj(working_dir: fs.Dir, objs_dir: fs.Dir, tree_obj: Object) !void {
    const tree_file_name = tree_obj.hash;
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
    var file_buf: [1024]u8 = undefined;
    var writer = tree_file.writer(&file_buf);
    var w = &writer.interface;

    for (tree_obj.children) |c| {
        try w.print("{s} {s} {s}\n", .{@tagName(c.kind), c.name, c.hash});
        try w.flush();
        if (c.kind == .tree) {
            var subdir = try working_dir.openDir(c.name, .{ .iterate = true });
            defer subdir.close();
            try store_tree_obj(subdir, objs_dir, c);
        } else {
            try store_blob_obj(working_dir, objs_dir, c);
        }
    }
}

fn write_commit_obj(objs_dir: fs.Dir, prev_commit_hash: ?[40]u8, tree_hash: [40]u8, msg: []const u8) ![40]u8 {
    var hasher = crypto.hash.Sha1.init(.{});
    if (prev_commit_hash) |ph| hasher.update(&ph) else hasher.update(&[1]u8{0});
    hasher.update(&tree_hash);
    hasher.update(msg);
    const hash_bytes = hasher.finalResult();
    const hash = fmt.bytesToHex(hash_bytes, .lower);

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

fn write_indexed_objs(index_file: fs.File, objs: []Object) !void {
    var buf: [2*1024]u8 = undefined;
    var w = index_file.writer(&buf);
    var writer = &w.interface;

    for (objs) |o| {
        try writer.print("{s} {s}\n", .{o.hash, o.name});
        try writer.flush();
    }
}

fn set_head(vec_dir: fs.Dir, new_head: [40]u8) !void {
    var head_file = try vec_dir.openFile("HEAD", .{ .mode = .read_write });
    defer head_file.close();

    var buf: [1024]u8 = undefined;
    var w = head_file.writer(&buf);
    var writer = &w.interface;

    try writer.print("{s}", .{new_head});
    try writer.flush();
}

fn list_commits(allocator: mem.Allocator, cwd: fs.Dir) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    const head = try get_head(vec_dir);
    if (head) |h| {
        var msg = try get_commit_message(allocator, objs_dir, h);
        debug.print("commit {s} (HEAD)\n", .{h});
        debug.print("   {s}\n", .{msg});
        allocator.free(msg);

        var it = try get_parent_commit(objs_dir, h);
        while (it) |commit| {
            msg = try get_commit_message(allocator, objs_dir, commit);
            defer allocator.free(msg);
            debug.print("commit {s}\n", .{commit});
            debug.print("   {s}\n", .{msg});
            it = try get_parent_commit(objs_dir, commit);
        } else {}
    }
}

fn reset_soft(cwd: fs.Dir, commit: []const u8) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    var target_commit: [40]u8 = undefined;
    _ = try fmt.bufPrint(&target_commit, "{s}", .{commit});

    const head = try get_head(vec_dir);
    if (head) |h| {
        var it = try get_parent_commit(objs_dir, h);
        while (it) |c| {
            if (mem.eql(u8, &c, &target_commit)) {
                try set_head(vec_dir, target_commit);
                return;
            }
            it = try get_parent_commit(objs_dir, c);
        } else {}
    }

    debug.print("fatal: provided commit does not exist\n", .{});
}

fn reset_hard(allocator: mem.Allocator, cwd: fs.Dir, commit: []const u8) !void {
    try reset_mixed(allocator, cwd, commit);

    const root_dir = try get_root_dir(cwd);
    try restore_path(allocator, root_dir, ".");
}

fn reset_mixed(allocator: mem.Allocator, cwd: fs.Dir, commit: []const u8) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    const head = try get_head(vec_dir);
    const tree = try get_tree_for_commit(allocator, objs_dir, head);
    defer if (tree) |t| allocator.free(t);

    var commit_tree = try construct_tree_from_hash(allocator, objs_dir, tree); 
    defer if (commit_tree) |*t| t.deinit();

    var current_tree = try construct_tree_from_dir(allocator, null, "", root_dir);
    defer current_tree.deinit();

    var index_file = try vec_dir.openFile("INDEX", .{ .mode = .read_only });

    var index_tree = try construct_tree_from_index(allocator, index_file);
    defer if (index_tree) |*t| t.deinit();

    var staged_changes = try std.ArrayList(ObjectStatus).initCapacity(allocator, 8);
    defer staged_changes.deinit(allocator);

    var unstaged_changes = try std.ArrayList(ObjectStatus).initCapacity(allocator, 8);
    defer unstaged_changes.deinit(allocator);

    if (index_tree) |t| try compare_index_tree_with_commit_tree(allocator, t, commit_tree, &staged_changes);
    try compare_index_tree_with_current_tree(allocator, index_tree, current_tree, &unstaged_changes);

    if (staged_changes.items.len > 0) {
        debug.print("fatal: staged changes have not been committed\n", .{});
        return;
    }

    for (0..unstaged_changes.items.len) |i| {
        if (unstaged_changes.items[i].status == .deleted or unstaged_changes.items[i].status == .modified) {
            debug.print("fatal: files have been modified in working directory\n", .{});
            return;
        }
    }

    var target_commit: [40]u8 = undefined;
    _ = try fmt.bufPrint(&target_commit, "{s}", .{commit});

    var is_present = false;
    if (head) |h| {
        var it = try get_parent_commit(objs_dir, h);
        while (it) |c| {
            if (mem.eql(u8, &c, &target_commit)) {
                is_present = true;
                break;
            }
            it = try get_parent_commit(objs_dir, c);
        } else {}
    }

    if (!is_present) {
        debug.print("fatal: provided commit does not exist\n", .{});
        return;
    }

    const target_tree_hash = try get_tree_for_commit(allocator, objs_dir, target_commit);
    defer if (target_tree_hash) |t| allocator.free(t);
    var target_tree = try construct_tree_from_hash(allocator, objs_dir, target_tree_hash);
    defer if (target_tree) |*t| t.deinit();

    var indexed_objs = try flatten_tree_obj(allocator, target_tree.?, "");
    defer allocator.free(indexed_objs);
    defer for (0..indexed_objs.len) |i| indexed_objs[i].deinit();

    index_file.close();
    var new_index_file = try vec_dir.createFile("INDEX", .{});
    defer new_index_file.close();
    try write_indexed_objs(new_index_file, indexed_objs);
    try set_head(vec_dir, target_commit);
}

fn flatten_tree_obj(allocator: mem.Allocator, tree: Object, parent_dir: []const u8) ![]Object {
    var objs = try std.ArrayList(Object).initCapacity(allocator, 16);
    defer objs.deinit(allocator);

    for (0..tree.children.len) |i| {
        if (tree.children[i].kind == .tree) {
            const children = try flatten_tree_obj(allocator, tree.children[i], tree.children[i].name);
            defer allocator.free(children);
            try objs.appendSlice(allocator, children);
        } else {
            var o = Object {
                .name = &[0]u8{},
                .kind = .blob,
                .allocator = allocator
            };
            _ = try fmt.bufPrint(&o.hash, "{s}", .{tree.children[i].hash});
            o.name = try fmt.allocPrint(allocator, "{s}{s}", .{parent_dir, tree.children[i].name});
            try objs.append(allocator, o);
        }
    }

    return objs.toOwnedSlice(allocator);
}

fn get_indexed_objs(allocator: mem.Allocator, index_file: fs.File) ![]Object {
    var file_buf: [1024]u8 = undefined;
    var r = index_file.reader(&file_buf);
    var reader = &r.interface;

    var objs = try std.ArrayList(Object).initCapacity(allocator, 16);
    defer objs.deinit(allocator);

    while (reader.takeDelimiter('\n')) |line| {
        if (line) |l| {
            var it = mem.splitScalar(u8, l, ' ');
            const obj_hash = it.next().?;
            const obj_name = it.next().?;
            var obj = Object {.allocator = allocator, .name = &[0]u8{}, .kind = .blob};
            obj.name = try fmt.allocPrint(obj.allocator, "{s}", .{obj_name});
            _ = try fmt.bufPrint(&obj.hash, "{s}", .{obj_hash});
            try objs.append(allocator, obj);
        } else {
            break;
        }
    } else |err| {
        _ = err catch {};
    }
    return objs.toOwnedSlice(allocator);
}

fn add_to_index(allocator: mem.Allocator, cwd: fs.Dir, path: []const u8) !void {
    var root_dir = try get_root_dir(cwd);
    const root_path = try root_dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);


    const full_path = try cwd.realpathAlloc(allocator, path);
    defer allocator.free(full_path);
    if (full_path.len < root_path.len or !mem.eql(u8, root_path, full_path[0..root_path.len])) {
        debug.print("fatal: provided path '{s}' is outside working directory '{s}'\n", .{full_path, root_path});
        process.exit(1);
    }

    const internal_path = if (full_path.len > root_path.len) full_path[root_path.len+1..] else ".";

    const s = try root_dir.statFile(internal_path);
    if (s.kind == .file) {
        try add_file_to_index(allocator, cwd, internal_path);
        return;
    } else if (s.kind != .directory) return;

    var dir = try root_dir.openDir(internal_path, .{ .iterate = true });
    defer if (full_path.len > root_path.len) dir.close();
    var it = dir.iterate();
    var entry = try it.next();
    while (entry) |e| {
        const child_full_path = try dir.realpathAlloc(allocator, e.name);
        defer allocator.free(child_full_path); 

        if (e.kind == .directory and mem.eql(u8, e.name, ".vec")) {
            entry = try it.next();
            continue;
        }

        if (e.kind == .directory) 
            try add_to_index(allocator,  root_dir, child_full_path[root_path.len+1..])
        else if (e.kind == .file) 
            try add_file_to_index(allocator, root_dir, child_full_path[root_path.len+1..]);
        entry = try it.next();
    }
}

fn add_file_to_index(allocator: mem.Allocator, cwd: fs.Dir, path: []const u8) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    var index_file = try vec_dir.openFile("INDEX", .{ .mode = .read_write });
    var indexed_objs = try get_indexed_objs(allocator, index_file);
    defer allocator.free(indexed_objs);
    defer for (indexed_objs) |*o| o.deinit(); 
    index_file.close();

    var file_obj = try get_obj_from_path(allocator, cwd, path);

    var indexed_objs_idx: usize = undefined;

    if (sort.binarySearch(Object, indexed_objs, file_obj, Object.compare_objs_by_name)) |idx| {
        file_obj.deinit();
        if (mem.eql(u8, &indexed_objs[idx].hash, &file_obj.hash)) return;

        _ = try fmt.bufPrint(&indexed_objs[idx].hash, "{s}", .{file_obj.hash});
        indexed_objs_idx = idx;
    } else {
        const idx = sort.upperBound(Object, indexed_objs, file_obj, Object.compare_objs_by_name);
        indexed_objs = try allocator.realloc(indexed_objs, indexed_objs.len + 1);
        if (idx < indexed_objs.len - 1) {
            var i = indexed_objs.len - 1;
            while (i > idx) {
                indexed_objs[i] = indexed_objs[i-1];
                i -= 1;
            }
        }
        indexed_objs[idx] = file_obj;
        indexed_objs_idx = idx;
    }

    index_file = try vec_dir.createFile("INDEX", .{});
    defer index_file.close();

    try write_indexed_objs(index_file, indexed_objs);
    try store_blob_obj(root_dir, objs_dir, indexed_objs[indexed_objs_idx]);
}

fn restore_path(allocator: mem.Allocator, cwd: fs.Dir, path: []const u8) !void {
    var root_dir = try get_root_dir(cwd);
    const root_path = try root_dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    const full_path = try cwd.realpathAlloc(allocator, path);
    defer allocator.free(full_path);

    if (full_path.len < root_path.len or !mem.eql(u8, root_path, full_path[0..root_path.len])) {
        debug.print("fatal: provided path '{s}' is outside working directory '{s}'\n", .{full_path, root_path});
        process.exit(1);
    }

    const internal_path = if (full_path.len > root_path.len) full_path[root_path.len+1..] else ".";

    const s = try cwd.statFile(internal_path);
    if (s.kind == .file) {
        try restore_file(allocator, root_dir, internal_path);
    } else if (s.kind != .directory) {
        return;
    }

    var dir = try root_dir.openDir(internal_path, .{ .iterate = true });
    defer if (full_path.len > root_path.len) dir.close();
    var it = dir.iterate();
    var entry = try it.next();
    while (entry) |e| {
        const child_full_path = try dir.realpathAlloc(allocator, e.name);
        defer allocator.free(child_full_path); 
        if (e.kind == .directory) 
            try restore_path(allocator, root_dir, child_full_path[root_path.len+1..])
        else if (e.kind == .file) 
            try restore_file(allocator, root_dir, child_full_path[root_path.len+1..]);
        
        entry = try it.next();
    }
}

fn restore_file(allocator: mem.Allocator, cwd: fs.Dir, path: []const u8) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    const index_file = try vec_dir.openFile("INDEX", .{ .mode = .read_write });
    const indexed_objs = try get_indexed_objs(allocator, index_file);
    defer allocator.free(indexed_objs);
    defer for (indexed_objs) |*o| o.deinit(); 

    var file_obj = try get_obj_from_path(allocator, cwd, path);
    defer file_obj.deinit();

    const file_indexed_obj_idx = sort.binarySearch(Object, indexed_objs, file_obj, Object.compare_objs_by_name);
    if (file_indexed_obj_idx) |idx| {
        if (!mem.eql(u8, &indexed_objs[idx].hash, &file_obj.hash)) 
                try fs.Dir.copyFile(objs_dir, &indexed_objs[idx].hash, cwd, path, .{});
    }
}

fn restore_index_for_file(allocator: mem.Allocator, cwd: fs.Dir, path: []const u8) !void {
    var root_dir = try get_root_dir(cwd);
    const root_path = try root_dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    const full_path = try cwd.realpathAlloc(allocator, path);
    defer allocator.free(full_path);

    if (full_path.len < root_path.len or !mem.eql(u8, root_path, full_path[0..root_path.len])) {
        debug.print("fatal: provided path '{s}' is outside working directory '{s}'\n", .{full_path, root_path});
        process.exit(1);
    }

    const s = try cwd.statFile(path);
    if (s.kind != .file) {
        debug.print("fatal: provided path '{s}' is not a file\n", .{full_path});
        process.exit(1);
    }

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    var index_file = try vec_dir.openFile("INDEX", .{ .mode = .read_write });
    var indexed_objs = try get_indexed_objs(allocator, index_file);
    defer allocator.free(indexed_objs);
    defer for (indexed_objs) |*o| o.deinit(); 
    index_file.close();

    const indexed_objs_idx = sort.binarySearch(Object, indexed_objs, full_path[root_path.len+1..], Object.compare_obj_to_name);
    if (indexed_objs_idx) |_| {} else { return; }

    index_file = try vec_dir.createFile("INDEX", .{});
    defer index_file.close();
    
    const tree_hash = try get_tree_for_commit(allocator, objs_dir, try get_head(vec_dir));
    defer if (tree_hash) |t| allocator.free(t);

    var commit_tree = try construct_tree_from_hash(allocator, objs_dir, tree_hash);
    defer if (commit_tree) |*t| t.deinit();

    if (commit_tree) |*tree| {

        var it = mem.splitScalar(u8, full_path[root_path.len+1..], '/');
        var tree_it: *Object = @constCast(tree);
        var present = true;
        while (it.next()) |p| {
            if (it.peek()) |_| {
                const p1 = try fmt.allocPrint(allocator, "{s}/", .{p});
                defer allocator.free(p1);
                if (sort.binarySearch(Object, tree_it.children, p1, Object.compare_obj_to_name)) |idx| {
                    tree_it = &tree_it.children[idx];
                } else {
                    present = false;
                    break;
                }
            } else {
                if (sort.binarySearch(Object, tree_it.children, p, Object.compare_obj_to_name)) |idx| {
                    tree_it = &tree_it.children[idx];
                } else {
                    present = false;
                }
                break;
            }
        }


        if (present) {
            _ = try fmt.bufPrint(&indexed_objs[indexed_objs_idx.?].hash, "{s}", .{tree_it.hash});
            try write_indexed_objs(index_file, indexed_objs);
            return;
        }
    } 

    indexed_objs[indexed_objs_idx.?].deinit();
    for (indexed_objs_idx.?..indexed_objs.len-1) |i| {
        indexed_objs[i] = indexed_objs[i+1];
    }
    indexed_objs = try allocator.realloc(indexed_objs, indexed_objs.len - 1);

    try write_indexed_objs(index_file, indexed_objs);
}

fn compare_commits(allocator: mem.Allocator, cwd: fs.Dir, commit1: []const u8, commit2: []const u8) !void {
    var root_dir = try get_root_dir(cwd);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    var commit1_hash: [40]u8 = undefined;
    _ = try fmt.bufPrint(&commit1_hash, "{s}", .{commit1});

    var commit2_hash: [40]u8 = undefined;
    _ = try fmt.bufPrint(&commit2_hash, "{s}", .{commit2});

    const tree1_hash = try get_tree_for_commit(allocator, objs_dir, commit1_hash);
    defer if (tree1_hash) |h| allocator.free(h);
    var tree1 = try construct_tree_from_hash(allocator, objs_dir, tree1_hash);
    defer if (tree1) |*t1| t1.deinit();

    const tree2_hash = try get_tree_for_commit(allocator, objs_dir, commit2_hash);
    defer if (tree2_hash) |h| allocator.free(h);
    var tree2 = try construct_tree_from_hash(allocator, objs_dir, tree2_hash);
    defer if (tree2) |*t2| t2.deinit();

    var changes = try std.ArrayList(ObjectStatus).initCapacity(allocator, 8);
    defer changes.deinit(allocator);

    if (tree1) |t1| if (tree2) |t2| try compare_trees(allocator, t1, t2, &changes);

    for (0..changes.items.len) |i| {
        if (changes.items[i].status == .modified) {
            var f1 = try objs_dir.openFile(&changes.items[i].obj1.hash, .{ .mode = .read_only });
            defer f1.close();
            var f2 = try objs_dir.openFile(&changes.items[i].obj2.?.hash, .{ .mode = .read_only });
            defer f2.close();

            var buf: [2][1024*1024]u8 = undefined;
            var file_readers = [_]fs.File.Reader {
                f1.reader(&buf[0]),
                f2.reader(&buf[1])
            };

            var stdout_buf: [1024*1024]u8 = undefined;
            var stdout_writer = fs.File.stdout().writer(&stdout_buf);
            const stdout = &stdout_writer.interface;

            try stdout.print("{s}\n", .{changes.items[i].obj1.name});
            try stdout.flush();
            _ = try myers_diff(@constCast(stdout), allocator, &file_readers);
        }
    }
}

fn compare_path_with_index(allocator: mem.Allocator, cwd: fs.Dir, path: []const u8, no_output: bool) !bool {
    var root_dir = try get_root_dir(cwd);
    const root_path = try root_dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    const full_path = try cwd.realpathAlloc(allocator, path);
    defer allocator.free(full_path);
    if (full_path.len < root_path.len or !mem.eql(u8, root_path, full_path[0..root_path.len])) {
        debug.print("fatal: provided path '{s}' is outside working directory '{s}'\n", .{full_path, root_path});
        process.exit(1);
    }

    const internal_path = if (full_path.len > root_path.len) full_path[root_path.len+1..] else ".";
 
    const s = try root_dir.statFile(internal_path);
    if (s.kind == .file) {
        const changed = try compare_file_with_indexed_obj(allocator, root_dir, full_path[root_path.len+1..], no_output);
        return changed;
    } else if (s.kind != .directory) return false;

    var changed = false;

    var dir = try root_dir.openDir(internal_path, .{ .iterate = true });
    defer if (full_path.len > root_path.len) dir.close();
    var it = dir.iterate();
    var entry = try it.next();
    while (entry) |e| {
        const child_full_path = try dir.realpathAlloc(allocator, e.name);
        defer allocator.free(child_full_path); 
        if (e.kind == .directory) 
            changed = try compare_path_with_index(allocator,  root_dir, child_full_path[root_path.len+1..], no_output) or changed
        else if (e.kind == .file) 
            changed = try compare_file_with_indexed_obj(allocator, root_dir, child_full_path[root_path.len+1..], no_output) or changed;
        
        entry = try it.next();
    }

    return changed;
}

fn compare_file_with_indexed_obj(allocator: mem.Allocator, root_dir: fs.Dir, file_path: []const u8, no_output: bool) !bool {
    var vec_dir = try root_dir.openDir(".vec", .{});
    defer vec_dir.close();

    var objs_dir = try vec_dir.openDir("objects", .{});
    defer objs_dir.close();

    const index_file = try vec_dir.openFile("INDEX", .{ .mode = .read_write });
    const indexed_objs = try get_indexed_objs(allocator, index_file);
    defer allocator.free(indexed_objs);
    defer for (indexed_objs) |*o| o.deinit(); 

    var index: usize = 0;
    if (sort.binarySearch(Object, indexed_objs, file_path, Object.compare_obj_to_name)) |i| {
        index = i;
    } else return false;

    var committed_file = try objs_dir.openFile(&indexed_objs[index].hash, .{ .mode = .read_only });
    defer committed_file.close();
    var current_file = try root_dir.openFile(file_path, .{ .mode = .read_only });
    defer current_file.close();

    var buf: [2][1024*1024]u8 = undefined;
    var file_readers = [_]fs.File.Reader {
        committed_file.reader(&buf[0]),
        current_file.reader(&buf[1])
    };

    var stdout_buf: [1024*1024]u8 = undefined;
    var stdout_writer = fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    try stdout.print("\n{s}index {s}\n{s}{s}\n", .{sub_prefix, indexed_objs[index].hash, add_prefix, file_path});

    const changed = try myers_diff(@constCast(stdout), allocator, &file_readers);
    if (!changed or no_output) try stdout.noopFlush()
    else try stdout.flush();
    return changed;
}

const EditGraph = struct {
    const Self = @This();
    items: []u32,
    edits: u32,
    max: usize,

    pub fn init(gpa: mem.Allocator, max: usize) !Self {
        var self = Self {.items = &[_]u32{}, .edits = undefined, .max = max};
        self.items = try gpa.alloc(u32, 2*max+1);
        @memset(self.items, 0);
        return self;
    }
    pub fn deinit(self: *Self, gpa: mem.Allocator) void {
        gpa.free(self.items);
    }
    pub fn get(self: *Self, i: i64) u32 {
        const idx: usize = @intCast(i + @as(i32, @intCast(self.max)));
        debug.assert(idx >= 0 and idx < 2*self.max+1);
        return self.items[idx];
    }
    pub fn set(self: *Self, i: i64, val: u32) void {
        const idx: usize = @intCast(i + @as(i32, @intCast(self.max)));
        debug.assert(idx >= 0 and idx < 2*self.max+1);
        self.items[idx] = val;
    }
    pub fn clone(self: *Self, gpa: mem.Allocator) !Self {
        var new = Self {.items = &[_]u32{}, .edits = self.edits, .max = self.max};
        new.items = try gpa.dupe(u32, self.items);
        return new;
    }
};

const Operation = enum {
    ADD,
    SUB
};

const add_prefix = "> ";
const sub_prefix = "< ";

fn myers_diff(stdout: *std.Io.Writer, allocator: mem.Allocator, file_readers: *[2]fs.File.Reader) !bool {
    const readers = [_]*std.Io.Reader {
        &file_readers[0].interface,
        &file_readers[1].interface,
    };

    var file_contents = [_]std.ArrayList([]u8) {
        try std.ArrayList([]u8).initCapacity(allocator, 16),
        try std.ArrayList([]u8).initCapacity(allocator, 16),
    };
    defer file_contents[0].deinit(allocator);
    defer file_contents[1].deinit(allocator);

    while (readers[0].takeDelimiterInclusive('\n')) |l| {
        const line = l[0..l.len-1];
        try file_contents[0].append(allocator, line);
    } else |err| {
        _ = err catch {};
    }
    while (readers[1].takeDelimiterInclusive('\n')) |l| {
        const line = l[0..l.len-1];
        try file_contents[1].append(allocator, line);
    } else |err| {
        _ = err catch {};
    }

    const m = file_contents[0].items.len;
    const n = file_contents[1].items.len;
    const max = m + n;

    var edit_graph = try EditGraph.init(allocator, max);
    defer edit_graph.deinit(allocator);

    var trace = try std.ArrayList(EditGraph).initCapacity(allocator, 16);
    defer {
        for (trace.items) |*item| {
            item.deinit(allocator);
        }
        trace.deinit(allocator);
    }

    var d: i64 = 0;
    outer: while (d <= max) {
        var k = -d;
        try trace.append(allocator, try edit_graph.clone(allocator));
        while (k <= d) {
            var x: i64 = undefined;
            if (k == -d or (k != d and edit_graph.get(k-1) < edit_graph.get(k+1))) {
                x = edit_graph.get(k + 1);
            } else {
                x = edit_graph.get(k - 1) + 1;
            }
            var y = x - k;

            while (x < m and y < n and mem.eql(u8, file_contents[0].items[@as(usize, @intCast(x))], file_contents[1].items[@as(usize, @intCast(y))])) {
                x += 1;
                y += 1;
            }

            edit_graph.set(k, @intCast(x));

            if (x >= m and y >= n) {
                edit_graph.edits = @intCast(d);
                break :outer;
            }

            k += 2;
        }
        d += 1;
    }

    var edit_ops = try std.ArrayList(Operation).initCapacity(allocator, 16);
    defer edit_ops.deinit(allocator);

    var edited_x = try std.ArrayList(i64).initCapacity(allocator, 16);
    defer edited_x.deinit(allocator);

    var edited_y = try std.ArrayList(i64).initCapacity(allocator, 16);
    defer edited_y.deinit(allocator);

    var x: i64 = @intCast(m);
    var y: i64 = @intCast(n);
    d = @intCast(trace.items.len-1);
    while (d >= 0) {
        var v = trace.items[@as(usize, @intCast(d))];
        const k = x - y;
        var op: Operation = undefined; 

        var prev_k: i64 = undefined;
        if (k == -d or (k != d and v.get(k-1) < v.get(k + 1))) {
            prev_k = k + 1;
            op = .ADD;
        } else {
            prev_k = k - 1;
            op = .SUB;
        }

        const prev_x = v.get(prev_k);
        const prev_y = prev_x - prev_k;

        while (x > prev_x and y > prev_y) {
            x -= 1;
            y -= 1;
        }

        if (op == .ADD) {
            if (y == 0) break;
            try edit_ops.append(allocator, .ADD);
            try edited_x.append(allocator, x);
            try edited_y.append(allocator, y - 1);
            y -= 1;
        } else {
            if (x == 0) break;
            try edit_ops.append(allocator, .SUB);
            try edited_x.append(allocator, x - 1);
            try edited_y.append(allocator, y);
            x -= 1;
        }

        if (x == 0 and y == 0) break;

        d -= 1;
    }

    if (edit_ops.items.len == 0) return false;

    mem.reverse(Operation, edit_ops.items);
    mem.reverse(i64, edited_x.items);
    mem.reverse(i64, edited_y.items);
    var i: usize = 0;
    while (i < edit_ops.items.len) {
        const x1 = edited_x.items[i];
        const y1 = edited_y.items[i];

        if (edit_ops.items[i] == .SUB and
            i + 1 < edit_ops.items.len and
            edit_ops.items[i+1] == .ADD) {
            const next_y = edited_y.items[i+1];
            try stdout.print("{d}c{d}\n", .{x1 + 1, next_y + 1});
            try stdout.print("{s}{s}\n", .{sub_prefix, file_contents[0].items[@as(usize, @intCast(x1))]});
            try stdout.print("---\n", .{});
            try stdout.print("{s}{s}\n", .{add_prefix, file_contents[1].items[@as(usize, @intCast(next_y))]});
            i += 2;
        } else if (edit_ops.items[i] == .ADD) {
            try stdout.print("{d}a{d}\n", .{x1, y1 + 1});
            try stdout.print("{s}{s}\n", .{add_prefix, file_contents[1].items[@as(usize, @intCast(y1))]});
            i += 1;
        } else {
            try stdout.print("{d}d{d}\n", .{x1 + 1, y1});
            try stdout.print("{s}{s}\n", .{sub_prefix, file_contents[0].items[@as(usize, @intCast(x1))]});
            i += 1;
        }
    }

    try file_readers[0].seekTo(0);
    try file_readers[1].seekTo(0);

    return true;
}
