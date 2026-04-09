# Phase 14 — Complete Setup Checklist
## What was missing and how to fix it

---

## Files to copy into your project

| File from this zip | Where it goes in your project |
|---|---|
| `dashboard.html` | `templates/dashboard.html` (replace existing) |
| `scraper_views_FULL.py` | `scraper/views.py` (replace existing) |
| `vikrant_urls_FULL.py` | `vikrant/urls.py` (replace existing) |
| `vikrant_asgi_FULL.py` | `vikrant/asgi.py` (replace existing) |
| `scraper_consumers_FULL.py` | `scraper/consumers.py` (replace existing) |
| `seed_scripts_command.py` | `scraper/management/commands/seed_scripts.py` (new file — see step 2 below) |
| `RUN.ps1` | Project root — same folder as `manage.py` |

---

## Step 1 — Create the management command folder

You must create these folders + an empty `__init__.py` file:

```
scraper/
  management/
    __init__.py          ← empty file, just create it
    commands/
      __init__.py        ← empty file, just create it
      seed_scripts.py    ← paste seed_scripts_command.py here
```

In PowerShell:
```powershell
mkdir scraper\management\commands
New-Item scraper\management\__init__.py -ItemType File
New-Item scraper\management\commands\__init__.py -ItemType File
```

---

## Step 2 — Edit seed_scripts.py to match YOUR actual filenames

Open `scraper/management/commands/seed_scripts.py`.
Find the `SCRIPTS` list near the top and change the filenames to match
whatever `.py` files you actually have in your `scripts/` folder.

Example — if your files are called `winfix_scraper.py` and `Compiler.py`:
```python
SCRIPTS = [
    ('Win Fix',   'winfix_scraper.py',  False, False, 1),
    ('Compiler',  'Compiler.py',         True,  False, 100),
    ('Modem',     'modem_reboot.py',     False, True,  200),
]
```

---

## Step 3 — Run migrations + seed

```powershell
python manage.py makemigrations scraper
python manage.py migrate
python manage.py createsuperuser    # skip if already done
python manage.py seed_scripts       # creates the ScraperScript rows
```

Verify at: http://localhost:8000/admin/scraper/scraperscript/

---

## Step 4 — Launch everything

```powershell
.\RUN.ps1
```

This opens 3 windows:
- Redis (inside WSL)
- Daphne on port 8000
- Celery worker (4 parallel slots)

---

## Step 5 — Test it

1. Open http://localhost:8000/
2. Click **Scraper** in the sidebar
3. The terminal should show:  `OK  Loaded N scripts`
4. The stage panels should appear (one per script from your DB)
5. Click **▶ Start Fetch**
6. Watch the progress bars and terminal fill with live logs

---

## What was actually wrong (root causes)

### Problem 1 — Missing `/api/scripts/` endpoint
The dashboard JS calls `GET /api/scripts/` inside `initAnalytics()` to build
the stage panels dynamically. This route was **not in urls.py** and the view
**did not exist** in views.py. Added in `scraper_views_FULL.py` and
`vikrant_urls_FULL.py`.

### Problem 2 — Missing `pipeline_id` in start response  
The JS does `data.pipeline_id` to display pipeline #N in the subtitle.
The old `start_pipeline` view never returned that field.
Fixed in `scraper_views_FULL.py`.

### Problem 3 — CSRF rejection on POST requests
Django rejects POST requests without a CSRF token (403 Forbidden).
The dashboard HTML was calling `fetch('/api/pipeline/start/', {method:'POST'})`
without the `X-CSRFToken` header.
Fixed by:
  - Adding `<meta name="csrf-token" content="{{ csrf_token }}">` to the HTML head
  - Adding `{% load static %}` at the top of the template
  - Adding a `getCsrf()` helper + `postJSON()` wrapper in the JS

### Problem 4 — Missing `pipeline.started` WebSocket handler in consumers.py
The `start_pipeline` view does a `channel_layer.group_send(type='pipeline.started')`
but the old consumer had no `pipeline_started()` method, so the message was silently
dropped. Added in `scraper_consumers_FULL.py`.

### Problem 5 — No `initial_state` sent on WebSocket connect
When you refresh the browser mid-run, the progress bars were blank because
the status consumer never sent current state on connect.
Added `_send_initial_state()` in `scraper_consumers_FULL.py`.

---

## If the stage grid still shows "Connecting to backend…"

That means `GET /api/scripts/` returned an error. Check:
1. Did you run `python manage.py seed_scripts`?
2. Go to http://localhost:8000/api/scripts/ in your browser — what do you see?
3. If you see a Django error page, read the traceback — it will tell you exactly what's wrong.

## If WebSocket shows "WS Off"
1. Make sure you're using **Daphne**, not `python manage.py runserver`
2. Daphne command: `daphne -b 0.0.0.0 -p 8000 vikrant.asgi:application`
3. Check `vikrant/asgi.py` — make sure it imports `scraper.routing`

## If Celery tasks never run
1. Is Redis running? Test: `wsl redis-cli ping` → should return `PONG`
2. Is the Celery worker running? Look for the worker window from RUN.ps1
3. Check `CELERY_BROKER_URL = 'redis://127.0.0.1:6379/0'` in settings.py
