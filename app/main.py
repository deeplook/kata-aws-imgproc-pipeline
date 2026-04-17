import os

import boto3
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import HTMLResponse

app = FastAPI(title="Semantic Photo Gallery")

S3_BUCKET = os.environ["S3_BUCKET"]
SEARCH_API_URL = os.environ["SEARCH_API_URL"].rstrip("/")
AWS_REGION = os.environ.get("AWS_REGION_NAME", "eu-central-1")

_s3 = None
_rekognition = None


def _get_rekognition():
    global _rekognition
    if _rekognition is None:
        _rekognition = boto3.client("rekognition", region_name=AWS_REGION)
    return _rekognition


def _get_s3():
    global _s3
    if _s3 is None:
        # TODO Stage 8: add Config(s3={"addressing_style": "virtual"}) here.
        # Without it, boto3 generates path-style presigned URLs which return 403
        # for S3 buckets created after 2019.
        _s3 = boto3.client("s3", region_name=AWS_REGION)
    return _s3


GALLERY_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Semantic Photo Gallery</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: system-ui, -apple-system, sans-serif; background: #f0f2f5; color: #1a1a2e; min-height: 100vh; }
    .header { background: #1a1a2e; color: #fff; padding: 1.25rem 2rem; display: flex; align-items: center; gap: .75rem; }
    .header h1 { font-size: 1.25rem; font-weight: 600; letter-spacing: -.01em; }
    .header .badge { font-size: .7rem; background: #4a90e2; padding: .2rem .5rem; border-radius: 99px; font-weight: 500; }
    .container { max-width: 1100px; margin: 2rem auto; padding: 0 1.5rem; display: grid; gap: 1.5rem; }
    .card { background: #fff; border-radius: 10px; padding: 1.5rem; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
    .card h2 { font-size: .8rem; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; color: #888; margin-bottom: 1rem; }
    .drop-zone { border: 2px dashed #d1d5db; border-radius: 8px; padding: 2rem 1rem; text-align: center; cursor: pointer; transition: all .2s; }
    .drop-zone.over { border-color: #4a90e2; background: #f0f6ff; }
    .drop-zone input[type=file] { display: none; }
    .drop-zone label { color: #4a90e2; font-weight: 600; cursor: pointer; font-size: .95rem; }
    .drop-zone p { margin-top: .4rem; font-size: .82rem; color: #aaa; }
    .drop-zone .filename { margin-top: .5rem; font-size: .85rem; color: #555; font-style: italic; }
    .btn { display: inline-flex; align-items: center; gap: .4rem; background: #4a90e2; color: #fff; border: none; padding: .55rem 1.25rem; border-radius: 6px; font-size: .9rem; font-weight: 500; cursor: pointer; transition: background .15s; }
    .btn:hover:not(:disabled) { background: #357abd; }
    .btn:disabled { background: #b0c4de; cursor: default; }
    .btn-row { margin-top: .9rem; }
    .status { margin-top: .7rem; font-size: .85rem; min-height: 1.2em; }
    .status.ok { color: #2e7d32; } .status.err { color: #c62828; }
    .search-row { display: flex; gap: .65rem; }
    .search-row input { flex: 1; padding: .55rem 1rem; border: 1.5px solid #d1d5db; border-radius: 6px; font-size: .9rem; outline: none; transition: border-color .15s; }
    .search-row input:focus { border-color: #4a90e2; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); gap: 1rem; }
    .result-card { background: #fff; border-radius: 10px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,.08); transition: transform .15s, box-shadow .15s; }
    .result-card:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,.12); }
    .result-card img { width: 100%; height: 155px; object-fit: cover; display: block; background: #f0f2f5; }
    .result-card .info { padding: .65rem .75rem; }
    .result-card .key { font-size: .72rem; color: #999; margin-bottom: .35rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .result-card .score { font-size: .72rem; font-weight: 600; color: #4a90e2; margin-bottom: .45rem; }
    .result-card .tags { display: flex; flex-wrap: wrap; gap: .3rem; }
    .result-card .tag { background: #e8f0fe; color: #1a73e8; font-size: .68rem; padding: .18rem .45rem; border-radius: 99px; font-weight: 500; }
    .empty { text-align: center; color: #aaa; padding: 3rem 1rem; grid-column: 1/-1; font-size: .9rem; }
    .result-card img { cursor: zoom-in; }
    .spinner { width: 14px; height: 14px; border: 2px solid currentColor; border-top-color: transparent; border-radius: 50%; animation: spin .55s linear infinite; display: inline-block; }
    @keyframes spin { to { transform: rotate(360deg); } }
    #lightbox { display: none; position: fixed; inset: 0; background: rgba(0,0,0,.88); z-index: 100; align-items: center; justify-content: center; cursor: zoom-out; }
    #lightbox.open { display: flex; }
    #lightbox img { max-width: 90vw; max-height: 90vh; object-fit: contain; border-radius: 6px; box-shadow: 0 12px 48px rgba(0,0,0,.5); cursor: default; }
    #lbClose { position: absolute; top: 1rem; right: 1.5rem; color: #fff; font-size: 2.2rem; line-height: 1; cursor: pointer; user-select: none; opacity: .8; transition: opacity .15s; }
    #lbClose:hover { opacity: 1; }
    .divider { text-align: center; color: #bbb; font-size: .75rem; margin: 1rem 0; position: relative; }
    .divider::before, .divider::after { content: ''; position: absolute; top: 50%; height: 1px; background: #e5e7eb; width: calc(50% - 5rem); }
    .divider::before { left: 0; } .divider::after { right: 0; }
  </style>
</head>
<body>
  <div class="header">
    <h1>Semantic Photo Gallery</h1>
    <span class="badge">AWS App Runner</span>
    <span class="badge" id="imgCount" style="background:#555;margin-left:auto;">…</span>
  </div>

  <div class="container">
    <div class="card">
      <h2>Upload Image</h2>
      <div class="drop-zone" id="dropZone">
        <input type="file" id="fileInput" accept="image/*" multiple>
        <label for="fileInput">Choose images</label>
        <p>or drag &amp; drop here (JPEG, PNG, WebP) — multiple files allowed</p>
        <div class="filename" id="fileName"></div>
      </div>
      <div class="btn-row">
        <button class="btn" id="uploadBtn" disabled>Upload</button>
      </div>
      <div class="status" id="uploadStatus"></div>
    </div>

    <div class="card">
      <h2>Search</h2>
      <div class="search-row">
        <input type="text" id="searchInput" placeholder="e.g. beach, dog, mountain, sunset…" autocomplete="off">
        <button class="btn" id="searchBtn">Search</button>
      </div>
      <div class="divider">or search by image</div>
      <div class="drop-zone" id="imgSearchZone">
        <input type="file" id="imgSearchInput" accept="image/*">
        <label for="imgSearchInput">Choose a query image</label>
        <p>or drag &amp; drop — finds visually similar photos in the gallery</p>
        <div class="filename" id="imgSearchName"></div>
      </div>
      <img id="imgSearchPreview" src="" alt="" style="display:none;max-height:180px;max-width:100%;border-radius:8px;margin-top:.75rem;object-fit:contain;">
      <div class="status" id="searchStatus"></div>
    </div>

    <div class="grid" id="results"></div>
  </div>

  <div id="lightbox">
    <span id="lbClose">&#x2715;</span>
    <img id="lbImg" src="" alt="">
  </div>

  <script>
    const lightbox = document.getElementById('lightbox');
    const lbImg    = document.getElementById('lbImg');
    document.getElementById('lbClose').addEventListener('click', closeLb);
    lightbox.addEventListener('click', e => { if (e.target === lightbox) closeLb(); });
    document.addEventListener('keydown', e => { if (e.key === 'Escape') closeLb(); });
    function openLb(url, alt) { lbImg.src = url; lbImg.alt = alt; lightbox.classList.add('open'); }
    function closeLb() { lightbox.classList.remove('open'); lbImg.src = ''; }

    const fileInput        = document.getElementById('fileInput');
    const dropZone         = document.getElementById('dropZone');
    const fileName         = document.getElementById('fileName');
    const uploadBtn        = document.getElementById('uploadBtn');
    const uploadStatus     = document.getElementById('uploadStatus');
    const searchInput      = document.getElementById('searchInput');
    const searchBtn        = document.getElementById('searchBtn');
    const searchStatus     = document.getElementById('searchStatus');
    const imgSearchInput   = document.getElementById('imgSearchInput');
    const imgSearchZone    = document.getElementById('imgSearchZone');
    const imgSearchName    = document.getElementById('imgSearchName');
    const imgSearchPreview = document.getElementById('imgSearchPreview');
    const resultsEl        = document.getElementById('results');

    fetch('/stats').then(r => r.json()).then(d => {
      document.getElementById('imgCount').textContent = d.count + ' image' + (d.count !== 1 ? 's' : '') + ' indexed';
    }).catch(() => { document.getElementById('imgCount').textContent = ''; });

    let selectedFiles = [];

    function pickFiles(fileList) {
      const images = Array.from(fileList).filter(f => f.type.startsWith('image/'));
      if (!images.length) return;
      selectedFiles = images;
      const totalKB = images.reduce((s, f) => s + f.size, 0) / 1024;
      fileName.textContent = images.length === 1
        ? images[0].name + ' (' + totalKB.toFixed(0) + ' KB)'
        : images.length + ' files (' + totalKB.toFixed(0) + ' KB total)';
      uploadBtn.disabled = false;
      uploadStatus.textContent = '';
      uploadStatus.className = 'status';
    }

    fileInput.addEventListener('change', () => pickFiles(fileInput.files));
    dropZone.addEventListener('dragover',  e => { e.preventDefault(); dropZone.classList.add('over'); });
    dropZone.addEventListener('dragleave', ()  => dropZone.classList.remove('over'));
    dropZone.addEventListener('drop', e => { e.preventDefault(); dropZone.classList.remove('over'); pickFiles(e.dataTransfer.files); });

    uploadBtn.addEventListener('click', async () => {
      if (!selectedFiles.length) return;
      uploadBtn.disabled = true;
      uploadBtn.innerHTML = '<span class="spinner"></span> Uploading…';
      uploadStatus.className = 'status';
      uploadStatus.textContent = '';
      const form = new FormData();
      for (const f of selectedFiles) form.append('files', f);
      try {
        const res = await fetch('/upload', { method: 'POST', body: form });
        const data = await res.json();
        if (res.ok) {
          const n = data.keys.length;
          uploadStatus.className = 'status ok';
          uploadStatus.textContent = '✓ Uploaded ' + n + ' file' + (n !== 1 ? 's' : '') + ' — pipeline is running (search in ~30s)';
          selectedFiles = []; fileInput.value = ''; fileName.textContent = ''; uploadBtn.disabled = true;
        } else {
          uploadStatus.className = 'status err';
          uploadStatus.textContent = '✗ ' + (data.message || 'Upload failed');
        }
      } catch { uploadStatus.className = 'status err'; uploadStatus.textContent = '✗ Network error'; }
      uploadBtn.innerHTML = 'Upload';
    });

    searchBtn.addEventListener('click', doSearch);
    searchInput.addEventListener('keydown', e => { if (e.key === 'Enter') doSearch(); });

    function renderResults(results) {
      if (!results.length) {
        resultsEl.innerHTML = '<p class="empty">No results — upload some images first, then wait ~30 s for the pipeline.</p>';
        return;
      }
      resultsEl.innerHTML = results.map(r => `
        <div class="result-card">
          <img src="${r.url}" alt="${r.key}" loading="lazy" data-url="${r.url}"
               onclick="openLb(this.dataset.url, this.alt)"
               onerror="this.style.height='80px';this.style.background='#eee'">
          <div class="info">
            <div class="key" title="${r.key}">${r.key}</div>
            <div class="score">score ${r.score.toFixed(4)}</div>
            <div class="tags">${(r.labels || []).slice(0, 6).map(l => `<span class="tag">${l}</span>`).join('')}</div>
          </div>
        </div>
      `).join('');
    }

    async function doSearch() {
      const q = searchInput.value.trim();
      if (!q) return;
      searchBtn.disabled = true;
      searchBtn.innerHTML = '<span class="spinner"></span> Searching…';
      searchStatus.className = 'status'; searchStatus.textContent = '';
      imgSearchPreview.style.display = 'none'; imgSearchName.textContent = ''; resultsEl.innerHTML = '';
      try {
        const res = await fetch('/search?q=' + encodeURIComponent(q));
        const data = await res.json();
        if (!res.ok) { searchStatus.className = 'status err'; searchStatus.textContent = '✗ ' + (data.message || 'Search failed'); return; }
        searchStatus.className = 'status ok';
        searchStatus.textContent = data.length + ' result' + (data.length !== 1 ? 's' : '') + ' for "' + q + '"';
        renderResults(data);
      } catch { searchStatus.className = 'status err'; searchStatus.textContent = '✗ Network error'; }
      searchBtn.disabled = false; searchBtn.textContent = 'Search';
    }

    imgSearchZone.addEventListener('dragover',  e => { e.preventDefault(); imgSearchZone.classList.add('over'); });
    imgSearchZone.addEventListener('dragleave', ()  => imgSearchZone.classList.remove('over'));
    imgSearchZone.addEventListener('drop', e => { e.preventDefault(); imgSearchZone.classList.remove('over'); const f = e.dataTransfer.files[0]; if (f && f.type.startsWith('image/')) doImageSearch(f); });
    imgSearchInput.addEventListener('change', () => { if (imgSearchInput.files[0]) doImageSearch(imgSearchInput.files[0]); });

    async function doImageSearch(file) {
      imgSearchName.textContent = file.name;
      imgSearchPreview.src = URL.createObjectURL(file);
      imgSearchPreview.style.display = 'block';
      searchStatus.className = 'status'; searchStatus.innerHTML = '<span class="spinner"></span> Analyzing…'; resultsEl.innerHTML = '';
      const form = new FormData(); form.append('file', file);
      try {
        const res = await fetch('/search-by-image', { method: 'POST', body: form });
        const data = await res.json();
        if (!res.ok) { searchStatus.className = 'status err'; searchStatus.textContent = '✗ ' + (data.message || 'Analysis failed'); return; }
        const n = data.results.length;
        searchStatus.className = 'status ok';
        searchStatus.textContent = 'Detected: ' + data.labels.join(', ') + ' — ' + n + ' result' + (n !== 1 ? 's' : '');
        renderResults(data.results);
      } catch { searchStatus.className = 'status err'; searchStatus.textContent = '✗ Network error'; }
    }
  </script>
</body>
</html>
"""


@app.get("/", response_class=HTMLResponse)
def index():
    return HTMLResponse(content=GALLERY_HTML)


@app.post("/upload")
async def upload(files: list[UploadFile] = File(...)):
    # TODO Stage 8: upload each file to S3_BUCKET using s3.put_object
    #   - call _get_s3().put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content, ContentType=...)
    #   - collect the filenames in a list
    # TODO Stage 8: return {"keys": [list of uploaded filenames]}
    pass


@app.get("/search")
async def search(q: str = ""):
    # TODO Stage 8: return 400 if q is empty
    # TODO Stage 8: proxy GET to SEARCH_API_URL/search?q=q using httpx
    # TODO Stage 8: deduplicate results by "key" (keep highest score per key)
    # TODO Stage 8: enrich each result with a presigned S3 GET URL (ExpiresIn=3600)
    # TODO Stage 8: return JSONResponse(results)
    pass


@app.post("/search-by-image")
async def search_by_image(file: UploadFile = File(...)):
    # TODO Stage 8: read file bytes
    # TODO Stage 8: call rekognition detect_labels with Image={"Bytes": content}
    #               (inline bytes — query image is never stored in S3)
    # TODO Stage 8: join label names, call SEARCH_API_URL/search
    # TODO Stage 8: deduplicate + add presigned URLs (same as /search)
    # TODO Stage 8: return JSONResponse({"labels": labels, "results": results})
    pass


@app.get("/stats")
async def stats():
    # TODO Stage 8: proxy GET to SEARCH_API_URL/count using httpx
    # TODO Stage 8: return JSONResponse(resp.json()) on success, {"count": 0} on failure
    pass
