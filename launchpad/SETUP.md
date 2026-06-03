# Staff Setup: AI Virtual Assistant on LaunchPad

This guide is for lab staff preparing a LaunchPad instance before participants arrive. The goal is to make participant handoff smooth by cloning the repo, preparing the notebook kernel, pre-pulling Docker images, and optionally warming the local NIM model cache.

Participants should start from **Resources > Code Server IDE**, not the LaunchPad **Jupyter Notebook** resource.

## 1. Open Code Server

Open the LaunchPad instance, then choose:

```text
Resources > Code Server IDE
```

Create a host terminal with:

```text
Terminal > New Terminal
```

Run all setup commands from this Code Server terminal.

## 2. Clone Or Refresh The Repo

For a fresh instance:

```bash
cd ~
git clone --branch nemotron3-milvus-cpu --single-branch \
  https://github.com/jspaulding-nv/ai-virtual-assistant.git
cd ~/ai-virtual-assistant
```

For an existing clone:

```bash
cd ~/ai-virtual-assistant
git fetch origin
git checkout nemotron3-milvus-cpu
git pull --ff-only
```

Confirm the expected branch and files:

```bash
git branch --show-current
test -f deploy/ai_virtual_assistant_notebook_launchpad.ipynb
test -f notebooks/ingest_data.ipynb
```

## 3. Copy The LaunchPad Notebook

Copy the LaunchPad deployment notebook next to the ingestion notebook so participants can move from one notebook to the next in the same folder:

```bash
cp deploy/ai_virtual_assistant_notebook_launchpad.ipynb \
  notebooks/ai_virtual_assistant_notebook_launchpad.ipynb
```

Confirm the participant-facing notebooks are side by side:

```bash
ls notebooks/*launchpad.ipynb notebooks/ingest_data.ipynb
```

## 4. Prepare The Notebook Kernel

Register the participant notebook kernel:

```bash
bash launchpad/setup-notebook-kernel.sh
```

This creates the `AIVA LaunchPad` kernel and configures it to use the LaunchPad unstructured retriever host port `18086`.

## 5. Create The LaunchPad Env File

Copy the template:

```bash
cp launchpad/.env.example .env.launchpad
chmod 600 .env.launchpad
mkdir -p ~/.cache/nim
```

Edit `.env.launchpad` and set:

```text
NGC_API_KEY=<ngc-personal-api-key>
```

Use an NGC personal API key with access to NIM containers and model assets. Do not paste the key into chat or screenshots.

## 6. Authenticate Docker

```bash
NGC_API_KEY="$(grep '^NGC_API_KEY=' .env.launchpad | cut -d= -f2-)"
printf '%s' "${NGC_API_KEY}" | docker login nvcr.io -u '$oauthtoken' --password-stdin
unset NGC_API_KEY
```

## 7. Pre-Pull Docker Images

Pull missing application, LaunchPad UI, NIM, Milvus, Postgres, Redis, MinIO, and supporting images:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim pull --policy missing
```

The LaunchPad UI image is already published to GHCR as:

```text
ghcr.io/jspaulding-nv/aiva-customer-service-ui:nemotron3-launchpad-proxy
```

The default `.env.launchpad` points Compose at that image with `LAUNCHPAD_UI_TAG=nemotron3-launchpad-proxy`, so staff do not need to build the UI image locally.

This is the minimum prep step that makes participant startup faster.

## 8. Optional: Warm The Full Stack

If time allows, start the stack once so local NIM containers can download model assets into `MODEL_DIRECTORY`:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim up -d --no-build
```

Watch status:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim ps
```

Useful logs:

```bash
docker logs -f nemollm-inference-microservice
docker logs -f nemo-retriever-embedding-microservice
docker logs -f nemo-retriever-ranking-microservice
docker logs -f milvus-standalone
```

Run quick readiness checks after containers report healthy:

```bash
curl -fsS http://127.0.0.1:8000/v1/health/ready
curl -fsS http://127.0.0.1:9080/v1/health/ready
curl -fsS http://127.0.0.1:1976/v1/health/ready
curl -fsS http://127.0.0.1:9091/healthz
curl -fsS http://127.0.0.1:18086/health
```

You may leave the stack running for participants, or stop it without deleting images, volumes, or model cache:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim down
```

## 9. Prepare Sample Manuals

Download the manuals ahead of time:

```bash
bash data/download.sh data/list_manuals.txt
```

Participants will still run `notebooks/ingest_data.ipynb` to load manuals, FAQs, products, and orders into the running services.

## 10. Participant Handoff

Tell participants to open:

```text
Resources > Code Server IDE
```

Then open this notebook:

```text
notebooks/ai_virtual_assistant_notebook_launchpad.ipynb
```

After deployment, they should open:

```text
notebooks/ingest_data.ipynb
```

Use the `AIVA LaunchPad` kernel when prompted.

The sample UI is available from the Code Server **Ports** tab next to the **Terminal** tab. Open port `3001`.

## Notes On Secrets

If the staff NGC key must not be shared with participants, do not leave the stack running with that key and do not leave the real key in `.env.launchpad`. You can still pre-pull images and warm the model cache, then stop the stack and replace `.env.launchpad` with the template before handoff:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim down

cp launchpad/.env.example .env.launchpad
chmod 600 .env.launchpad
docker logout nvcr.io
```

Participants can then enter their own NGC key in the copied `notebooks/ai_virtual_assistant_notebook_launchpad.ipynb`.
