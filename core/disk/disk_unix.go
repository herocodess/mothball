//go:build darwin || linux || freebsd

// Package disk reports free space.
package disk

import "syscall"

// Free returns the bytes available to the current user on the disk holding path.
func Free(path string) (uint64, error) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return 0, err
	}
	return uint64(st.Bavail) * uint64(st.Bsize), nil
}
