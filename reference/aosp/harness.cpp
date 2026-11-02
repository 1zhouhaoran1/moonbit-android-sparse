// Original fixture harness. Link against the untouched pinned AOSP libsparse.
// sparse_file_import(..., true, true) is the CRC oracle, not simg2img.
#include <sparse/sparse.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

static int save(const char* path, const std::vector<unsigned char>& bytes) {
  int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (fd < 0) { perror(path); return 1; }
  size_t at = 0;
  while (at < bytes.size()) {
    ssize_t n = write(fd, bytes.data() + at, bytes.size() - at);
    if (n <= 0) { perror("write"); close(fd); return 1; }
    at += static_cast<size_t>(n);
  }
  return close(fd) != 0;
}

static int make(const char* sparse_path, const char* raw_path, bool mixed) {
  constexpr unsigned int block = 4096;
  std::vector<unsigned char> expected((mixed ? 8 : 2) * block, 0);
  std::vector<unsigned char> literal(block);
  for (size_t i = 0; i < literal.size(); ++i) {
    literal[i] = static_cast<unsigned char>((i * 37 + i / 17) % 256);
    expected[i] = literal[i];
  }
  const size_t fill_end = (mixed ? 3 : 2) * block;
  for (size_t i = block; i < fill_end; ++i) {
    expected[i] = static_cast<unsigned char>(0x12345678U >> ((i % 4) * 8));
  }
  sparse_file* image = sparse_file_new(block, expected.size());
  if (!image) return 1;
  int result = sparse_file_add_data(image, literal.data(), literal.size(), 0);
  if (!result) result = sparse_file_add_fill(image, 0x12345678U, (mixed ? 2 : 1) * block, 1);
  if (!result && mixed) result = sparse_file_add_fill(image, 0, 2 * block, 6);
  int fd = open(sparse_path, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (fd < 0) { perror(sparse_path); sparse_file_destroy(image); return 1; }
  if (!result) result = sparse_file_write(image, fd, false, true, true);
  if (close(fd)) result = -1;
  sparse_file_destroy(image);
  return result ? 1 : save(raw_path, expected);
}

int main(int argc, char** argv) {
  if (argc == 4 && (!strcmp(argv[1], "make") || !strcmp(argv[1], "make-mixed"))) {
    return make(argv[2], argv[3], !strcmp(argv[1], "make-mixed"));
  }
  if ((argc == 3 && !strcmp(argv[1], "verify")) ||
      (argc == 4 && !strcmp(argv[1], "expand"))) {
    int input = open(argv[2], O_RDONLY);
    if (input < 0) { perror(argv[2]); return 1; }
    sparse_file* image = sparse_file_import(input, true, true);
    if (!image) { close(input); return 1; }
    int result = 0;
    if (argc == 4) {
      int output = open(argv[3], O_WRONLY | O_CREAT | O_EXCL, 0600);
      if (output < 0) { perror(argv[3]); result = -1; }
      else {
        result = sparse_file_write(image, output, false, false, false);
        if (close(output)) result = -1;
      }
    }
    sparse_file_destroy(image);
    close(input);
    return result ? 1 : 0;
  }
  fprintf(stderr, "usage: oracle verify sparse | expand sparse raw | make sparse raw | make-mixed sparse raw\n");
  return 2;
}
