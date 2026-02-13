# vec
A simple version control system written in [zig](https://ziglang.org/), built to learn internal workings of modern vcs tools like [git](https://git-scm.com/).

## Current Features
- Status: lists status of working directory compared to previous commit
    - Untracked files/directories
    - Modified files/directories
    - Deleted files/directories
- Commit: takes snapshot of entire working directory

## Planned Features
- [ ] Commit History
- [ ] Object Compression: Reduce storage size of stored objects
- [ ] Staging area
- [ ] Diff Support: Show difference between working directory and previous commit

## Limitations
- Only works on Linux
