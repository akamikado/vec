const std = @import("std");

fn init_contents_dir(dir: std.fs.Dir) !void {
    dir.makeDir(".vec") catch |err| {
        switch (err) {
            error.PathAlreadyExists => return,
            else => return err
        }
    };
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    var path_buf: [1024]u8 = undefined;
    var cwd = try std.fs.cwd().openDir(".", .{});
    defer cwd.close();
    var cwd_path = try cwd.realpath(".", &path_buf);

    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "init")) {
            try init_contents_dir(cwd);
            return;
        } else {
            std.debug.print("fatal: unknown argument: {s}\n", .{arg});
            return;
        }
    }

    var found_vec_contents_dir = if(cwd.access(".vec/", .{.mode = .read_only})) |_| true else |_| false;
    while (!found_vec_contents_dir and !std.mem.eql(u8, cwd_path, "/")) {
        cwd = try cwd.openDir("..", .{});
        cwd_path = try cwd.realpath(".", &path_buf);
        found_vec_contents_dir = if(cwd.access(".vec/", .{.mode = .read_only})) |_| true else |_| false;
    }
    if (!found_vec_contents_dir) {
        std.debug.print("fatal: not found in current directory (or any of the parent directories): .vec\n", .{});
        return;
    } 
}
