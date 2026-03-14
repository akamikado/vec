# vec
A simple version control system written in [zig](https://ziglang.org/), built to learn internal workings of modern vcs tools like [git](https://git-scm.com/).

## Current Features
- Status: Displays state of the working directory relative to the latest commit. It detects:
    - Staged files/directories
    - Untracked files/directories
    - Modified files/directories
    - Deleted files/directories
- Staging area: Supports staging area for preparing changes before committing
- Commit: Creates snapshots of staged files and stores them as versioned objects
- Log: Displays the history of commits in the repository

## Planned Features
- [x] Staging area
- [ ] Diff Support: Show difference between current state of file and state of the file in previous commit
- [ ] Commit History
    - [x] View commit history
    - [ ] Restore working directory to a previous commit snapshot
- [ ] Object Compression: Reduce storage size of stored objects

## Limitations
- Only works on Linux
