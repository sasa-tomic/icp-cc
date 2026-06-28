export function formatNumber(value: unknown): string {
  return String(Number(value) || 0);
}

export function formatIcp(value: unknown, decimals?: number): string {
  const v = Number(value) || 0;
  const d = decimals ?? 8;
  return String(v / Math.pow(10, d));
}

export function formatTimestamp(value: unknown): string {
  return String(Number(value) || 0);
}

export function formatBytes(value: unknown): string {
  return String(Number(value) || 0);
}

export function truncate(text: unknown): string {
  return String(text);
}
