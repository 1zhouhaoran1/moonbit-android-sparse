export const CHUNK_KINDS = ['RAW', 'FILL', 'DONT_CARE', 'CRC32'] as const;
export type ChunkKind = (typeof CHUNK_KINDS)[number];

export interface Chunk {
  index: number;
  kind: ChunkKind;
  inputOffset: string;
  outputOffset: string;
  blocks: number;
  totalSize: number;
}

export interface InspectionReport {
  ok: true;
  header: {
    majorVersion: number;
    minorVersion: number;
    blockSize: number;
    totalBlocks: number;
    totalChunks: number;
    expandedBytes: string;
    imageChecksum: string;
  };
  chunks: Chunk[];
  inputBytes: string;
  outputBytes: string;
  chunksRead: number;
  crcStatus: 'verified' | 'unchecked' | 'checking' | 'absent';
  complete: boolean;
}

export interface InspectionFailure {
  ok: false;
  error: { offset: string; message: string };
}

export type WorkerRequest = {
  type: 'inspect';
  file?: File;
  sample: boolean;
  verifyCrc: boolean;
};

export type WorkerResponse =
  | { type: 'start'; name: string; total: number; sample: boolean }
  | { type: 'progress'; read: number; total: number }
  | { type: 'complete'; report: InspectionReport }
  | { type: 'error'; error: InspectionFailure['error'] };
