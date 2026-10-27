/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/file.h>
#include <sys/stat.h>

/**
 * Creates a uniquely-named empty file under /tmp.
 *
 * Template is `/tmp/<prefix>-XXXXXX<ext>`. Uses `mkstemps(3)` so the file is
 * created atomically with `O_EXCL` and mode 0600; the fd is immediately
 * closed. Callers that want to write the file (via `fs.writefile` or an
 * external command) overwrite the empty stub.
 *
 * @param prefix  name prefix
 * @param ext     extension, '' for none
 * @param path    receives the path
 * @param len     size of `path`
 * @return        false when the path does not fit or the file cannot be made
 */
bool
tmpfile_create(const char *prefix, const char *ext, char *path, size_t len)
{
	int fd;

	if (snprintf(path, len, "/tmp/%s-XXXXXX%s", prefix, ext) >= (int)len)
		return false;

	fd = mkstemps(path, (int)strlen(ext));
	if (fd < 0)
		return false;

	close(fd);

	return true;
}

/**
 * ucode: `tmpfile_name(prefix, ext)`, see tmpfile_create().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-2 expected: prefix, optional extension)
 * @return       path string, or null on failure
 */
uc_value_t *
uc_ubbf_tmpfile_name(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *prefix = uc_fn_arg(0), *ext = uc_fn_arg(1);
	char path[256];

	if (ucv_type(prefix) != UC_STRING ||
	    !tmpfile_create(ucv_string_get(prefix), (ucv_type(ext) == UC_STRING) ? ucv_string_get(ext) : "",
			    path, sizeof(path)))
		return NULL;

	return ucv_string_new(path);
}

/**
 * Writes `contents` to `path` atomically, or deletes `path` when contents
 * is null or empty. Contents of any other type are refused.
 *
 * Writes to `<path>.tmp`, fsyncs the data and the containing directory, then
 * renames into place. On any failure the temp file is unlinked. When
 * `contents` is null or empty, `path` itself is unlinked (and the directory
 * fsynced), so callers can toggle between "present" and "absent" atomically.
 *
 * The file gets the permission bits of the optional `mode`, default 0644;
 * a file that holds secrets passes 0600.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2-3 expected: path, contents, mode)
 * @return       boolean true on success, false on failure
 */
uc_value_t *
uc_ubbf_write_file_atomic(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *content_val = uc_fn_arg(1);
	uc_value_t *mode_val = uc_fn_arg(2);
	mode_t mode = (ucv_type(mode_val) == UC_INTEGER)
		? (mode_t)(ucv_int64_get(mode_val) & 07777) : 0644;

	if (ucv_type(path_val) != UC_STRING)
		return ucv_boolean_new(false);

	if (!content_val)
		return ucv_boolean_new(file_write_atomic(ucv_string_get(path_val), NULL, 0, mode));

	if (ucv_type(content_val) != UC_STRING)
		return ucv_boolean_new(false);

	return ucv_boolean_new(file_write_atomic(ucv_string_get(path_val),
						 ucv_string_get(content_val),
						 ucv_string_length(content_val), mode));
}

/**
 * Writes a file atomically, or deletes it for empty content; see
 * uc_ubbf_write_file_atomic().
 *
 * @param path         destination file
 * @param content      data, or NULL
 * @param content_len  length of `content`
 * @param mode         permission bits of the file
 * @return             true on success
 */
bool
file_write_atomic(const char *path, const char *content, size_t content_len, mode_t mode)
{
	char tmp_path[512];
	char dir_path[512];
	const char *slash;
	int fd, dir_fd;
	ssize_t n, off;

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
			return false;
		dir_fd = open(dir_path, O_RDONLY | O_DIRECTORY);
		if (dir_fd >= 0) {
			fsync(dir_fd);
			close(dir_fd);
		}
		return true;
	}

	if (snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", path)
	    >= (int)sizeof(tmp_path))
		return false;

	fd = open(tmp_path, O_WRONLY | O_CREAT | O_TRUNC, mode);
	if (fd < 0)
		return false;

	/* A leftover temp file keeps its own mode through O_TRUNC */
	if (fchmod(fd, mode) != 0) {
		close(fd);
		unlink(tmp_path);
		return false;
	}

	off = 0;
	while ((size_t)off < content_len) {
		n = write(fd, content + off, content_len - off);
		if (n <= 0) {
			close(fd);
			unlink(tmp_path);
			return false;
		}
		off += n;
	}

	if (fsync(fd) != 0) {
		close(fd);
		unlink(tmp_path);
		return false;
	}
	close(fd);

	if (rename(tmp_path, path) != 0) {
		unlink(tmp_path);
		return false;
	}

	dir_fd = open(dir_path, O_RDONLY | O_DIRECTORY);
	if (dir_fd >= 0) {
		fsync(dir_fd);
		close(dir_fd);
	}

	return true;
}

