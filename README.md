# MicroFlow AI — SME Finance Copilot

**2026 Shenzhen International FinTech Competition · International Track · Topic E: SME Finance Copilot**
Theme: *AI as a Financial Participant*

MicroFlow AI is an AI agent for small-business owners. It reads the documents an Egyptian SME already has (bank statements, e-invoices, even informal Arabic/English receipt notes), predicts when each customer will actually pay, forecasts cash 13 weeks ahead, explains an alternative credit score factor by factor, finds the cheapest financing that closes the cash gap, and drafts the application — then waits for the owner's approval before anything is sent.

| Capability required by Topic E | Where it lives |
|---|---|
| Financing-option matching | `backend/copilot.py` → `match_financing` (factoring vs discounting vs loan, ranked by cost per EGP 1,000) |
| Cash-flow management with alerts | `backend/copilot.py` → `forecast_cashflow`, `build_alerts` (base + stress scenarios) |
| Business financial analysis | `backend/ai_engine.py` → XGBoost invoice-delay model + explainable 7-factor scorecard |
| Agent that completes real tasks | `POST /api/agent/run`: observe → analyse → decide → act (draft application) → owner approval → sandbox provider decision |

---

## Quick start (local, ~3 minutes)

Requires Python 3.11+.

```bash
pip install -r requirements.txt
python scripts/generate_samples.py              # synthetic demo dataset
uvicorn backend.main:app --port 8000            # terminal 1: API  (docs at http://localhost:8000/docs)
streamlit run frontend/app.py --server.port 8501   # terminal 2: dashboard at http://localhost:8501
```

Or run `./run_local.sh` to do all of the above.

**Demo walkthrough (dashboard):**
1. Sign in as **SME owner – Al-Nour Bakery Supplies** (password `Demo@2026!`).
2. Tab 1: click **Load bundled demo dataset** (2 statements as CSV + PDF, invoices as XML, JSON and PDF).
3. Tab 2: **Generate credit dossier** — score, grade, factor contributions, policy checks.
4. Tab 3: cash-flow runway chart with base/stress scenarios and alerts.
5. Tab 4: **Run the copilot agent** → reasoning trace → financing draft → **Approve & submit** → sandbox provider response. Ask questions in English or Arabic.
6. Tab 5: audit log, **Verify hash chain integrity**, and the raw ciphertext the database stores.
7. Sign out and sign in as **Advisor**, **Bank auditor** or the **other tenant** to see role and tenant restrictions.

### Docker (Postgres + Redis + API + dashboard)

```bash
cp .env.example .env   # fill in MICROFLOW_MASTER_KEY, MICROFLOW_JWT_SECRET, POSTGRES_PASSWORD
docker compose up --build
```

Cloud Run: `gcloud run deploy microflow-api --source . --set-env-vars DATABASE_URL=...,MICROFLOW_MASTER_KEY=...` (store secrets in Secret Manager in production).

### Tests and execution evidence

```bash
python -m pytest -q                    # 22 tests: parsers, model, encryption, audit chain, RBAC, tenant isolation, full flow
python scripts/run_sandbox_demo.py     # regenerates evidence/ (sandbox operation logs)
```

---

## Architecture

```
 Statements (PDF/CSV/text)   E-invoices (XML/JSON/PDF)
              │                        │
              ▼                        ▼
   ┌──────────────────────────────────────────────┐
   │ Ingestion (parser.py)                        │  magic-byte type check, 5 MB cap,
   │  XXE-safe XML · PDF text · CSV · Arabic text │  DTD/entity rejection, field validation
   └──────────────────────────────────────────────┘
              │ AES-256-GCM envelope encryption per field (security.py)
              ▼
   ┌──────────────────────────────────────────────┐
   │ PostgreSQL / SQLite (database.py)            │  amounts, names, tax ids stored as ciphertext
   └──────────────────────────────────────────────┘
              │ decrypt in memory, scoped to one tenant
              ▼
   ┌──────────────────────────────────────────────┐
   │ AI engine (ai_engine.py)                     │
   │  XGBoost delay model → expected pay dates    │
   │  7-factor explainable credit scorecard       │
   │  policy checks (history, affordability, HITL)│
   └──────────────────────────────────────────────┘
              ▼
   ┌──────────────────────────────────────────────┐
   │ Copilot (copilot.py)                         │
   │  13-week forecast (base/stress) + alerts     │
   │  financing matcher (cost-ranked)             │
   │  agent plan · NL Q&A (EN/AR)                 │
   └──────────────────────────────────────────────┘
              ▼
   FastAPI (main.py): JWT auth · RBAC · tenant scoping · hash-chained audit log
              ▼
   Streamlit dashboard (frontend/app.py)  ·  sandbox NBFI provider (simulated)
```

[![Architecture diagram of kareem-diaa/microflow-ai](https://gitdiagram.com/kareem-diaa/microflow-ai/diagram.png)](https://gitdiagram.com/kareem-diaa/microflow-ai?utm_source=readme&utm_medium=picture)

![image alt](https://github.com/kareem-diaa/MicroFlow-AI/blob/a4bce4070a407d7dfcc9761ff318359dc2a54dba/diagram.png)

## Key results on the demo dataset

| Metric | Value |
|---|---|
| Delay model (XGBoost) test MAE | 6.46 days vs 7.70 for the buyer-average baseline (16% better) |
| Credit score | 57.9 / 100 (grade C) — flagged for advisor review (< 60) |
| Cash alert | Balance turns negative in week 1 (payroll lands before collections) |
| Funding gap to 7-day buffer | EGP ~392k |
| Agent recommendation | Factor 4 invoices with NileFactor: EGP 414,630 unlocked for EGP 17,332 (vs EGP 37,355 for a 6-month loan) |
| Security tests | 12 / 12 passed (`evidence/security_tests.json`) |

## Data and honesty notes

- **All data is synthetic.** Businesses, buyers and providers (NileFactor, Delta Receivables Finance, Cairo Micro Lending) are fictional; the provider is a deterministic sandbox and no real money moves.
- The delay model is trained on a simulation of B2B payment behaviour (`ai_engine.generate_training_data`). With real ledgers it retrains on the same feature columns.
- Policy parameters in `backend/config.py` (`POLICY`) are illustrative and editable. The simplified-tax-regime flag is an indicator, not tax advice.
- Demo users and password are seeded for judging only (`MICROFLOW_SEED_DEMO=0` disables them).

## API reference (main endpoints)

| Method | Path | Permission |
|---|---|---|
| POST | `/api/auth/login` | public |
| POST | `/api/upload-statement`, `/api/upload-invoice` | `data:upload` (owner) |
| POST | `/api/demo/load-samples` | `data:upload` |
| GET | `/api/invoices` | `data:read` |
| POST | `/api/score-credit` · GET `/api/credit-dossier` | `credit:score` · `credit:read` |
| POST | `/api/forecast-cashflow` | `forecast:run` |
| GET | `/api/financing/offers`, `/api/financing/applications` | `financing:read` |
| POST | `/api/agent/run`, `/api/agent/ask` | `agent:run`, `agent:ask` |
| POST | `/api/financing/applications/{id}/approve` · `/reject` | `financing:approve` (owner only) |
| GET | `/api/audit-logs` · `/api/audit-logs/verify` | own scope · `audit:verify` (auditor) |

Interactive docs: `http://localhost:8000/docs`.

## Repository layout

```
backend/   config, database, security, parser, ai_engine, copilot, cache, main (API)
frontend/  app.py (Streamlit dashboard)
scripts/   generate_samples.py, run_sandbox_demo.py
tests/     pytest suite
data/samples/   synthetic statements and invoices
evidence/  sandbox operation logs (deliverable 06)
docs/      technical documentation, security self-assessment
```

## Team

Kareem Diaa Helal · Ahmed Mohamed · Mostafa — ElSewedy University of Technology (SUTech), Cairo, Egypt.

## License

MIT for the team's code. Third-party libraries keep their own licenses (FastAPI MIT, XGBoost Apache-2.0, PyMuPDF AGPL-3.0, Streamlit Apache-2.0, cryptography Apache-2.0/BSD).
