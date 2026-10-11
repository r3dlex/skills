export function nested(n: number): number {
  if (n > 0) {
    if (n > 1) {
      if (n > 2) {
        if (n > 3) {
          if (n > 4) {
            if (n > 5) {
              return n;
            }
          }
        }
      }
    }
  }
  return 0;
}
