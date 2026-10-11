async function later(): Promise<void> {
  return;
}

export function caller(): void {
  later();
}
