# vec
A simple version control system written in [zig](https://ziglang.org/), built to learn internal workings of modern vcs tools like [git](https://git-scm.com/).

## Current Features
- Status: lists status of working directory compared to previous commit
    - Untracked files/directories
    - Modified files/directories
    - Deleted files/directories
- Commit: takes snapshot of entire working directory
- Log: view commit history

## Planned Features
- [ ] Commit History
    - [x] View commit history
    - [ ] Patch working directory to committed snapshots
- [ ] Object Compression: Reduce storage size of stored objects
- [x] Staging area
- [ ] Diff Support: Show difference between working directory and previous commit

## Limitations
- Only works on Linux
