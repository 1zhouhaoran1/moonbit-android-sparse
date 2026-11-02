import { useEffect, useMemo, useRef, useState } from 'react';
import type { ChangeEvent, DragEvent } from 'react';
import { CHUNK_KINDS } from './types';
import type { Chunk, ChunkKind, InspectionFailure, InspectionReport, WorkerResponse } from './types';

const PAGE_SIZE = 100;
const kindName = (kind: ChunkKind) => kind === 'DONT_CARE' ? 'SKIP' : kind === 'CRC32' ? 'CRC32' : kind;
const number = (value: number | string) => BigInt(value).toLocaleString('en-US');
const hex = (value: number | string) => `0x${BigInt(value).toString(16).toUpperCase().padStart(8, '0')}`;
const crcLabel = { verified: 'verified', unchecked: 'not checked', checking: 'checking', absent: 'not present' };

function bytes(value: number | string) {
  const size = Number(value);
  if (size < 1024) return `${size} B`;
  const units = ['KiB', 'MiB', 'GiB', 'TiB'];
  const power = Math.min(Math.floor(Math.log2(size) / 10), units.length);
  return `${(size / 1024 ** power).toLocaleString('en-US', { maximumFractionDigits: 2 })} ${units[power - 1]}`;
}

function Icon({ name, size = 18 }: { name: 'file' | 'download' | 'chevron' | 'close'; size?: number }) {
  const paths = {
    file: <><path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z" /><path d="M14 3v6h6M8 14h8M8 17h5" /></>,
    download: <><path d="M12 3v12m-5-5 5 5 5-5M4 16v4h16v-4" /></>,
    chevron: <path d="m9 5 7 7-7 7" />,
    close: <path d="m6 6 12 12M6 18 18 6" />,
  };
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}

function AllocationMap({ chunks, onSelect, selected }: { chunks: Chunk[]; onSelect: (chunk: Chunk) => void; selected: number | null }) {
  const segments = useMemo(() => {
    const groupSize = Math.max(1, Math.ceil(chunks.length / 240));
    const result = [];
    for (let i = 0; i < chunks.length; i += groupSize) {
      const group = chunks.slice(i, i + groupSize);
      const kinds = new Set(group.map(chunk => chunk.kind));
      result.push({ first: group[0], last: group.at(-1)!, blocks: group.reduce((sum, chunk) => sum + chunk.blocks, 0), kind: kinds.size === 1 ? group[0].kind : 'MIXED' });
    }
    return result;
  }, [chunks]);

  return <div>
    <div className="allocation-track" role="group" aria-label="Logical block allocation. Select a segment to locate its first chunk in the ledger.">
      {segments.map(segment => <button
        key={segment.first.index}
        type="button"
        className={`allocation-segment kind-${segment.kind} ${selected !== null && selected >= segment.first.index && selected <= segment.last.index ? 'is-selected' : ''}`}
        style={{ flexGrow: segment.blocks, flexBasis: segment.blocks === 0 ? 4 : 0 }}
        onClick={() => onSelect(segment.first)}
        aria-label={segment.first.index === segment.last.index
          ? `Chunk ${segment.first.index + 1}, ${kindName(segment.first.kind)}, ${number(segment.blocks)} blocks`
          : `Chunks ${segment.first.index + 1} to ${segment.last.index + 1}, ${segment.kind === 'MIXED' ? 'mixed types' : kindName(segment.first.kind)}, ${number(segment.blocks)} blocks`}
        title={`#${segment.first.index + 1}${segment.first.index === segment.last.index ? '' : `–${segment.last.index + 1}`} · ${segment.kind === 'MIXED' ? 'MIXED' : kindName(segment.first.kind)} · ${number(segment.blocks)} blocks`}
      />)}
    </div>
    <div className="allocation-scale data"><span>0</span><span>{number(chunks.reduce((sum, chunk) => sum + chunk.blocks, 0))} blocks</span></div>
    <p className="map-note">Widths represent logical blocks. CRC32 markers produce no output.{chunks.length > 240 ? ' Adjacent chunks are grouped; select a group to locate its first chunk.' : ''}</p>
  </div>;
}

export default function App() {
  const [phase, setPhase] = useState<'empty' | 'reading' | 'complete' | 'error' | 'cancelled'>('empty');
  const [report, setReport] = useState<InspectionReport | null>(null);
  const [error, setError] = useState<InspectionFailure['error'] | null>(null);
  const [fileInfo, setFileInfo] = useState<{ name: string; size: number; sample: boolean } | null>(null);
  const [progress, setProgress] = useState({ read: 0, total: 0 });
  const [verifyCrc, setVerifyCrc] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [filter, setFilter] = useState<ChunkKind | 'ALL'>('ALL');
  const [page, setPage] = useState(0);
  const [selected, setSelected] = useState<number | null>(null);
  const workerRef = useRef<Worker | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const sourceFileRef = useRef<File | undefined>(undefined);
  const rowRefs = useRef(new Map<number, HTMLTableRowElement>());
  const dragDepth = useRef(0);
  const loading = phase === 'reading';

  useEffect(() => () => workerRef.current?.terminate(), []);

  function start(file?: File, sample = false, crc = verifyCrc) {
    workerRef.current?.terminate();
    workerRef.current = null;
    sourceFileRef.current = file;
    setPhase('reading');
    setReport(null);
    setError(null);
    setProgress({ read: 0, total: file?.size ?? 0 });
    setFileInfo(file ? { name: file.name, size: file.size, sample: false } : { name: 'synthetic-example.sparse', size: 0, sample: true });
    setFilter('ALL');
    setPage(0);
    setSelected(null);
    try {
      const worker = new Worker(new URL('./inspector.worker.ts', import.meta.url), { type: 'module' });
      workerRef.current = worker;
      worker.onmessage = ({ data }: MessageEvent<WorkerResponse>) => {
        if (workerRef.current !== worker) return;
        if (data.type === 'start') {
          setFileInfo({ name: data.name, size: data.total, sample: data.sample });
          setProgress({ read: 0, total: data.total });
        } else if (data.type === 'progress') setProgress({ read: data.read, total: data.total });
        else if (data.type === 'complete') {
          setReport(data.report);
          setPhase('complete');
          worker.terminate();
          workerRef.current = null;
        } else if (data.type === 'error') {
          setError(data.error);
          setPhase('error');
          worker.terminate();
          workerRef.current = null;
        }
      };
      worker.onerror = () => {
        if (workerRef.current !== worker) return;
        setError({ offset: '0', message: 'The inspection worker could not run. Reload the page and choose the file again.' });
        setPhase('error');
        worker.terminate();
        workerRef.current = null;
      };
      worker.postMessage({ type: 'inspect', file, sample, verifyCrc: crc });
    } catch (failure) {
      setError({ offset: '0', message: failure instanceof Error ? failure.message : 'This browser cannot start the inspection worker.' });
      setPhase('error');
    }
  }

  function cancel() {
    workerRef.current?.terminate();
    workerRef.current = null;
    setPhase('cancelled');
  }

  function selectFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.currentTarget.files?.[0];
    if (file) start(file);
    event.currentTarget.value = '';
  }

  function drop(event: DragEvent) {
    event.preventDefault();
    dragDepth.current = 0;
    setDragging(false);
    if (event.dataTransfer.files.length === 1) start(event.dataTransfer.files[0]);
    else if (event.dataTransfer.files.length > 1) {
      workerRef.current?.terminate();
      workerRef.current = null;
      setError({ offset: '0', message: 'Choose one sparse image at a time.' });
      setPhase('error');
      setReport(null);
      setFileInfo(null);
      sourceFileRef.current = undefined;
    }
  }

  function exportReport() {
    if (!report) return;
    const objectUrl = URL.createObjectURL(new Blob([JSON.stringify({ source: fileInfo, ...report }, null, 2)], { type: 'application/json' }));
    const anchor = document.createElement('a');
    anchor.href = objectUrl;
    anchor.download = `${fileInfo?.name ?? 'sparse-image'}.report.json`;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
  }

  const chunks = report?.chunks ?? [];
  const filtered = useMemo(() => chunks.filter(chunk => filter === 'ALL' || chunk.kind === filter), [chunks, filter]);
  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const visible = filtered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);
  const totals = useMemo(() => CHUNK_KINDS.map(kind => ({
    kind,
    count: chunks.filter(chunk => chunk.kind === kind).length,
    blocks: chunks.reduce((sum, chunk) => sum + (chunk.kind === kind ? chunk.blocks : 0), 0),
  })), [chunks]);

  function selectChunk(chunk: Chunk) {
    setFilter('ALL');
    setPage(Math.floor(chunks.findIndex(item => item.index === chunk.index) / PAGE_SIZE));
    setSelected(chunk.index);
  }

  useEffect(() => {
    if (selected !== null) rowRefs.current.get(selected)?.scrollIntoView({ block: 'nearest', behavior: 'instant' });
  }, [selected, page]);

  const percent = progress.total ? Math.min(100, Math.floor(progress.read / progress.total * 100)) : 0;
  const status = loading ? `Reading ${percent}%` : phase === 'complete' ? 'Structure valid' : phase === 'cancelled' ? 'Inspection cancelled' : phase === 'error' ? 'Inspection stopped' : 'No file selected';

  return <div className="app-shell min-h-screen flex flex-col">
    <a className="skip-link" href="#inspector">Skip to inspector</a>
    <header className="app-header flex items-center justify-between gap-4">
      <div className="brand flex items-center gap-3"><span className="brand-mark" aria-hidden="true"><span /><span /><span /></span><span>MoonBit <span className="brand-divider">/</span> <strong>Android Sparse</strong></span></div>
      <span className="version-label">SPARSE v1</span>
    </header>

    <main id="inspector" className="workspace flex-1" onDragOver={event => { event.preventDefault(); event.dataTransfer.dropEffect = 'copy'; }} onDragEnter={event => { event.preventDefault(); if (event.dataTransfer.types.includes('Files')) { dragDepth.current += 1; setDragging(true); } }} onDragLeave={() => { dragDepth.current -= 1; if (dragDepth.current <= 0) setDragging(false); }} onDrop={drop}>
      <div className="page-title flex items-center justify-between gap-4"><h1>Image inspector</h1><span className="local-indicator"><span aria-hidden="true" />Local files only</span></div>
      <section className="controls" aria-label="Image selection">
        <div className="control-actions flex flex-wrap items-center gap-3">
          <input ref={inputRef} type="file" onChange={selectFile} hidden aria-label="Choose a sparse image" />
          <button className="button button-primary" type="button" onClick={() => inputRef.current?.click()}><Icon name="file" />{fileInfo ? 'Choose another file' : 'Choose image'}</button>
          <button className="button button-secondary" type="button" onClick={() => start(undefined, true)} disabled={loading}>Run synthetic example</button>
          <label className="crc-control"><input type="checkbox" checked={verifyCrc} disabled={loading} onChange={event => { const checked = event.target.checked; setVerifyCrc(checked); if (fileInfo) start(sourceFileRef.current, fileInfo.sample, checked); }} />Verify CRC32</label>
        </div>
        <div className="control-notes"><span>Files stay in this browser.</span><span>Limits: 10,000 chunks · 64 GiB logical · 256 MiB CRC work</span></div>
      </section>

      {dragging && <div className="drop-overlay"><span>Drop one sparse image</span></div>}

      {phase === 'empty' && <div className="empty-canvas"><div className="empty-target"><span className="drop-target-icon"><Icon name="file" size={24} /></span><button className="text-button" onClick={() => inputRef.current?.click()}>Choose image</button><span>or drop a file here</span></div></div>}

      {fileInfo && <section className="file-summary" aria-label="Current image">
        <div className="file-identity"><Icon name="file" size={20} /><span className="file-name" title={fileInfo.name}>{fileInfo.name}</span>{fileInfo.sample && <span className="synthetic-label">Synthetic</span>}<span className="file-size data">{bytes(fileInfo.size)}</span></div>
        <div className="file-status"><span className={`status-label status-${phase}`} role="status">{status}</span>{loading && <button type="button" className="button button-small" onClick={cancel}><Icon name="close" size={14} />Cancel</button>}{report && <button type="button" className="button button-small" onClick={exportReport}><Icon name="download" size={15} />Export JSON</button>}</div>
        {loading && <div className="progress-row"><progress aria-label="Image inspection progress" max={Math.max(progress.total, 1)} value={progress.read} /><span className="data">{bytes(progress.read)} / {bytes(progress.total)}</span></div>}
      </section>}

      {phase === 'error' && error && <section className="error-report" role="alert"><h2>Image could not be inspected</h2><p>{error.message}</p><p className="data">Input offset {hex(error.offset)} · {number(error.offset)} bytes</p><button className="text-button" type="button" onClick={() => inputRef.current?.click()}>Choose another file</button></section>}
      {phase === 'cancelled' && <div className="cancelled-state"><p>Inspection cancelled.</p><button className="text-button" type="button" onClick={() => inputRef.current?.click()}>Choose an image</button></div>}

      {report && <div className="report-content">
        <section className="header-section" aria-labelledby="header-heading">
          <div className="section-heading"><h2 id="header-heading">Image header</h2><span className={`crc-status ${report.crcStatus === 'verified' ? 'is-verified' : ''}`}>CRC32 {crcLabel[report.crcStatus]}</span></div>
          <dl className="header-ledger">
            <div><dt>Format</dt><dd>Android sparse <span className="data">{report.header.majorVersion}.{report.header.minorVersion}</span></dd></div>
            <div><dt>Block size</dt><dd className="data">{number(report.header.blockSize)} <span className="unit">bytes</span></dd></div>
            <div><dt>Logical size</dt><dd className="data" title={`${number(report.header.expandedBytes)} bytes`}>{bytes(report.header.expandedBytes)}</dd></div>
            <div><dt>Total blocks</dt><dd className="data">{number(report.header.totalBlocks)}</dd></div>
            <div><dt>Chunks</dt><dd className="data">{number(report.chunksRead)} <span className="unit">/ {number(report.header.totalChunks)}</span></dd></div>
            <div><dt>Header checksum</dt><dd className="data">0x{report.header.imageChecksum.toUpperCase().padStart(8, '0')}</dd></div>
          </dl>
        </section>

        <section className="allocation-section" aria-labelledby="allocation-heading">
          <div className="section-heading"><h2 id="allocation-heading">Logical allocation</h2><span className="section-caption">Select a segment to locate its chunk</span></div>
          <AllocationMap chunks={chunks} onSelect={selectChunk} selected={selected} />
          <ul className="allocation-legend">{totals.map(total => <li key={total.kind}><span className={`legend-swatch kind-${total.kind}`} aria-hidden="true" /><span>{kindName(total.kind)}</span><span className="data legend-count">{number(total.count)} {total.count === 1 ? 'chunk' : 'chunks'}</span><span className="data legend-blocks">{number(total.blocks)} blocks</span></li>)}</ul>
        </section>

        <section className="chunk-section" aria-labelledby="chunk-heading">
          <div className="section-heading ledger-heading"><div className="flex items-baseline gap-3"><h2 id="chunk-heading">Chunk ledger</h2><span className="section-caption data">{number(filtered.length)} {filtered.length === 1 ? 'entry' : 'entries'}</span></div><label className="filter-control">Type <select value={filter} onChange={event => { setFilter(event.target.value as ChunkKind | 'ALL'); setPage(0); setSelected(null); }}><option value="ALL">All types</option>{CHUNK_KINDS.map(kind => <option key={kind} value={kind}>{kindName(kind)}</option>)}</select></label></div>
          <div className="table-scroll" role="region" aria-label="Chunk ledger; scroll horizontally on small screens" tabIndex={0}>
            <table><caption className="sr-only">Chunk types, offsets, logical block counts and stored byte lengths. Offsets are hexadecimal.</caption><thead><tr><th scope="col">Chunk</th><th scope="col">Type</th><th scope="col">Input offset</th><th scope="col">Output offset</th><th scope="col" className="numeric">Blocks</th><th scope="col" className="numeric">Stored bytes</th></tr></thead><tbody>{visible.map(chunk => <tr key={chunk.index} className={selected === chunk.index ? 'selected-row' : ''} ref={node => { if (node) rowRefs.current.set(chunk.index, node); else rowRefs.current.delete(chunk.index); }}><th scope="row"><button className="row-select data" aria-label={`Select chunk ${chunk.index + 1}`} aria-pressed={selected === chunk.index} onClick={() => setSelected(chunk.index)}>#{chunk.index + 1}</button></th><td><span className={`kind-label kind-text-${chunk.kind}`}>{kindName(chunk.kind)}</span></td><td className="data">{hex(chunk.inputOffset)}</td><td className="data">{hex(chunk.outputOffset)}</td><td className="numeric data">{number(chunk.blocks)}</td><td className="numeric data">{number(chunk.totalSize)}</td></tr>)}</tbody></table>
            {visible.length === 0 && <p className="no-entries">No {filter === 'ALL' ? '' : kindName(filter)} chunks.</p>}
          </div>
          <div className="table-footer"><span className="data">{filtered.length ? `${page * PAGE_SIZE + 1}–${Math.min((page + 1) * PAGE_SIZE, filtered.length)} of ${number(filtered.length)}` : '0 entries'}</span>{pageCount > 1 && <div className="pagination"><button className="button button-small" disabled={page === 0} onClick={() => setPage(current => current - 1)} aria-label="Previous page"><span className="previous-icon"><Icon name="chevron" size={14} /></span>Previous</button><span className="data">{page + 1} / {pageCount}</span><button className="button button-small" disabled={page + 1 >= pageCount} onClick={() => setPage(current => current + 1)}>Next<Icon name="chevron" size={14} /></button></div>}</div>
        </section>
      </div>}
    </main>
    <footer className="app-footer"><span>MoonBit codec · local inspection</span><span>SKIP preserves holes; it does not mean zero-filled data.</span></footer>
  </div>;
}
