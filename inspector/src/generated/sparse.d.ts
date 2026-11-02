export function create_inspector(verifyCrc: boolean): number;
export function feed_inspector(handle: number, data: Uint8Array): string;
export function finish_inspector(handle: number): string;
export function inspector_report(handle: number): string;
export function dispose_inspector(handle: number): void;
export function make_sample(): Uint8Array;
