// randombytes() backend for TweetNaCl on HarmonyOS Next.
// Reads from /dev/urandom. Aborts on failure — callers of
// crypto_box_keypair / crypto_sign_keypair depend on fresh entropy and
// must never proceed with deterministic bytes.

#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

void randombytes(unsigned char *out, unsigned long long n) {
  int fd = open("/dev/urandom", O_RDONLY);
  if (fd < 0) abort();
  while (n > 0) {
    ssize_t r = read(fd, out, n);
    if (r <= 0) {
      close(fd);
      abort();
    }
    out += r;
    n -= (unsigned long long)r;
  }
  close(fd);
}
