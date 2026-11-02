import {
  create_inspector,
  dispose_inspector,
  feed_inspector,
  finish_inspector,
  make_sample,
} from './generated/sparse.js';
import type { InspectionFailure, InspectionReport, WorkerRequest, WorkerResponse } from './types';

const SLICE_BYTES = 1024 * 1024;
const send = (message: WorkerResponse) => self.postMessage(message);

self.onmessage = async ({ data }: MessageEvent<WorkerRequest>) => {
  if (data.type !== 'inspect') return;
  let handle: number | undefined;
  let read = 0;
  try {
    const sample = data.sample ? make_sample() : undefined;
    const source = sample
      ? new File([new Uint8Array(sample)], 'synthetic-example.sparse', { type: 'application/octet-stream' })
      : data.file;
    if (!source) throw new Error('Choose a local image to inspect.');
    send({ type: 'start', name: source.name, total: source.size, sample: data.sample });
    handle = create_inspector(data.verifyCrc);
    let lastProgress = 0;
    while (read < source.size) {
      const bytes = new Uint8Array(await source.slice(read, read + SLICE_BYTES).arrayBuffer());
      const result = JSON.parse(feed_inspector(handle, bytes)) as { ok: true } | InspectionFailure;
      if (!result.ok) {
        send({ type: 'error', error: result.error });
        return;
      }
      read += bytes.byteLength;
      const now = performance.now();
      if (now - lastProgress >= 80 || read === source.size) {
        send({ type: 'progress', read, total: source.size });
        lastProgress = now;
      }
    }
    const result = JSON.parse(finish_inspector(handle)) as InspectionReport | InspectionFailure;
    if (!result.ok) send({ type: 'error', error: result.error });
    else send({ type: 'complete', report: result });
  } catch (error) {
    send({ type: 'error', error: {
      offset: String(read),
      message: error instanceof Error ? error.message : 'The file could not be read. Choose it again.',
    } });
  } finally {
    if (handle !== undefined) dispose_inspector(handle);
  }
};
