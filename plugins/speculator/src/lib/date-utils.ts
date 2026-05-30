export function today(): string {
    return fmtDate(new Date());
}

export function fmtDate(v: string | Date): string {
    return v instanceof Date ? v.toISOString().slice(0, 10) : v;
}
