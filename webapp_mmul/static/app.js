const tabButtons = Array.from(document.querySelectorAll('.tab'));
const panels = {
  matrix: document.getElementById('tab-matrix'),
  fpga: document.getElementById('tab-fpga'),
  docs: document.getElementById('tab-docs'),
  diagram: document.getElementById('tab-diagram'),
};
const startupAlert = document.getElementById('startup-alert');

const dimInput = document.getElementById('dim-input');
const kInput = document.getElementById('k-input');
const nInput = document.getElementById('n-input');
const randMin = document.getElementById('rand-min');
const randMax = document.getElementById('rand-max');
const randSeed = document.getElementById('rand-seed');
const initMatricesBtn = document.getElementById('init-matrices-btn');
const randomMatricesBtn = document.getElementById('random-matrices-btn');
const scriptRandomMatricesBtn = document.getElementById('script-random-matrices-btn');
const uploadMatricesBtn = document.getElementById('upload-matrices-btn');
const scriptDimOverrideInput = document.getElementById('script-dim-override');
const matrixSizeHint = document.getElementById('matrix-size-hint');
const matrixLayout = document.getElementById('matrix-layout');

const matrixAWrap = document.getElementById('matrix-a-wrap');
const matrixBWrap = document.getElementById('matrix-b-wrap');
const matrixCWrap = document.getElementById('matrix-c-wrap');

const runtimeOutput = document.getElementById('runtime-output');
const traceOutput = document.getElementById('trace-output');
const computeBtn = document.getElementById('compute-btn');
const fpgaComputeBtn = document.getElementById('fpga-compute-btn');
const computeBothBtn = document.getElementById('compute-both-btn');
const traceBtn = document.getElementById('trace-btn');
const computeRunStatus = document.getElementById('compute-run-status');

const cpuMs = document.getElementById('cpu-ms');
const cpuGflops = document.getElementById('cpu-gflops');
const fpgaKernelMs = document.getElementById('fpga-kernel-ms');
const fpgaTotalMs = document.getElementById('fpga-total-ms');
const fpgaGbps = document.getElementById('fpga-gbps');
const speedupKernel = document.getElementById('speedup-kernel');
const speedupTotal = document.getElementById('speedup-total');
const speedupDetail = document.getElementById('speedup-detail');

const fpgaDevice = document.getElementById('fpga-device');
const xclbinPath = document.getElementById('xclbin-path');
const benchMode = document.getElementById('bench-mode');
const benchDimInput = document.getElementById('bench-dim');
const benchIterations = document.getElementById('bench-iterations');
const benchBtn = document.getElementById('bench-btn');
const traceRow = document.getElementById('trace-row');
const traceCol = document.getElementById('trace-col');
const uploadAFile = document.getElementById('upload-a-file');
const uploadBFile = document.getElementById('upload-b-file');

const docsSelect = document.getElementById('docs-select');
const docsRender = document.getElementById('docs-render');
const docsMeta = document.getElementById('docs-meta');
const docsToc = document.getElementById('docs-toc');

const diagramSvg = document.getElementById('diagram-svg');
const blockDetails = document.getElementById('block-details');
const flowNotes = document.getElementById('flow-notes');
const diagramBackBtn = document.getElementById('diagram-back-btn');
const diagramZoomOutBtn = document.getElementById('diagram-zoom-out-btn');
const diagramZoomInBtn = document.getElementById('diagram-zoom-in-btn');
const diagramResetBtn = document.getElementById('diagram-reset-btn');
const diagramBreadcrumb = document.getElementById('diagram-breadcrumb');
const diagramZoomReadout = document.getElementById('diagram-zoom-readout');

const themeToggle = document.getElementById('theme-toggle');

const modal = document.getElementById('matrix-modal');
const modalTitle = document.getElementById('modal-title');
const modalMeta = document.getElementById('modal-meta');
const modalWrap = document.getElementById('modal-matrix-wrap');
const modalCloseBtn = document.getElementById('modal-close-btn');
const modalApplyBtn = document.getElementById('modal-apply-btn');
const modalRandomBtn = document.getElementById('modal-random-btn');
const modalEmptyBtn = document.getElementById('modal-empty-btn');
const uploadModal = document.getElementById('upload-modal');
const uploadModalCloseBtn = document.getElementById('upload-modal-close-btn');
const uploadModalPickABtn = document.getElementById('upload-modal-pick-a-btn');
const uploadModalPickBBtn = document.getElementById('upload-modal-pick-b-btn');
const uploadModalApplyBtn = document.getElementById('upload-modal-apply-btn');
const uploadModalAName = document.getElementById('upload-modal-a-name');
const uploadModalBName = document.getElementById('upload-modal-b-name');

const INLINE_EDIT_THRESHOLD = 10;
const MODAL_FULL_EDIT_MAX = 64;
const PREVIEW_DIM = 8;
const MAX_DIM = 1024;
const BENCHMARK_DIM_MAX = 10000;
const MIN_DIM = 1;
const DIAGRAM_MIN_SCALE = 0.02;
const DIAGRAM_MAX_SCALE = 5.0;
const DIAGRAM_FIT_MAX_SCALE = 3.2;

const groupColors = {
  software: '#0f766e',
  platform: '#1d4ed8',
  memory: '#0ea5a6',
  control: '#b45309',
  datapath: '#16a34a',
  compute: '#9333ea',
  observability: '#475569',
  internals: '#9d174d',
};

let docsCache = [];
let diagramModel = null;
let diagramViewStack = [];
let diagramPanGroup = null;
let diagramScale = 1.0;
let diagramTx = 0;
let diagramTy = 0;
let diagramDragging = false;
let diagramLastX = 0;
let diagramLastY = 0;
let diagramFitRaf = 0;

let currentDim = 4;
let currentM = 4;
let currentK = 4;
let currentN = 4;
let matrixA = [];
let matrixB = [];
let matrixC = [];
let computeRunning = false;
let computeStatusTimer = 0;
let activeGeneratedSource = null;
const perfState = {
  cpuMs: null,
  cpuGflops: null,
  cpuDim: null,
  fpgaKernelMs: null,
  fpgaTotalMs: null,
  fpgaGbps: null,
  fpgaDim: null,
  lastDim: null,
  lastIterations: null,
};

const modalState = {
  key: 'A',
  working: [],
};

const uploadModalState = {
  fileA: null,
  fileB: null,
};

function setActiveTab(tabKey) {
  tabButtons.forEach((btn) => btn.classList.toggle('active', btn.dataset.tab === tabKey));
  Object.entries(panels).forEach(([key, panel]) => panel.classList.toggle('active', key === tabKey));
  if (tabKey === 'docs') {
    loadDocsList({ preserveSelection: true, autoLoadSelected: true }).catch((err) => {
      docsMeta.textContent = `ERROR: ${err.message}`;
    });
  }
  if (tabKey === 'diagram' && diagramModel) {
    scheduleDiagramFit();
  }
}

for (const button of tabButtons) {
  button.addEventListener('click', () => setActiveTab(button.dataset.tab));
}

function appendOutput(text) {
  runtimeOutput.textContent = `${text}\n${runtimeOutput.textContent}`.slice(0, 20000);
}

function renderStartupGate(health) {
  if (!startupAlert) return;
  const gate = health && typeof health === 'object' ? health.startup_gate : null;
  if (!gate || typeof gate !== 'object') {
    startupAlert.classList.add('hidden');
    startupAlert.textContent = '';
    return;
  }

  const status = String(gate.status || '').toLowerCase();
  const message = String(gate.message || '').trim();
  if (status !== 'warn') {
    startupAlert.classList.add('hidden');
    startupAlert.textContent = '';
    return;
  }

  const details = message || 'Startup xclbin validation failed. Program the expected xclbin before running FPGA actions.';
  startupAlert.textContent = `Startup warning: ${details}`;
  startupAlert.classList.remove('hidden');
}

function matrixRows(matrix) {
  return Array.isArray(matrix) ? matrix.length : 0;
}

function matrixCols(matrix) {
  const rows = matrixRows(matrix);
  return rows > 0 && Array.isArray(matrix[0]) ? matrix[0].length : 0;
}

function matrixShapeString(matrix) {
  return `${matrixRows(matrix)}x${matrixCols(matrix)}`;
}

function shapeTupleString(m, k, n) {
  return `A=${m}x${k}, B=${k}x${n}, C=${m}x${n}`;
}

function makeZeroMatrixRect(rows, cols) {
  return Array.from({ length: rows }, () => Array.from({ length: cols }, () => 0));
}

function makeZeroMatrix(dim) {
  return makeZeroMatrixRect(dim, dim);
}

function cloneMatrix(m) {
  return m.map((row) => row.slice());
}

function createSeededRng(seedValue) {
  let t = (seedValue >>> 0) || 1;
  return () => {
    t += 0x6D2B79F5;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r ^= r + Math.imul(r ^ (r >>> 7), 61 | r);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

function randInt(minVal, maxVal, rng) {
  return Math.floor(rng() * (maxVal - minVal + 1)) + minVal;
}

function fillRandomMatrixInPlace(matrix, seedOffset = 0) {
  const minV = Number(randMin.value);
  const maxV = Number(randMax.value);
  if (!Number.isFinite(minV) || !Number.isFinite(maxV)) {
    throw new Error('Random min/max must be numeric');
  }
  if (maxV < minV) {
    throw new Error('Random max must be >= random min');
  }
  const seedRaw = randSeed.value.trim();
  const rng = seedRaw ? createSeededRng(Number(seedRaw) + seedOffset) : Math.random;

  for (let r = 0; r < matrix.length; r++) {
    for (let c = 0; c < matrix[r].length; c++) {
      matrix[r][c] = randInt(minV, maxV, rng);
    }
  }
}

function clampDim(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return currentDim;
  return Math.max(MIN_DIM, Math.min(MAX_DIM, Math.floor(n)));
}

function clampShape(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(MIN_DIM, Math.min(MAX_DIM, Math.floor(n)));
}

function syncShapeInputs() {
  dimInput.value = String(currentM);
  if (kInput) kInput.value = String(currentK);
  if (nInput) nInput.value = String(currentN);
}

function getRequestedShapes() {
  return {
    m: clampShape(dimInput.value, currentM),
    k: clampShape(kInput ? kInput.value : currentK, currentK),
    n: clampShape(nInput ? nInput.value : currentN, currentN),
  };
}

function setMatrixShapes(m, k, n, resetData = true) {
  currentM = clampShape(m, currentM);
  currentK = clampShape(k, currentK);
  currentN = clampShape(n, currentN);
  currentDim = Math.max(currentM, currentK, currentN);
  syncShapeInputs();

  traceRow.max = String(Math.max(0, currentM - 1));
  traceCol.max = String(Math.max(0, currentN - 1));
  if (Number(traceRow.value) >= currentM) traceRow.value = '0';
  if (Number(traceCol.value) >= currentN) traceCol.value = '0';

  if (resetData) {
    matrixA = makeZeroMatrixRect(currentM, currentK);
    matrixB = makeZeroMatrixRect(currentK, currentN);
    matrixC = makeZeroMatrixRect(currentM, currentN);
  }

  renderAllMatrices();

  if (diagramModel && currentDiagramViewId && currentDiagramViewId() === 'pe_mesh_grid') {
    drawCurrentDiagramView();
  }
}

function setDimension(dim, resetData = true) {
  const d = clampDim(dim);
  setMatrixShapes(d, d, d, resetData);
}

function matrixToTable(matrix, {
  editable = false,
  onCellChange = null,
  limitDim = null,
  readOnly = false,
  idPrefix = 'm',
} = {}) {
  const rows = matrixRows(matrix);
  const cols = matrixCols(matrix);
  const renderRows = limitDim ? Math.min(rows, limitDim) : rows;
  const renderCols = limitDim ? Math.min(cols, limitDim) : cols;

  const table = document.createElement('table');
  for (let r = 0; r < renderRows; r++) {
    const tr = document.createElement('tr');
    for (let c = 0; c < renderCols; c++) {
      const td = document.createElement('td');
      const input = document.createElement('input');
      input.type = 'number';
      input.step = 'any';
      input.value = String(matrix[r][c]);
      input.dataset.r = String(r);
      input.dataset.c = String(c);
      input.id = `${idPrefix}_${r}_${c}`;
      input.readOnly = readOnly || !editable;
      if (editable && onCellChange) {
        input.addEventListener('input', () => {
          const v = Number(input.value);
          onCellChange(r, c, Number.isFinite(v) ? v : 0);
        });
      }
      td.appendChild(input);
      tr.appendChild(td);
    }
    table.appendChild(tr);
  }
  return table;
}

function renderMatrixWrap({ wrap, matrix, editableInline, matrixName, key }) {
  wrap.innerHTML = '';

  if (editableInline) {
    const table = matrixToTable(matrix, {
      editable: true,
      readOnly: false,
      idPrefix: key,
      onCellChange: (r, c, v) => {
        clearActiveGeneratedSource();
        matrix[r][c] = v;
      },
    });
    wrap.appendChild(table);
    return;
  }

  const previewTable = matrixToTable(matrix, {
    editable: false,
    readOnly: true,
    limitDim: PREVIEW_DIM,
    idPrefix: `${key}_preview`,
  });
  wrap.appendChild(previewTable);

  if (matrixRows(matrix) > PREVIEW_DIM || matrixCols(matrix) > PREVIEW_DIM) {
    const note = document.createElement('div');
    note.className = 'matrix-preview-note';
    note.textContent = `${matrixName} is ${matrixShapeString(matrix)}. Showing ${PREVIEW_DIM}x${PREVIEW_DIM} preview. Use Open Editor for full matrix edits.`;
    wrap.appendChild(note);
  }
}

function renderResultMatrix() {
  matrixCWrap.innerHTML = '';
  const cRows = matrixRows(matrixC);
  const cCols = matrixCols(matrixC);
  const editableInline = Math.max(cRows, cCols) <= INLINE_EDIT_THRESHOLD;
  if (editableInline) {
    const table = matrixToTable(matrixC, { editable: false, readOnly: true, idPrefix: 'c' });
    matrixCWrap.appendChild(table);
    return;
  }

  const preview = matrixToTable(matrixC, {
    editable: false,
    readOnly: true,
    limitDim: PREVIEW_DIM,
    idPrefix: 'c_preview',
  });
  matrixCWrap.appendChild(preview);

  const note = document.createElement('div');
  note.className = 'matrix-preview-note';
  note.textContent = `Result matrix is ${matrixShapeString(matrixC)}. Showing ${PREVIEW_DIM}x${PREVIEW_DIM} preview.`;
  matrixCWrap.appendChild(note);
}

function renderAllMatrices() {
  const largeMode = Math.max(currentM, currentK, currentN) > INLINE_EDIT_THRESHOLD;
  matrixLayout.classList.toggle('large', largeMode);
  const baseHint = largeMode
    ? `Large matrix mode enabled (${shapeTupleString(currentM, currentK, currentN)}). Use Open Editor or Upload A/B. FPGA path auto-zero-pads rectangular inputs to square N=max(M,K,N). Python script generation supports larger square N up to ${BENCHMARK_DIM_MAX}.`
    : `Inline editing enabled (${shapeTupleString(currentM, currentK, currentN)}). Upload A/B (CSV or JSON) is available. FPGA path auto-zero-pads rectangular inputs to square N=max(M,K,N).`;
  const sourceHint = (activeGeneratedSource && activeGeneratedSource.mode === 'files')
    ? ` Active script-generated source selected: N=${activeGeneratedSource.dim} (A/B files on server).`
    : '';
  matrixSizeHint.textContent = `${baseHint}${sourceHint}`;

  renderMatrixWrap({
    wrap: matrixAWrap,
    matrix: matrixA,
    editableInline: !largeMode,
    matrixName: 'Matrix A',
    key: 'a',
  });

  renderMatrixWrap({
    wrap: matrixBWrap,
    matrix: matrixB,
    editableInline: !largeMode,
    matrixName: 'Matrix B',
    key: 'b',
  });

  renderResultMatrix();
}

function resetTimingCards() {
  cpuMs.textContent = '-';
  cpuGflops.textContent = '-';
  fpgaKernelMs.textContent = '-';
  fpgaTotalMs.textContent = '-';
  fpgaGbps.textContent = '-';
  speedupKernel.textContent = '-';
  speedupTotal.textContent = '-';
  speedupDetail.textContent = 'Run CPU compute and FPGA benchmark to generate a detailed speedup breakdown.';
  perfState.cpuMs = null;
  perfState.cpuGflops = null;
  perfState.cpuDim = null;
  perfState.fpgaKernelMs = null;
  perfState.fpgaTotalMs = null;
  perfState.fpgaGbps = null;
  perfState.fpgaDim = null;
  perfState.lastDim = null;
  perfState.lastIterations = null;
}

function formatSpeedup(speedupValue) {
  if (!Number.isFinite(speedupValue) || speedupValue <= 0) return '-';
  if (speedupValue >= 100) return `${speedupValue.toFixed(0)}x`;
  if (speedupValue >= 10) return `${speedupValue.toFixed(1)}x`;
  return `${speedupValue.toFixed(2)}x`;
}

function formatDuration(ms) {
  if (!Number.isFinite(ms)) return '-';
  if (ms >= 1000) {
    return `${ms / 1000} s`;
  }
  return `${ms.toFixed(3)} ms`;
}

function clearActiveGeneratedSource() {
  activeGeneratedSource = null;
}

function updateSpeedupAnalysis() {
  if (!speedupDetail) return;
  const cpu = perfState.cpuMs;
  const fk = perfState.fpgaKernelMs;
  const ft = perfState.fpgaTotalMs;
  const cpuDim = perfState.cpuDim;
  const fpgaDim = perfState.fpgaDim;

  if (!Number.isFinite(cpu) || cpu <= 0) {
    speedupKernel.textContent = '-';
    speedupTotal.textContent = '-';
    speedupDetail.textContent = 'Run CPU compute first, then run FPGA benchmark to compare acceleration.';
    return;
  }

  if (Number.isFinite(cpuDim) && Number.isFinite(fpgaDim) && cpuDim !== fpgaDim) {
    speedupKernel.textContent = '-';
    speedupTotal.textContent = '-';
    speedupDetail.textContent = `CPU run used N=${cpuDim}, but FPGA benchmark used N=${fpgaDim}. Re-run with matching N for a valid speedup comparison.`;
    return;
  }

  const kernelSpeedup = Number.isFinite(fk) && fk > 0 ? (cpu / fk) : NaN;
  const totalSpeedup = Number.isFinite(ft) && ft > 0 ? (cpu / ft) : NaN;
  speedupKernel.textContent = formatSpeedup(kernelSpeedup);
  speedupTotal.textContent = formatSpeedup(totalSpeedup);

  const lines = [];
  lines.push(`Workload: CPU N=${Number.isFinite(cpuDim) ? cpuDim : 'unknown'} | FPGA N=${Number.isFinite(fpgaDim) ? fpgaDim : 'unknown'}${Number.isFinite(perfState.lastIterations) ? `, iterations=${perfState.lastIterations}` : ''}`);
  lines.push(`CPU compute time: ${formatDuration(cpu)} (${Number.isFinite(perfState.cpuGflops) ? `${perfState.cpuGflops.toFixed(4)} GFLOP/s` : 'GFLOP/s unavailable'})`);

  if (Number.isFinite(fk) && fk > 0) {
    const reduction = ((cpu - fk) / cpu) * 100;
    const deltaText = reduction >= 0
      ? `${reduction.toFixed(1)}% lower latency than CPU`
      : `${Math.abs(reduction).toFixed(1)}% higher latency than CPU`;
    lines.push(`FPGA kernel time: ${formatDuration(fk)} -> kernel speedup ${formatSpeedup(kernelSpeedup)} (${deltaText})`);
  } else {
    lines.push('FPGA kernel time: unavailable. Run FPGA benchmark in the FPGA Runtime tab.');
  }

  if (Number.isFinite(ft) && ft > 0) {
    const reduction = ((cpu - ft) / cpu) * 100;
    const deltaText = reduction >= 0
      ? `${reduction.toFixed(1)}% lower latency than CPU`
      : `${Math.abs(reduction).toFixed(1)}% higher latency than CPU`;
    lines.push(`FPGA end-to-end time: ${formatDuration(ft)} -> end-to-end speedup ${formatSpeedup(totalSpeedup)} (${deltaText})`);
  } else {
    lines.push('FPGA end-to-end time: unavailable. Run FPGA benchmark in the FPGA Runtime tab.');
  }

  if (Number.isFinite(perfState.fpgaGbps)) {
    lines.push(`FPGA throughput: ${perfState.fpgaGbps.toFixed(3)} GB/s`);
  }

  speedupDetail.textContent = lines.join('\n');
}

function openModalForMatrix(key, preserveWorking = false) {
  modalState.key = key;
  if (!preserveWorking) {
    modalState.working = cloneMatrix(key === 'A' ? matrixA : matrixB);
  }
  const rows = matrixRows(modalState.working);
  const cols = matrixCols(modalState.working);

  modalTitle.textContent = key === 'A' ? 'Matrix A Editor' : 'Matrix B Editor';
  modalMeta.textContent = `${rows}x${cols} matrix editor. Scroll horizontally/vertically for full access.`;
  modalWrap.innerHTML = '';

  if (Math.max(rows, cols) <= MODAL_FULL_EDIT_MAX) {
    const table = matrixToTable(modalState.working, {
      editable: true,
      readOnly: false,
      idPrefix: `modal_${key.toLowerCase()}`,
      onCellChange: (r, c, v) => {
        modalState.working[r][c] = v;
      },
    });
    modalWrap.appendChild(table);
  } else {
    const preview = matrixToTable(modalState.working, {
      editable: false,
      readOnly: true,
      limitDim: PREVIEW_DIM,
      idPrefix: `modal_${key.toLowerCase()}_preview`,
    });
    modalWrap.appendChild(preview);

    const note = document.createElement('div');
    note.className = 'matrix-preview-note';
    note.textContent = `${rows}x${cols} is above the full-manual-edit limit (${MODAL_FULL_EDIT_MAX}). Use Generate Random / Initialize Empty here, or lower workspace dimensions for per-cell editing.`;
    modalWrap.appendChild(note);
  }

  modal.classList.remove('hidden');
  modal.setAttribute('aria-hidden', 'false');
}

function closeModal() {
  modal.classList.add('hidden');
  modal.setAttribute('aria-hidden', 'true');
}

function refreshUploadModalLabels() {
  if (uploadModalAName) {
    uploadModalAName.textContent = uploadModalState.fileA ? uploadModalState.fileA.name : 'No file selected';
  }
  if (uploadModalBName) {
    uploadModalBName.textContent = uploadModalState.fileB ? uploadModalState.fileB.name : 'No file selected';
  }
}

function openUploadModal() {
  uploadModalState.fileA = null;
  uploadModalState.fileB = null;
  if (uploadAFile) uploadAFile.value = '';
  if (uploadBFile) uploadBFile.value = '';
  refreshUploadModalLabels();
  uploadModal.classList.remove('hidden');
  uploadModal.setAttribute('aria-hidden', 'false');
}

function closeUploadModal() {
  uploadModal.classList.add('hidden');
  uploadModal.setAttribute('aria-hidden', 'true');
}

async function applyUploadModalFiles() {
  if (!uploadModalState.fileA || !uploadModalState.fileB) {
    throw new Error('Select both Matrix A and Matrix B files before loading.');
  }

  clearActiveGeneratedSource();
  const [textA, textB] = await Promise.all([
    readTextFile(uploadModalState.fileA),
    readTextFile(uploadModalState.fileB),
  ]);

  const parsedA = parseMatrixText(textA);
  const parsedB = parseMatrixText(textB);
  const aRows = matrixRows(parsedA);
  const aCols = matrixCols(parsedA);
  const bRows = matrixRows(parsedB);
  const bCols = matrixCols(parsedB);

  if (aCols !== bRows) {
    throw new Error(`Matrix dimension mismatch: A is ${aRows}x${aCols}, B is ${bRows}x${bCols}. Need A.cols == B.rows.`);
  }

  setMatrixShapes(aRows, aCols, bCols, true);
  matrixA = parsedA;
  matrixB = parsedB;
  matrixC = makeZeroMatrixRect(aRows, bCols);
  renderAllMatrices();
  resetTimingCards();
  closeUploadModal();
  appendOutput(`Loaded Matrix A/B from files (A=${aRows}x${aCols}, B=${bRows}x${bCols}).`);
}

function applyModalChanges() {
  clearActiveGeneratedSource();
  if (modalState.key === 'A') {
    matrixA = cloneMatrix(modalState.working);
  } else {
    matrixB = cloneMatrix(modalState.working);
  }
  renderAllMatrices();
  closeModal();
  appendOutput(`Applied changes to Matrix ${modalState.key}`);
}

function modalRandomize() {
  const seedOffset = modalState.key === 'A' ? 17 : 31;
  fillRandomMatrixInPlace(modalState.working, seedOffset);
  openModalForMatrix(modalState.key, true);
  appendOutput(`Randomized Matrix ${modalState.key} in popup editor.`);
}

function modalZero() {
  const rows = matrixRows(modalState.working);
  const cols = matrixCols(modalState.working);
  modalState.working = makeZeroMatrixRect(rows, cols);
  openModalForMatrix(modalState.key, true);
  appendOutput(`Initialized Matrix ${modalState.key} to zeros in popup editor.`);
}

async function apiCall(path, method = 'GET', body = null) {
  const opts = { method, headers: {} };
  if (body !== null) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const res = await fetch(path, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.detail || `${res.status} ${res.statusText}`);
  }
  return data;
}

async function doCompute(includeTrace = false) {
  const payload = {
    matrix_a: matrixA,
    matrix_b: matrixB,
  };
  if (includeTrace) {
    payload.trace_row = Number(traceRow.value || 0);
    payload.trace_col = Number(traceCol.value || 0);
  }

  const response = await apiCall('/api/matmul/compute', 'POST', payload);
  matrixC = cloneMatrix(response.result);
  renderResultMatrix();

  cpuMs.textContent = formatDuration(response.elapsed_ms);
  cpuGflops.textContent = `${response.gflops.toFixed(4)}`;
  perfState.cpuMs = response.elapsed_ms;
  perfState.cpuGflops = response.gflops;
  perfState.cpuDim = Number.isFinite(response?.shape_a?.[0]) ? response.shape_a[0] : currentDim;
  perfState.lastDim = Number.isFinite(response?.shape_a?.[0]) ? response.shape_a[0] : currentDim;
  perfState.lastIterations = 1;
  updateSpeedupAnalysis();
  appendOutput(`CPU matmul ${response.shape_a.join('x')} x ${response.shape_b.join('x')} in ${formatDuration(response.elapsed_ms)}`);

  if (response.trace) {
    const lines = response.trace.terms.map((t) => `k=${t.k}: ${t.a} * ${t.b} = ${t.product} -> partial=${t.partial_sum}`);
    lines.push(`sum = ${response.trace.sum}`);
    traceOutput.textContent = lines.join('\n');
  }
}

function setComputeStatus(state, text, mode = 'neutral') {
  if (!computeRunStatus) return;
  computeRunStatus.classList.remove('idle', 'running', 'done', 'error', 'mode-cpu', 'mode-fpga', 'mode-script');
  computeRunStatus.classList.add(state);
  if (mode === 'cpu') computeRunStatus.classList.add('mode-cpu');
  if (mode === 'fpga') computeRunStatus.classList.add('mode-fpga');
  if (mode === 'script') computeRunStatus.classList.add('mode-script');
  computeRunStatus.textContent = text;
}

function clearComputeStatusTimer() {
  if (computeStatusTimer) {
    clearTimeout(computeStatusTimer);
    computeStatusTimer = 0;
  }
}

function setComputeRunningState(running, opts = {}) {
  const mode = opts.mode || 'cpu';
  const includeTrace = Boolean(opts.includeTrace);
  computeRunning = running;
  if (computeBtn) {
    computeBtn.disabled = running;
    computeBtn.textContent = running && (mode === 'cpu' || mode === 'both')
      ? (includeTrace ? 'Tracing...' : (mode === 'both' ? 'CPU Step...' : 'CPU Computing...'))
      : 'CPU Compute';
  }
  if (fpgaComputeBtn) {
    fpgaComputeBtn.disabled = running;
    fpgaComputeBtn.textContent = running && mode === 'fpga'
      ? 'FPGA Running...'
      : (running && mode === 'both' ? 'FPGA Queued...' : 'FPGA Compute');
  }
  if (computeBothBtn) {
    computeBothBtn.disabled = running;
    computeBothBtn.textContent = running && mode === 'both' ? 'Running Both...' : 'Compute Both';
  }
  if (scriptRandomMatricesBtn) {
    scriptRandomMatricesBtn.disabled = running;
    scriptRandomMatricesBtn.textContent = running && mode === 'script'
      ? 'Generating...'
      : 'Generate via Python Script';
  }
  if (uploadMatricesBtn) {
    uploadMatricesBtn.disabled = running;
  }
  if (randomMatricesBtn) {
    randomMatricesBtn.disabled = running;
  }
  if (initMatricesBtn) {
    initMatricesBtn.disabled = running;
  }
  if (traceBtn) {
    traceBtn.disabled = running;
  }
  if (benchBtn) {
    benchBtn.disabled = running;
    benchBtn.textContent = running && (mode === 'fpga' || mode === 'both') ? 'Running FPGA...' : 'Run FPGA Timing';
  }
}

async function runComputeWithStatus(includeTrace = false) {
  if (computeRunning) return;
  clearComputeStatusTimer();
  setComputeRunningState(true, { mode: 'cpu', includeTrace });
  const cpuShape = shapeTupleString(currentM, currentK, currentN);
  setComputeStatus('running', includeTrace ? `Running CPU trace (${cpuShape})...` : `Running CPU compute (${cpuShape})...`, 'cpu');

  try {
    const aRows = matrixRows(matrixA);
    const aCols = matrixCols(matrixA);
    const bRows = matrixRows(matrixB);
    const bCols = matrixCols(matrixB);
    if (aCols !== bRows) {
      throw new Error(`Shape mismatch: A is ${aRows}x${aCols}, B is ${bRows}x${bCols}. Need A.cols == B.rows.`);
    }
    await doCompute(includeTrace);
    setComputeStatus('done', includeTrace ? 'CPU trace complete' : 'CPU compute complete', 'cpu');
    computeStatusTimer = window.setTimeout(() => {
      setComputeStatus('idle', 'Ready');
      computeStatusTimer = 0;
    }, 2200);
  } catch (err) {
    setComputeStatus('error', `CPU error: ${err.message}`, 'cpu');
    throw err;
  } finally {
    setComputeRunningState(false, { mode: 'cpu', includeTrace });
  }
}

async function runFpgaComputeWithStatus() {
  if (computeRunning) return;
  clearComputeStatusTimer();
  setComputeRunningState(true, { mode: 'fpga' });
  const benchDimRaw = (benchDimInput.value || '').trim();
  const runDim = benchDimRaw
    ? benchDimRaw
    : (activeGeneratedSource && activeGeneratedSource.mode === 'files' && Number.isInteger(activeGeneratedSource.dim)
      ? String(activeGeneratedSource.dim)
      : String(Math.max(currentM, currentK, currentN)));
  setComputeStatus('running', `Running FPGA compute (N=${runDim})...`, 'fpga');

  try {
    await doBenchmark();
    setComputeStatus('done', 'FPGA compute complete', 'fpga');
    computeStatusTimer = window.setTimeout(() => {
      setComputeStatus('idle', 'Ready');
      computeStatusTimer = 0;
    }, 2200);
  } catch (err) {
    setComputeStatus('error', `FPGA error: ${err.message}`, 'fpga');
    throw err;
  } finally {
    setComputeRunningState(false, { mode: 'fpga' });
  }
}

async function runBothComputeWithStatus() {
  if (computeRunning) return;
  clearComputeStatusTimer();
  setComputeRunningState(true, { mode: 'both' });
  const cpuShape = shapeTupleString(currentM, currentK, currentN);
  setComputeStatus('running', `Running CPU compute (${cpuShape})...`, 'cpu');

  try {
    const aRows = matrixRows(matrixA);
    const aCols = matrixCols(matrixA);
    const bRows = matrixRows(matrixB);
    const bCols = matrixCols(matrixB);
    if (aCols !== bRows) {
      throw new Error(`Shape mismatch: A is ${aRows}x${aCols}, B is ${bRows}x${bCols}. Need A.cols == B.rows.`);
    }

    await doCompute(false);
    setComputeStatus('running', 'CPU complete. Running FPGA compute...', 'fpga');
    await doBenchmark();

    setComputeStatus('done', 'CPU + FPGA compute complete', 'fpga');
    computeStatusTimer = window.setTimeout(() => {
      setComputeStatus('idle', 'Ready');
      computeStatusTimer = 0;
    }, 2200);
  } catch (err) {
    setComputeStatus('error', `Compute both error: ${err.message}`, 'fpga');
    throw err;
  } finally {
    setComputeRunningState(false, { mode: 'both' });
  }
}

async function runScriptGenerateWithStatus() {
  if (computeRunning) return;
  clearComputeStatusTimer();
  setComputeRunningState(true, { mode: 'script' });
  setComputeStatus('running', 'Generating matrices via Python script...', 'script');
  try {
    await doRandomizeBothViaScript();
    setComputeStatus('done', 'Script generation complete', 'script');
    computeStatusTimer = window.setTimeout(() => {
      setComputeStatus('idle', 'Ready');
      computeStatusTimer = 0;
    }, 2200);
  } catch (err) {
    setComputeStatus('error', `Script generation error: ${err.message}`, 'script');
    throw err;
  } finally {
    setComputeRunningState(false, { mode: 'script' });
  }
}

async function doRandomizeBoth() {
  clearActiveGeneratedSource();
  const { m, k, n } = getRequestedShapes();
  setMatrixShapes(m, k, n, true);
  fillRandomMatrixInPlace(matrixA, 13);
  fillRandomMatrixInPlace(matrixB, 29);
  matrixC = makeZeroMatrixRect(currentM, currentN);
  renderAllMatrices();
  appendOutput(`Generated random matrices (${shapeTupleString(currentM, currentK, currentN)}).`);
}

async function doRandomizeBothViaScript() {
  let scriptDim = clampDim(Math.max(currentM, currentK, currentN));
  if (scriptDimOverrideInput) {
    const raw = scriptDimOverrideInput.value.trim();
    if (raw) {
      const parsed = Number(raw);
      if (!Number.isInteger(parsed) || parsed < MIN_DIM || parsed > BENCHMARK_DIM_MAX) {
        throw new Error(`Script N Override must be an integer in [${MIN_DIM}, ${BENCHMARK_DIM_MAX}]`);
      }
      scriptDim = parsed;
    } else if (!(currentM === currentK && currentK === currentN)) {
      throw new Error('Python script generation is square-only. Set Script N Override to a square N.');
    }
  }

  const payload = {
    dim: scriptDim,
    min_value: Number(randMin.value),
    max_value: Number(randMax.value),
    seed: randSeed.value.trim() ? Number(randSeed.value) : null,
    file_format: 'csv',
  };
  const response = await apiCall('/api/matmul/random-script', 'POST', payload);
  if (response.mode === 'inline') {
    clearActiveGeneratedSource();
    setMatrixShapes(clampDim(scriptDim), clampDim(scriptDim), clampDim(scriptDim), true);
    matrixA = cloneMatrix(response.matrix_a);
    matrixB = cloneMatrix(response.matrix_b);
    matrixC = makeZeroMatrixRect(currentM, currentN);
    renderAllMatrices();
    appendOutput(`Generated random matrices via Python script (dim=${payload.dim})`);
    return;
  }

  if (response.mode === 'files') {
    activeGeneratedSource = {
      mode: 'files',
      dim: Number(response.dim),
      matrixAPath: response.matrix_a_path,
      matrixBPath: response.matrix_b_path,
      fileFormat: response.file_format || 'csv',
    };
    if (benchDimInput && !benchDimInput.value.trim()) {
      benchDimInput.value = String(response.dim);
    } else if (benchDimInput) {
      benchDimInput.value = String(response.dim);
    }
    appendOutput(`Generated large matrices via Python script (dim=${response.dim}).`);
    appendOutput(`Matrix A file: ${response.matrix_a_path}`);
    appendOutput(`Matrix B file: ${response.matrix_b_path}`);
    appendOutput(`Large matrices are stored on disk (not loaded into editor).`);
    appendOutput('Script-generated files are now selected as active compute input source.');
    renderAllMatrices();
    return;
  }

  throw new Error('Unexpected matrix script response from server.');
}

function normalizeUploadedMatrix(matrixAny) {
  if (!Array.isArray(matrixAny) || matrixAny.length === 0) {
    throw new Error('Uploaded matrix is empty or invalid.');
  }

  const matrix = matrixAny.map((row) => {
    if (!Array.isArray(row) || row.length === 0) {
      throw new Error('Uploaded matrix has an empty row.');
    }
    return row.map((cell) => {
      const v = Number(cell);
      if (!Number.isFinite(v)) {
        throw new Error(`Invalid numeric value: ${cell}`);
      }
      return v;
    });
  });

  const cols = matrix[0].length;
  for (let r = 1; r < matrix.length; r++) {
    if (matrix[r].length !== cols) {
      throw new Error('Uploaded matrix is not rectangular.');
    }
  }

  if (matrix.length > MAX_DIM || cols > MAX_DIM) {
    throw new Error(`Uploaded matrix shape ${matrix.length}x${cols} exceeds workspace max ${MAX_DIM} on at least one dimension.`);
  }

  return matrix;
}

function parseMatrixText(text) {
  const raw = String(text || '').trim();
  if (!raw) throw new Error('Uploaded file is empty.');

  if (raw.startsWith('[')) {
    let parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (err) {
      throw new Error('JSON matrix parse failed.');
    }
    return normalizeUploadedMatrix(parsed);
  }

  const rows = raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => line.split(/[,\t; ]+/).filter((x) => x.length > 0));

  return normalizeUploadedMatrix(rows);
}

async function readTextFile(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('Failed to read file.'));
    reader.onload = () => resolve(String(reader.result || ''));
    reader.readAsText(file);
  });
}

async function loadMatrixFromFile(file, target) {
  if (!file) return;
  clearActiveGeneratedSource();
  const text = await readTextFile(file);
  const parsed = parseMatrixText(text);
  const rows = matrixRows(parsed);
  const cols = matrixCols(parsed);

  const keepA = cloneMatrix(matrixA);
  const keepB = cloneMatrix(matrixB);

  let nextA = keepA;
  let nextB = keepB;
  if (target === 'A') {
    nextA = parsed;
  } else {
    nextB = parsed;
  }
  const aRows = matrixRows(nextA);
  const aCols = matrixCols(nextA);
  const bRows = matrixRows(nextB);
  const bCols = matrixCols(nextB);
  if (aCols !== bRows) {
    throw new Error(`Loaded Matrix ${target} is incompatible with the other matrix. A is ${aRows}x${aCols}, B is ${bRows}x${bCols}. Need A.cols == B.rows.`);
  }

  setMatrixShapes(aRows, aCols, bCols, true);
  matrixA = nextA;
  matrixB = nextB;
  matrixC = makeZeroMatrixRect(aRows, bCols);
  renderAllMatrices();
  resetTimingCards();
  appendOutput(`Loaded Matrix ${target} from file (${rows}x${cols}).`);
}

function doProgramFpga() {
  const payload = {
    device: fpgaDevice.value.trim() || '0',
    xclbin_path: xclbinPath.value.trim(),
  };
  appendOutput(`Programming FPGA on device ${payload.device}...`);
  return apiCall('/api/fpga/program', 'POST', payload).then((response) => {
    appendOutput(response.output || '(no output)');
    appendOutput(`Program command completed rc=${response.return_code} in ${formatDuration(response.elapsed_ms)}`);
  });
}

function doFpgaStatus() {
  const params = new URLSearchParams({ device: fpgaDevice.value.trim() || '0' });
  return apiCall(`/api/fpga/status?${params.toString()}`).then((response) => {
    appendOutput(`FPGA status: uuid=${response.xclbin_uuid || 'unknown'} CUs=${(response.compute_units || []).join(', ') || 'none'}`);
  });
}

function doBenchmark() {
  const benchDimRaw = (benchDimInput.value || '').trim();
  let runDim = Math.max(currentM, currentK, currentN);
  if (benchDimRaw) {
    const parsed = Number(benchDimRaw);
    if (!Number.isInteger(parsed) || parsed < MIN_DIM || parsed > BENCHMARK_DIM_MAX) {
      throw new Error(`Benchmark N Override must be an integer in [${MIN_DIM}, ${BENCHMARK_DIM_MAX}]`);
    }
    runDim = parsed;
  } else if (activeGeneratedSource && activeGeneratedSource.mode === 'files' && Number.isInteger(activeGeneratedSource.dim)) {
    runDim = activeGeneratedSource.dim;
  }

  const payload = {
    dim: runDim,
    mode: benchMode.value,
    iterations: Number(benchIterations.value || 1),
    device: fpgaDevice.value.trim() || '0',
    xclbin_path: xclbinPath.value.trim(),
  };

  if (
    activeGeneratedSource
    && activeGeneratedSource.mode === 'files'
    && Number.isInteger(activeGeneratedSource.dim)
    && activeGeneratedSource.dim === runDim
  ) {
    payload.matrix_a_path = activeGeneratedSource.matrixAPath;
    payload.matrix_b_path = activeGeneratedSource.matrixBPath;
  } else if (Array.isArray(matrixA) && Array.isArray(matrixB)) {
    payload.matrix_a = matrixA;
    payload.matrix_b = matrixB;
  }

  if (!(currentM === currentK && currentK === currentN) && (!activeGeneratedSource || activeGeneratedSource.mode !== 'files')) {
    appendOutput(`FPGA rectangular mode: zero-padding A(${currentM}x${currentK}) and B(${currentK}x${currentN}) to ${runDim}x${runDim}.`);
  }
  appendOutput(`Running ${payload.mode} benchmark for ${runDim}x${runDim} ...`);
  return apiCall('/api/benchmark', 'POST', payload).then((response) => {
    if (response.matrix_source && response.matrix_source.mode === 'generated-files') {
      appendOutput(`Active script-generated input source selected:`);
      appendOutput(`  A: ${response.matrix_source.matrix_a_path}`);
      appendOutput(`  B: ${response.matrix_source.matrix_b_path}`);
    } else if (response.matrix_source && response.matrix_source.mode === 'inline-zero-pad') {
      appendOutput(`Inline matrix source selected (auto zero-pad):`);
      appendOutput(`  A: ${response.matrix_source.shape_a.join('x')}  B: ${response.matrix_source.shape_b.join('x')}`);
      appendOutput(`  required N >= ${response.matrix_source.required_dim}; running N=${response.matrix_source.run_dim}`);
    }
    appendOutput(response.output_tail || '(no output)');
    if (response.summary && response.summary.metrics) {
      const m = response.summary.metrics;
      if (Number.isFinite(m.avg_kernel_ms)) {
        fpgaKernelMs.textContent = formatDuration(m.avg_kernel_ms);
        perfState.fpgaKernelMs = m.avg_kernel_ms;
      }
      if (Number.isFinite(m.avg_total_ms)) {
        fpgaTotalMs.textContent = formatDuration(m.avg_total_ms);
        perfState.fpgaTotalMs = m.avg_total_ms;
      }
      if (Number.isFinite(m.avg_throughput_gbps)) {
        fpgaGbps.textContent = `${m.avg_throughput_gbps.toFixed(3)} GB/s`;
        perfState.fpgaGbps = m.avg_throughput_gbps;
      }
      perfState.fpgaDim = runDim;
      perfState.lastDim = runDim;
      perfState.lastIterations = payload.iterations;
      updateSpeedupAnalysis();
    }
    appendOutput(`Benchmark done rc=${response.return_code} elapsed=${formatDuration(response.elapsed_ms)}`);
  });
}

function escapeHtml(text) {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function slugifyHeading(text) {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

function extractMarkdownHeadings(md) {
  const headings = [];
  const seen = new Map();
  const re = /^(#{1,6})\s+(.*)$/gm;
  let match;

  while ((match = re.exec(md)) !== null) {
    const level = match[1].length;
    const text = match[2].trim();
    if (!text) continue;
    const base = slugifyHeading(text) || `section-${headings.length + 1}`;
    const count = (seen.get(base) || 0) + 1;
    seen.set(base, count);
    const id = count === 1 ? base : `${base}-${count}`;
    headings.push({ level, text, id });
  }

  return headings;
}

function renderDocsToc(headings) {
  if (!docsToc) return;
  if (!headings.length) {
    docsToc.innerHTML = '<p class="hint">No section headings found in this document.</p>';
    return;
  }

  const links = headings
    .map((h) => `<a class="toc-link level-${h.level}" href="#${h.id}" data-doc-anchor="${h.id}">${escapeHtml(h.text)}</a>`)
    .join('');

  docsToc.innerHTML = `<nav class="docs-toc-list">${links}</nav>`;
}

function markdownToHtml(md, headings = []) {
  let html = escapeHtml(md);

  html = html.replace(/```([\s\S]*?)```/g, (_, code) => `<pre><code>${code.trim()}</code></pre>`);
  let headingIdx = 0;
  html = html.replace(/^(#{1,6})\s+(.*)$/gm, (_, hashes, text) => {
    const level = hashes.length;
    const heading = headings[headingIdx] || { id: `section-${headingIdx + 1}` };
    headingIdx += 1;
    return `<h${level} id="${heading.id}">${text}</h${level}>`;
  });
  html = html.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_, alt, src) => {
    const resolvedSrc = src.startsWith('assets/') ? `/README/assets/${src.slice('assets/'.length)}` : src;
    const cap = alt ? `<figcaption>${alt}</figcaption>` : '';
    return `<figure class=\"doc-image\"><img src=\"${resolvedSrc}\" alt=\"${alt}\" loading=\"lazy\"/>${cap}</figure>`;
  });
  html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href=\"$2\" target=\"_blank\" rel=\"noopener noreferrer\">$1</a>');
  html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
  html = html.replace(/`([^`]+)`/g, '<code>$1</code>');

  html = html.replace(/^\-\s+(.*)$/gm, '<li>$1</li>');
  html = html.replace(/(<li>.*<\/li>\n?)+/g, (block) => `<ul>${block}</ul>`);

  html = html
    .split(/\n{2,}/)
    .map((chunk) => {
      const t = chunk.trim();
      if (!t) return '';
      if (t.startsWith('<h') || t.startsWith('<pre>') || t.startsWith('<ul>')) return t;
      return `<p>${t.replaceAll('\n', '<br/>')}</p>`;
    })
    .join('\n');

  return html;
}

function loadDocsList({ preserveSelection = true, autoLoadSelected = false } = {}) {
  const previousKey = preserveSelection ? docsSelect.value : '';
  return apiCall('/api/docs/files').then((response) => {
    docsCache = response.items || [];
    docsSelect.innerHTML = '';
    docsCache.forEach((item) => {
      const opt = document.createElement('option');
      opt.value = item.key;
      opt.textContent = item.key;
      docsSelect.appendChild(opt);
    });

    let selectedKey = '';
    if (docsCache.length) {
      if (previousKey && docsCache.some((item) => item.key === previousKey)) {
        selectedKey = previousKey;
      } else {
        selectedKey = docsCache[0].key;
      }
      docsSelect.value = selectedKey;
    }

    if (!docsCache.length) {
      docsMeta.textContent = 'No markdown docs available.';
      docsRender.innerHTML = '<p>No documents found.</p>';
      renderDocsToc([]);
      return;
    }

    if (autoLoadSelected && selectedKey) {
      return loadSelectedDoc();
    }

    docsMeta.textContent = `${docsCache.length} markdown docs available.`;
  });
}

function loadSelectedDoc() {
  const key = docsSelect.value;
  if (!key) {
    docsRender.innerHTML = '<p>No document selected.</p>';
    renderDocsToc([]);
    return Promise.resolve();
  }
  return apiCall('/api/docs/read', 'POST', { key }).then((response) => {
    const text = response.text || '';
    const headings = extractMarkdownHeadings(text);
    docsMeta.textContent = `Loaded ${response.key} from ${response.path}`;
    docsRender.innerHTML = markdownToHtml(text, headings);
    docsRender.scrollTop = 0;
    renderDocsToc(headings);
  });
}

function currentDiagramViewId() {
  return diagramViewStack[diagramViewStack.length - 1];
}

function currentDiagramView() {
  if (!diagramModel) return null;
  return diagramModel.views[currentDiagramViewId()] || null;
}

function meshDisplayN() {
  return Math.max(1, Math.min(5, currentDim));
}

function buildDynamicPeMeshView(baseView) {
  const n = meshDisplayN();
  const view = {
    ...baseView,
    title: `PE Mesh Dataflow Explorer (N=${n} shown, capped at 5)`,
    description: `Orthogonal dataflow map from HBM -> tile/control -> ${n}x${n} PE mesh -> accumulator/drain.`,
    notes: [
      `Mesh display N is derived from Matrix Lab workspace N (${currentDim}), capped at 5 for readability.`,
      'HBM transfers tile payloads into local tile buffers.',
      'Controller injects timing/control and B-lane launch into top row.',
      'A values move left-to-right; B values move top-to-bottom through the mesh.',
      'Right edge of mesh drains into accumulation/output path.',
    ],
  };

  const nodes = [
    {
      id: 'hbm_src',
      label: 'HBM Fabric',
      subtitle: 'tile payload source',
      x: 40,
      y: 300,
      w: 240,
      h: 118,
      group: 'memory',
      details: 'HBM-backed matrix tiles are fetched here before compute.',
    },
    {
      id: 'tile_buf',
      label: 'Tile Buffers',
      subtitle: 'A/B staging',
      x: 330,
      y: 320,
      w: 270,
      h: 118,
      group: 'datapath',
      details: 'Staging buffers align A/B tile words for wavefront injection.',
    },
    {
      id: 'ctrl',
      label: 'Wavefront Controller',
      subtitle: 'schedule + launch',
      x: 330,
      y: 140,
      w: 270,
      h: 118,
      group: 'control',
      details: 'Issues launch timing and control metadata into the mesh.',
    },
    {
      id: 'accum',
      label: 'Accumulator',
      subtitle: 'partial sum fold',
      x: 1620,
      y: 330,
      w: 240,
      h: 118,
      group: 'compute',
      details: 'Collects row outputs from mesh edge and accumulates tile results.',
    },
    {
      id: 'drain',
      label: 'Drain / Store',
      subtitle: 'C tile writeback',
      x: 1620,
      y: 570,
      w: 240,
      h: 118,
      group: 'datapath',
      details: 'Sends completed C tiles toward memory writeback.',
    },
  ];

  const edges = [
    { from: 'hbm_src', to: 'tile_buf', label: 'tile bursts' },
    { from: 'hbm_src', to: 'ctrl', label: 'tile meta' },
    { from: 'ctrl', to: 'tile_buf', label: 'schedule cfg' },
    { from: 'accum', to: 'drain', label: 'C tile' },
  ];

  const meshStartX = 700;
  const meshStartY = 120;
  const pitchX = 150;
  const pitchY = 122;
  const peW = 104;
  const peH = 82;

  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      const peId = `pe_${r}_${c}`;
      nodes.push({
        id: peId,
        label: `PE[${r},${c}]`,
        subtitle: 'MAC',
        x: meshStartX + (c * pitchX),
        y: meshStartY + (r * pitchY),
        w: peW,
        h: peH,
        group: 'compute',
        details: `Processing element (${r},${c}): receives A/B wavefront values, performs local multiply-accumulate, and forwards data to neighbors.`,
        drill_to: 'pe_cell',
      });

      if (c < n - 1) {
        edges.push({ from: peId, to: `pe_${r}_${c + 1}`, label: 'A ->', show_label: false });
      }
      if (r < n - 1) {
        edges.push({ from: peId, to: `pe_${r + 1}_${c}`, label: 'B v', show_label: false });
      }
    }
  }

  for (let r = 0; r < n; r++) {
    edges.push({ from: 'tile_buf', to: `pe_${r}_0`, label: `A row ${r}`, always_label: true });
  }
  for (let c = 0; c < n; c++) {
    edges.push({ from: 'ctrl', to: `pe_0_${c}`, label: `B col ${c}`, always_label: true });
  }
  for (let r = 0; r < n; r++) {
    edges.push({ from: `pe_${r}_${n - 1}`, to: 'accum', label: `row ${r} out`, always_label: true });
  }

  view.nodes = nodes;
  view.edges = edges;
  return view;
}

function spreadViewLayout(baseView, spacingX = 1.2, spacingY = 1.2, marginX = 24, marginY = 24) {
  const nodes = (baseView.nodes || []).map((n) => ({
    ...n,
    x: Math.round((n.x * spacingX) + marginX),
    y: Math.round((n.y * spacingY) + marginY),
  }));

  return {
    ...baseView,
    nodes,
    edges: (baseView.edges || []).map((e) => ({ ...e })),
  };
}

function resolveDiagramView(view) {
  if (!view) return null;
  if (view.id === 'pe_mesh_grid') {
    return buildDynamicPeMeshView(view);
  }
  return spreadViewLayout(view, 1.35, 1.38, 34, 34);
}

function resetDiagramTransform() {
  diagramScale = 1.0;
  diagramTx = 0;
  diagramTy = 0;
  applyDiagramTransform();
}

function getDiagramViewportUnits() {
  const vb = diagramSvg.viewBox && diagramSvg.viewBox.baseVal;
  if (
    vb
    && Number.isFinite(vb.width) && Number.isFinite(vb.height)
    && vb.width > 0 && vb.height > 0
  ) {
    return { width: vb.width, height: vb.height };
  }

  const rect = diagramSvg.getBoundingClientRect();
  return {
    width: rect.width,
    height: rect.height,
  };
}

function clientToDiagramUnits(clientX, clientY) {
  if (!diagramSvg) return null;
  const ctm = diagramSvg.getScreenCTM();
  if (!ctm) return null;
  const pt = diagramSvg.createSVGPoint();
  pt.x = clientX;
  pt.y = clientY;
  const mapped = pt.matrixTransform(ctm.inverse());
  if (!Number.isFinite(mapped.x) || !Number.isFinite(mapped.y)) return null;
  return { x: mapped.x, y: mapped.y };
}

function getDiagramViewportCenterUnits() {
  const vb = diagramSvg.viewBox && diagramSvg.viewBox.baseVal;
  if (
    vb
    && Number.isFinite(vb.x) && Number.isFinite(vb.y)
    && Number.isFinite(vb.width) && Number.isFinite(vb.height)
    && vb.width > 0 && vb.height > 0
  ) {
    return {
      x: vb.x + (vb.width / 2),
      y: vb.y + (vb.height / 2),
    };
  }

  const rect = diagramSvg.getBoundingClientRect();
  return clientToDiagramUnits(
    rect.left + (rect.width / 2),
    rect.top + (rect.height / 2),
  );
}

function zoomDiagramAt(scaleFactor, anchor) {
  if (!diagramPanGroup) return;
  const prevScale = diagramScale;
  if (!Number.isFinite(prevScale) || prevScale <= 0) return;

  const clampedScale = Math.min(
    DIAGRAM_MAX_SCALE,
    Math.max(DIAGRAM_MIN_SCALE, prevScale * scaleFactor),
  );
  if (!Number.isFinite(clampedScale) || Math.abs(clampedScale - prevScale) < 1e-12) {
    return;
  }

  const fallbackAnchor = getDiagramViewportCenterUnits() || { x: 0, y: 0 };
  const ax = (anchor && Number.isFinite(anchor.x)) ? anchor.x : fallbackAnchor.x;
  const ay = (anchor && Number.isFinite(anchor.y)) ? anchor.y : fallbackAnchor.y;

  const worldX = (ax - diagramTx) / prevScale;
  const worldY = (ay - diagramTy) / prevScale;

  diagramScale = clampedScale;
  diagramTx = ax - (worldX * diagramScale);
  diagramTy = ay - (worldY * diagramScale);
  applyDiagramTransform();
}

function fitDiagramToViewport(padding = 26) {
  if (!diagramPanGroup) {
    resetDiagramTransform();
    return false;
  }

  const svgRect = diagramSvg.getBoundingClientRect();
  const viewport = getDiagramViewportUnits();
  const viewportW = viewport.width;
  const viewportH = viewport.height;
  if (!Number.isFinite(viewportW) || !Number.isFinite(viewportH) || viewportW < 40 || viewportH < 40) {
    return false;
  }

  let bbox = null;
  const prevTransform = diagramPanGroup.getAttribute('transform');
  try {
    // Measure in design space so prior pan/zoom state cannot bias fit.
    diagramPanGroup.removeAttribute('transform');
    bbox = diagramPanGroup.getBBox();
  } catch (err) {
    bbox = null;
  } finally {
    if (prevTransform) {
      diagramPanGroup.setAttribute('transform', prevTransform);
    }
  }

  if (!bbox || !Number.isFinite(bbox.width) || !Number.isFinite(bbox.height) || bbox.width <= 0 || bbox.height <= 0) {
    resetDiagramTransform();
    return false;
  }

  const availW = Math.max(20, viewportW - (padding * 2));
  const availH = Math.max(20, viewportH - (padding * 2));
  const sx = availW / bbox.width;
  const sy = availH / bbox.height;

  diagramScale = Math.min(DIAGRAM_FIT_MAX_SCALE, Math.max(DIAGRAM_MIN_SCALE, Math.min(sx, sy)));
  diagramTx = padding + ((availW - (bbox.width * diagramScale)) / 2) - (bbox.x * diagramScale);
  diagramTy = padding + ((availH - (bbox.height * diagramScale)) / 2) - (bbox.y * diagramScale);
  applyDiagramTransform();
  return true;
}

function isDiagramViewportReady() {
  if (!diagramModel || !panels.diagram.classList.contains('active')) return false;
  const rect = diagramSvg.getBoundingClientRect();
  return rect.width > 40 && rect.height > 40;
}

function scheduleDiagramFit(padding = 26, maxAttempts = 12) {
  if (diagramFitRaf) {
    cancelAnimationFrame(diagramFitRaf);
    diagramFitRaf = 0;
  }

  const attemptFit = (attempt) => {
    diagramFitRaf = 0;
    if (!diagramPanGroup) return;

    if (!isDiagramViewportReady()) {
      if (attempt >= maxAttempts) return;
      diagramFitRaf = requestAnimationFrame(() => attemptFit(attempt + 1));
      return;
    }

    if (!fitDiagramToViewport(padding) && attempt < maxAttempts) {
      diagramFitRaf = requestAnimationFrame(() => attemptFit(attempt + 1));
    }
  };

  diagramFitRaf = requestAnimationFrame(() => attemptFit(0));
}

function addWrappedSvgText(parent, {
  x,
  y,
  text,
  fontSize = 14,
  fontWeight = '400',
  fill = '#1f2937',
  maxWidth = 220,
  lineHeight = 1.25,
}) {
  const node = document.createElementNS('http://www.w3.org/2000/svg', 'text');
  node.setAttribute('x', String(x));
  node.setAttribute('y', String(y));
  node.setAttribute('font-size', String(fontSize));
  node.setAttribute('font-weight', String(fontWeight));
  node.setAttribute('fill', fill);

  const words = String(text || '').split(/\s+/).filter(Boolean);
  if (!words.length) {
    parent.appendChild(node);
    return y;
  }

  const approxChars = Math.max(8, Math.floor(maxWidth / (fontSize * 0.57)));
  const lines = [];
  let cur = words[0];
  for (let i = 1; i < words.length; i++) {
    const candidate = `${cur} ${words[i]}`;
    if (candidate.length <= approxChars) {
      cur = candidate;
    } else {
      lines.push(cur);
      cur = words[i];
    }
  }
  lines.push(cur);

  lines.forEach((line, idx) => {
    const tspan = document.createElementNS('http://www.w3.org/2000/svg', 'tspan');
    tspan.setAttribute('x', String(x));
    tspan.setAttribute('dy', idx === 0 ? '0' : `${fontSize * lineHeight}`);
    tspan.textContent = line;
    node.appendChild(tspan);
  });

  parent.appendChild(node);
  return y + ((lines.length - 1) * fontSize * lineHeight);
}

function applyDiagramTransform() {
  if (!diagramPanGroup) return;
  diagramPanGroup.setAttribute('transform', `translate(${diagramTx},${diagramTy}) scale(${diagramScale})`);
  diagramZoomReadout.textContent = `${Math.round(diagramScale * 100)}%`;
}

function updateDiagramBreadcrumb() {
  if (!diagramModel || !diagramViewStack.length) {
    diagramBreadcrumb.textContent = '';
    return;
  }
  const labels = diagramViewStack
    .map((id) => diagramModel.views[id])
    .filter(Boolean)
    .map((view) => view.title || view.id);
  diagramBreadcrumb.textContent = labels.join(' / ');
  diagramBackBtn.disabled = diagramViewStack.length <= 1;
}

function renderFlowNotes(view, selectedNode = null) {
  flowNotes.innerHTML = '';
  if (selectedNode && selectedNode.notes && selectedNode.notes.length) {
    selectedNode.notes.forEach((n) => {
      const li = document.createElement('li');
      li.textContent = n;
      flowNotes.appendChild(li);
    });
    return;
  }

  if (view.notes && view.notes.length) {
    view.notes.forEach((n) => {
      const li = document.createElement('li');
      li.textContent = n;
      flowNotes.appendChild(li);
    });
    return;
  }

  (view.edges || []).forEach((e) => {
    const li = document.createElement('li');
    li.textContent = `${e.from} -> ${e.to}${e.label ? ` (${e.label})` : ''}`;
    flowNotes.appendChild(li);
  });
}

function setNodeDetails(node) {
  const drillText = node.drill_to ? `<button id="drill-btn" class="btn primary" type="button">Drill Into ${escapeHtml(node.label)}</button>` : '';
  blockDetails.innerHTML = `
    <h3>${escapeHtml(node.label)}</h3>
    <p>${escapeHtml(node.details || '')}</p>
    ${node.subtitle ? `<p><strong>${escapeHtml(node.subtitle)}</strong></p>` : ''}
    ${drillText}
  `;
  if (node.drill_to) {
    const btn = document.getElementById('drill-btn');
    if (btn) {
      btn.addEventListener('click', () => {
        diagramViewStack.push(node.drill_to);
        drawCurrentDiagramView();
      });
    }
  }
}

function edgeAnchor(from, to) {
  const fx = from.x + (from.w / 2);
  const fy = from.y + (from.h / 2);
  const tx = to.x + (to.w / 2);
  const ty = to.y + (to.h / 2);
  const dx = tx - fx;
  const dy = ty - fy;

  if (Math.abs(dx) >= Math.abs(dy)) {
    if (dx >= 0) {
      return {
        orientation: 'horizontal',
        x1: from.x + from.w,
        y1: fy,
        x2: to.x,
        y2: ty,
      };
    }
    return {
      orientation: 'horizontal',
      x1: from.x,
      y1: fy,
      x2: to.x + to.w,
      y2: ty,
    };
  }

  if (dy >= 0) {
    return {
      orientation: 'vertical',
      x1: fx,
      y1: from.y + from.h,
      x2: tx,
      y2: to.y,
    };
  }
  return {
    orientation: 'vertical',
    x1: fx,
    y1: from.y,
    x2: tx,
    y2: to.y + to.h,
  };
}

function orthogonalPath(anchors) {
  const { orientation, x1, y1, x2, y2 } = anchors;
  if (orientation === 'horizontal') {
    const midX = Math.round((x1 + x2) / 2);
    const pathLen = Math.abs(midX - x1) + Math.abs(y2 - y1) + Math.abs(x2 - midX);
    return {
      d: `M ${x1} ${y1} L ${midX} ${y1} L ${midX} ${y2} L ${x2} ${y2}`,
      labelX: midX + 4,
      labelY: Math.round((y1 + y2) / 2) - 6,
      pathLen,
    };
  }

  const midY = Math.round((y1 + y2) / 2);
  const pathLen = Math.abs(midY - y1) + Math.abs(x2 - x1) + Math.abs(y2 - midY);
  return {
    d: `M ${x1} ${y1} L ${x1} ${midY} L ${x2} ${midY} L ${x2} ${y2}`,
    labelX: Math.round((x1 + x2) / 2) + 4,
    labelY: midY - 6,
    pathLen,
  };
}

function drawCurrentDiagramView() {
  const view = resolveDiagramView(currentDiagramView());
  if (!view) return;
  const dark = document.body.getAttribute('data-theme') === 'dark';
  const edgeColor = dark ? '#96a8b7' : '#54646d';
  const edgeLabelColor = dark ? '#cbd9e3' : '#36454f';
  const nodeFill = dark ? '#0f1922' : '#ffffff';
  const labelColor = dark ? '#f0f7fc' : '#1f2937';
  const subtitleColor = dark ? '#9db1bf' : '#475569';
  const groupColorFallback = dark ? '#8fb3c9' : '#334155';

  diagramSvg.innerHTML = '';

  const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
  defs.innerHTML = `
    <marker id="arrow" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="${edgeColor}"></polygon>
    </marker>
  `;
  diagramSvg.appendChild(defs);

  diagramPanGroup = document.createElementNS('http://www.w3.org/2000/svg', 'g');
  diagramSvg.appendChild(diagramPanGroup);

  const edgesGroup = document.createElementNS('http://www.w3.org/2000/svg', 'g');
  const nodesGroup = document.createElementNS('http://www.w3.org/2000/svg', 'g');
  diagramPanGroup.appendChild(edgesGroup);
  diagramPanGroup.appendChild(nodesGroup);

  const nodeById = {};
  (view.nodes || []).forEach((n) => { nodeById[n.id] = n; });

  (view.edges || []).forEach((e) => {
    const from = nodeById[e.from];
    const to = nodeById[e.to];
    if (!from || !to) return;

    const anchors = edgeAnchor(from, to);
    const route = orthogonalPath(anchors);

    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', route.d);
    path.setAttribute('stroke', edgeColor);
    path.setAttribute('stroke-width', '2.5');
    path.setAttribute('fill', 'none');
    path.setAttribute('marker-end', 'url(#arrow)');
    edgesGroup.appendChild(path);

    const showLabel = Boolean(e.label) && (e.always_label || (e.show_label !== false && route.pathLen >= 170));
    if (showLabel) {
      const label = document.createElementNS('http://www.w3.org/2000/svg', 'text');
      label.setAttribute('x', String(route.labelX));
      label.setAttribute('y', String(route.labelY));
      label.setAttribute('font-size', '13');
      label.setAttribute('fill', edgeLabelColor);
      label.setAttribute('text-anchor', 'start');
      label.textContent = e.label;
      edgesGroup.appendChild(label);
    }
  });

  (view.nodes || []).forEach((n) => {
    const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    g.classList.add('node');

    const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    rect.setAttribute('x', String(n.x));
    rect.setAttribute('y', String(n.y));
    rect.setAttribute('width', String(n.w));
    rect.setAttribute('height', String(n.h));
    rect.setAttribute('rx', '12');
    rect.setAttribute('fill', nodeFill);
    rect.setAttribute('stroke', groupColors[n.group] || groupColorFallback);
    rect.setAttribute('stroke-width', '3');
    g.appendChild(rect);

    const maxTextWidth = Math.max(80, n.w - 24);
    let lastTextY = addWrappedSvgText(g, {
      x: n.x + 12,
      y: n.y + 27,
      text: n.label,
      fontSize: 17,
      fontWeight: '700',
      fill: labelColor,
      maxWidth: maxTextWidth,
      lineHeight: 1.2,
    });

    if (n.subtitle) {
      lastTextY = addWrappedSvgText(g, {
        x: n.x + 12,
        y: lastTextY + 17,
        text: n.subtitle,
        fontSize: 12,
        fill: subtitleColor,
        maxWidth: maxTextWidth,
        lineHeight: 1.2,
      });
    }

    const showTag = n.w >= 130 && n.h >= 92;
    if (showTag) {
      const tag = document.createElementNS('http://www.w3.org/2000/svg', 'text');
      tag.setAttribute('x', String(n.x + 12));
      tag.setAttribute('y', String(n.y + n.h - 12));
      tag.setAttribute('font-size', '11');
      tag.setAttribute('fill', subtitleColor);
      tag.textContent = n.group + (n.drill_to ? ' • double-click to drill' : '');
      g.appendChild(tag);
    }

    g.addEventListener('click', (evt) => {
      evt.stopPropagation();
      setNodeDetails(n);
      renderFlowNotes(view, n);
    });

    g.addEventListener('dblclick', (evt) => {
      evt.stopPropagation();
      if (n.drill_to && diagramModel.views[n.drill_to]) {
        diagramViewStack.push(n.drill_to);
        drawCurrentDiagramView();
      }
    });

    nodesGroup.appendChild(g);
  });

  diagramSvg.onclick = () => {
    blockDetails.textContent = 'Click a block to see details.';
    renderFlowNotes(view, null);
  };

  updateDiagramBreadcrumb();
  renderFlowNotes(view, null);
  blockDetails.innerHTML = `<h3>${escapeHtml(view.title || 'Diagram')}</h3><p>${escapeHtml(view.description || '')}</p>`;
  scheduleDiagramFit();
}

function bindDiagramInteractions() {
  diagramSvg.addEventListener('wheel', (evt) => {
    evt.preventDefault();
    const anchor = clientToDiagramUnits(evt.clientX, evt.clientY) || getDiagramViewportCenterUnits();
    const delta = evt.deltaY < 0 ? 1.12 : 0.89;
    zoomDiagramAt(delta, anchor);
  }, { passive: false });

  diagramSvg.addEventListener('mousedown', (evt) => {
    diagramDragging = true;
    diagramLastX = evt.clientX;
    diagramLastY = evt.clientY;
  });

  window.addEventListener('mouseup', () => {
    diagramDragging = false;
  });

  window.addEventListener('mousemove', (evt) => {
    if (!diagramDragging) return;
    diagramTx += evt.clientX - diagramLastX;
    diagramTy += evt.clientY - diagramLastY;
    diagramLastX = evt.clientX;
    diagramLastY = evt.clientY;
    applyDiagramTransform();
  });

  diagramBackBtn.addEventListener('click', () => {
    if (diagramViewStack.length <= 1) return;
    diagramViewStack.pop();
    drawCurrentDiagramView();
  });

  diagramZoomInBtn.addEventListener('click', () => {
    zoomDiagramAt(1.15, getDiagramViewportCenterUnits());
  });

  diagramZoomOutBtn.addEventListener('click', () => {
    zoomDiagramAt(0.87, getDiagramViewportCenterUnits());
  });

  diagramResetBtn.addEventListener('click', () => {
    if (!fitDiagramToViewport()) {
      scheduleDiagramFit();
    }
  });

  window.addEventListener('resize', () => {
    if (!diagramModel) return;
    scheduleDiagramFit();
  });
}

function loadDiagram() {
  return apiCall('/api/block-diagram').then((data) => {
    diagramModel = data;
    diagramViewStack = [data.root_view || 'top'];
    drawCurrentDiagramView();
  });
}

function applyTheme(theme) {
  if (theme === 'dark') {
    document.body.setAttribute('data-theme', 'dark');
    themeToggle.textContent = 'Light Mode';
  } else {
    document.body.setAttribute('data-theme', 'light');
    themeToggle.textContent = 'Dark Mode';
  }
  localStorage.setItem('mmul_lab_theme', theme);
  if (diagramModel) {
    drawCurrentDiagramView();
  }
}

function initTheme() {
  const stored = localStorage.getItem('mmul_lab_theme');
  applyTheme(stored === 'dark' ? 'dark' : 'light');
  themeToggle.addEventListener('click', () => {
    const cur = document.body.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
    applyTheme(cur === 'dark' ? 'light' : 'dark');
  });
}

function initModalHandlers() {
  modalCloseBtn.addEventListener('click', closeModal);
  modalApplyBtn.addEventListener('click', applyModalChanges);
  modalRandomBtn.addEventListener('click', () => {
    try {
      modalRandomize();
    } catch (err) {
      appendOutput(`ERROR modal randomize: ${err.message}`);
    }
  });
  modalEmptyBtn.addEventListener('click', modalZero);

  modal.addEventListener('click', (evt) => {
    if (evt.target === modal) closeModal();
  });
}

function initUploadModalHandlers() {
  if (!uploadModal) return;

  if (uploadModalCloseBtn) {
    uploadModalCloseBtn.addEventListener('click', closeUploadModal);
  }

  if (uploadModalPickABtn) {
    uploadModalPickABtn.addEventListener('click', () => {
      if (!uploadAFile) return;
      uploadAFile.value = '';
      uploadAFile.click();
    });
  }

  if (uploadModalPickBBtn) {
    uploadModalPickBBtn.addEventListener('click', () => {
      if (!uploadBFile) return;
      uploadBFile.value = '';
      uploadBFile.click();
    });
  }

  if (uploadAFile) {
    uploadAFile.addEventListener('change', () => {
      uploadModalState.fileA = uploadAFile.files && uploadAFile.files[0] ? uploadAFile.files[0] : null;
      refreshUploadModalLabels();
    });
  }

  if (uploadBFile) {
    uploadBFile.addEventListener('change', () => {
      uploadModalState.fileB = uploadBFile.files && uploadBFile.files[0] ? uploadBFile.files[0] : null;
      refreshUploadModalLabels();
    });
  }

  if (uploadModalApplyBtn) {
    uploadModalApplyBtn.addEventListener('click', () => {
      applyUploadModalFiles().catch((err) => appendOutput(`ERROR upload matrices: ${err.message}`));
    });
  }

  uploadModal.addEventListener('click', (evt) => {
    if (evt.target === uploadModal) closeUploadModal();
  });
}

function bindUiActions() {
  const onShapeChange = () => {
    clearActiveGeneratedSource();
    const { m, k, n } = getRequestedShapes();
    setMatrixShapes(m, k, n, true);
    resetTimingCards();
    appendOutput(`Workspace shape set: ${shapeTupleString(currentM, currentK, currentN)}.`);
  };
  dimInput.addEventListener('change', onShapeChange);
  if (kInput) kInput.addEventListener('change', onShapeChange);
  if (nInput) nInput.addEventListener('change', onShapeChange);

  document.getElementById('init-matrices-btn').addEventListener('click', () => {
    clearActiveGeneratedSource();
    const { m, k, n } = getRequestedShapes();
    setMatrixShapes(m, k, n, true);
    resetTimingCards();
    traceOutput.textContent = '';
    appendOutput(`Initialized zero matrices (${shapeTupleString(currentM, currentK, currentN)}).`);
  });

  document.getElementById('random-matrices-btn').addEventListener('click', () => {
    clearActiveGeneratedSource();
    const { m, k, n } = getRequestedShapes();
    setMatrixShapes(m, k, n, true);
    doRandomizeBoth().catch((err) => appendOutput(`ERROR randomize: ${err.message}`));
  });

  if (scriptRandomMatricesBtn) {
    scriptRandomMatricesBtn.addEventListener('click', () => {
      runScriptGenerateWithStatus().catch((err) => appendOutput(`ERROR script randomize: ${err.message}`));
    });
  }

  document.getElementById('random-a-btn').addEventListener('click', () => {
    try {
      clearActiveGeneratedSource();
      fillRandomMatrixInPlace(matrixA, 13);
      renderAllMatrices();
      appendOutput('Randomized Matrix A');
    } catch (err) {
      appendOutput(`ERROR random A: ${err.message}`);
    }
  });

  document.getElementById('random-b-btn').addEventListener('click', () => {
    try {
      clearActiveGeneratedSource();
      fillRandomMatrixInPlace(matrixB, 29);
      renderAllMatrices();
      appendOutput('Randomized Matrix B');
    } catch (err) {
      appendOutput(`ERROR random B: ${err.message}`);
    }
  });

  document.getElementById('empty-a-btn').addEventListener('click', () => {
    clearActiveGeneratedSource();
    matrixA = makeZeroMatrixRect(currentM, currentK);
    matrixC = makeZeroMatrixRect(currentM, currentN);
    renderAllMatrices();
    appendOutput('Initialized Matrix A to zeros');
  });

  document.getElementById('empty-b-btn').addEventListener('click', () => {
    clearActiveGeneratedSource();
    matrixB = makeZeroMatrixRect(currentK, currentN);
    matrixC = makeZeroMatrixRect(currentM, currentN);
    renderAllMatrices();
    appendOutput('Initialized Matrix B to zeros');
  });

  document.getElementById('edit-a-btn').addEventListener('click', () => openModalForMatrix('A'));
  document.getElementById('edit-b-btn').addEventListener('click', () => openModalForMatrix('B'));
  if (uploadMatricesBtn) {
    uploadMatricesBtn.addEventListener('click', () => {
      if (computeRunning) return;
      openUploadModal();
    });
  }

  if (computeBtn) {
    computeBtn.addEventListener('click', () => {
      runComputeWithStatus(false).catch((err) => appendOutput(`ERROR compute: ${err.message}`));
    });
  }

  if (fpgaComputeBtn) {
    fpgaComputeBtn.addEventListener('click', () => {
      runFpgaComputeWithStatus().catch((err) => appendOutput(`ERROR fpga compute: ${err.message}`));
    });
  }

  if (computeBothBtn) {
    computeBothBtn.addEventListener('click', () => {
      runBothComputeWithStatus().catch((err) => appendOutput(`ERROR compute both: ${err.message}`));
    });
  }

  if (traceBtn) {
    traceBtn.addEventListener('click', () => {
      runComputeWithStatus(true).catch((err) => appendOutput(`ERROR trace: ${err.message}`));
    });
  }

  document.getElementById('program-btn').addEventListener('click', () => {
    doProgramFpga().catch((err) => appendOutput(`ERROR program: ${err.message}`));
  });

  document.getElementById('status-btn').addEventListener('click', () => {
    doFpgaStatus().catch((err) => appendOutput(`ERROR status: ${err.message}`));
  });

  if (benchBtn) {
    benchBtn.addEventListener('click', () => {
      runFpgaComputeWithStatus().catch((err) => appendOutput(`ERROR benchmark: ${err.message}`));
    });
  }

  docsSelect.addEventListener('change', () => {
    loadSelectedDoc().catch((err) => {
      docsMeta.textContent = `ERROR: ${err.message}`;
    });
  });

  if (docsToc) {
    docsToc.addEventListener('click', (event) => {
      const link = event.target.closest('a[data-doc-anchor]');
      if (!link) return;
      event.preventDefault();
      const anchor = link.getAttribute('data-doc-anchor');
      if (!anchor) return;
      const target = docsRender.querySelector(`[id="${anchor}"]`);
      if (!target) return;
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  }
}

function initHealth() {
  return apiCall('/api/health').then((health) => {
    renderStartupGate(health);
    xclbinPath.value = health.default_xclbin || '';
    if (Number.isFinite(health.workspace_dim_max)) {
      dimInput.max = String(health.workspace_dim_max);
      if (kInput) kInput.max = String(health.workspace_dim_max);
      if (nInput) nInput.max = String(health.workspace_dim_max);
    }
    if (Number.isFinite(health.benchmark_dim_max)) {
      benchDimInput.max = String(health.benchmark_dim_max);
      if (scriptDimOverrideInput) {
        scriptDimOverrideInput.max = String(health.benchmark_dim_max);
      }
    }
    if (health.startup_gate && health.startup_gate.status === 'warn' && health.startup_gate.message) {
      appendOutput(`Startup warning: ${health.startup_gate.message}`);
    }
    appendOutput(`Loaded app health. kernel=${health.default_kernel}`);
  });
}

(function init() {
  initTheme();
  bindUiActions();
  initModalHandlers();
  initUploadModalHandlers();
  bindDiagramInteractions();
  setComputeStatus('idle', 'Ready');

  const { m, k, n } = getRequestedShapes();
  setMatrixShapes(m, k, n, true);

  Promise.resolve()
    .then(initHealth)
    .then(() => loadDocsList({ preserveSelection: false, autoLoadSelected: true }))
    .then(loadDiagram)
    .then(doFpgaStatus)
    .catch((err) => {
      appendOutput(`Startup warning: ${err.message}`);
    });
})();
