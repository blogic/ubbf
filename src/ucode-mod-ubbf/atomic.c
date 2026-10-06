/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/file.h>

/**
 * Creates a uniquely-named empty file under /tmp.
 *
 * Template is `/tmp/<prefix>-XXXXXX<ext>`. Uses `mkstemps(3)` so the file is
 * created atomically with `O_EXCL`; the fd is immediately closed. Callers
 * that want to write the file (via `fs.writefile` or an external command)
 * overwrite the empty stub. Returns the full path on success, null on
 * failure or invalid arguments.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-2 expected: prefix, optional .ext)
 * @return       path string, or null on failure
 */
uc_value_t *
uc_ubbf_tmpfile_name(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *prefix_val = uc_fn_arg(0);
	uc_value_t *ext_val = uc_fn_arg(1);
	const char *prefix, *ext = "";
	char path[256];
	int fd;
	size_t ext_len;

	if (ucv_type(prefix_val) != UC_STRING)
		return NULL;

	prefix = ucv_string_get(prefix_val);
	if (ucv_type(ext_val) == UC_STRING)
		ext = ucv_string_get(ext_val);

	ext_len = strlen(ext);
	if (snprintf(path, sizeof(path), "/tmp/%s-XXXXXX%s", prefix, ext)
	    >= (int)sizeof(path))
		return NULL;

	fd = mkstemps(path, (int)ext_len);
	if (fd < 0)
		return NULL;

	close(fd);

	return ucv_string_new(path);
}

/**
 * Writes `contents` to `path` atomically, or deletes `path` when contents
 * is null or empty.
 *
 * Writes to `<path>.tmp`, fsyncs the data and the containing directory, then
 * renames into place. On any failure the temp file is unlinked. When
 * `contents` is null or empty, `path` itself is unlinked (and the directory
 * fsynced), so callers can toggle between "present" and "absent" atomically.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: path, contents)
 * @return       boolean true on success, false on failure
 */
uc_value_t *
uc_ubbf_write_file_atomic(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *content_val = uc_fn_arg(1);
	const char *path, *content = NULL;
	size_t content_len = 0;
	char tmp_path[512];
	char dir_path[512];
	const char *slash;
	int fd, dir_fd;
	ssize_t n, off;

	if (ucv_type(path_val) != UC_STRING)
		return ucv_boolean_new(false);

	path = ucv_string_get(path_val);

	if (ucv_type(content_val) == UC_STRING) {
		content = ucv_string_get(content_val);
		content_len = ucv_string_length(content_val);
	}

	slash = strrchr(path, '/');
	if (slash && (size_t)(slash - path) < sizeof(dir_path)) {
		size_t dlen = slash - path;
		if (dlen == 0) {
			strcpy(dir_path, "/");
		} else {
			memcpy(dir_path, path, dlen);
			dir_path[dlen] = '\0';
		}
	} else {
		strcpy(dir_path, ".");
	}

	if (!content || content_len == 0) {
		if (unlink(path) != 0 && errno != ENOENT)
			return ucv_boolean_new(false);
		dir_fd = open(dir_path, O_RDONLY | O_DIRECTORY);
		if (dir_fd >= 0) {
			fsync(dir_fd);
			close(dir_fd);
		}
		return ucv_boolean_new(true);
	}

	if (snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", path)
	    >= (int)sizeof(tmp_path))
		return ucv_boolean_new(false);

	fd = open(tmp_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0)
		return ucv_boolean_new(false);

	off = 0;
	while ((size_t)off < content_len) {
		n = write(fd, content + off, content_len - off);
		if (n <= 0) {
			close(fd);
			unlink(tmp_path);
			return ucv_boolean_new(false);
		}
		off += n;
	}

	if (fsync(fd) != 0) {
		close(fd);
		unlink(tmp_path);
		return ucv_boolean_new(false);
	}
	close(fd);

	if (rename(tmp_path, path) != 0) {
		unlink(tmp_path);
		return ucv_boolean_new(false);
	}

	dir_fd = open(dir_path, O_RDONLY | O_DIRECTORY);
	if (dir_fd >= 0) {
		fsync(dir_fd);
		close(dir_fd);
	}

	return ucv_boolean_new(true);
}

/**
 * Atomically reads, increments, and writes back an integer counter file.
 *
 * Opens `path` for read-write (creating it if missing), takes an exclusive
 * `flock(2)` for the duration of the read-modify-write cycle, parses the
 * decimal integer content (0 when the file is new or unparseable), writes
 * back `value + 1`, and returns the OLD value. Used to allocate unique
 * IDs across concurrent callers that share the same counter file.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: path)
 * @return       integer counter value before increment, or null on failure
 */
uc_value_t *
uc_ubbf_counter_bump(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);
	const char *path;
	char buf[64];
	int fd;
	ssize_t n;
	long long current = 0;
	long long next;
	int written;

	if (ucv_type(path_val) != UC_STRING)
		return NULL;

	path = ucv_string_get(path_val);

	fd = open(path, O_RDWR | O_CREAT, 0644);
	if (fd < 0)
		return NULL;

	if (flock(fd, LOCK_EX) != 0) {
		close(fd);
		return NULL;
	}

	n = read(fd, buf, sizeof(buf) - 1);
	if (n > 0) {
		buf[n] = '\0';
		char *endp;
		long long v = strtoll(buf, &endp, 10);
		if (endp != buf)
			current = v;
	}

	next = current + 1;
	written = snprintf(buf, sizeof(buf), "%lld\n", next);

	if (lseek(fd, 0, SEEK_SET) != 0 ||
	    ftruncate(fd, 0) != 0 ||
	    write(fd, buf, written) != written ||
	    fsync(fd) != 0) {
		flock(fd, LOCK_UN);
		close(fd);
		return NULL;
	}

	flock(fd, LOCK_UN);
	close(fd);

	return ucv_int64_new(current);
}
