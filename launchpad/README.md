# Participant Guide: AI Virtual Assistant on LaunchPad

Welcome. In this lab, you will deploy the NVIDIA AI Virtual Assistant blueprint on a LaunchPad instance with **2 H100 GPUs**. The stack runs the `nemotron3-milvus-cpu` branch of the application with Docker Compose, local NVIDIA NIM microservices, and GPU-accelerated Milvus.

You will self-host:

- NVIDIA Nemotron 3 Nano 30B A3B NIM for response generation
- NVIDIA llama-nemotron-embed-1b-v2 NIM for embeddings
- NVIDIA llama-nemotron-rerank-1b-v2 NIM for reranking
- Milvus standalone with the GPU image and GPU vector indexes

You need an NGC personal API key with access to NIM containers and model assets. You do not need a hosted NVIDIA API Catalog key for inference in this LaunchPad path.

## NVIDIA LaunchPad Environment

NVIDIA LaunchPad provides a ready-to-use GPU development environment with common tools and IDE access already configured.

This deployment expects:

- LaunchPad instance with 2 H100 GPUs
- Git
- Docker and Docker Compose v2
- NVIDIA Container Toolkit
- Code Server IDE access
- Enough local disk space for NIM model cache and Docker volumes

Use the **Code Server IDE** for this lab. LaunchPad may also provide browser desktop, WebSSH, or Jupyter Notebook access if you prefer those tools.

## Local Model And GPU Layout

The Compose override in this folder uses a split-GPU layout:

- GPU `0`: Nemotron 3 Nano NIM
- GPU `1`: embedding NIM, reranking NIM, and GPU Milvus

Nemotron 3 Nano runs on GPU `0` and lets NIM select a compatible H100 profile from its model manifest. This keeps the full local stack on a 2x H100 LaunchPad instance while leaving the second GPU for retrieval services and Milvus.

## 1. Open The VS Code Environment

Staff will provide the LaunchPad URL for your lab environment. It will look like this:

```text
https://<uuid>.nvidialaunchpad.com/launch
```

1. Open the LaunchPad URL in your browser.
2. Sign in with your NVIDIA account.
3. Open the **Resources** menu and select **Code Server IDE**.
4. In VS Code, create a new Bash terminal with **Terminal > New Terminal**.

## 2. Clone The Blueprint Repository

Clone the lab branch into your LaunchPad home directory:

```bash
cd ~
git clone --branch nemotron3-milvus-cpu --single-branch \
  https://github.com/jspaulding-nv/ai-virtual-assistant.git
cd ~/ai-virtual-assistant
```

Confirm that you are on the expected branch:

```bash
git branch --show-current
test -f deploy/compose/docker-compose.yaml
```

Expected branch:

```text
nemotron3-milvus-cpu
```

## 3. Check The Instance

Confirm that Docker Compose and the H100 GPUs are visible:

```bash
docker compose version
nvidia-smi
```

You should see two H100 GPUs.

Check whether any NIM containers are already running before starting this lab:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -i nim || true
nvidia-smi
```

If another NIM is already using GPU memory, stop it only if it belongs to your lab session. Otherwise, ask staff before continuing so this stack does not compete for the H100s.

## 4. Create The LaunchPad Environment File

Copy the template:

```bash
cp launchpad/.env.example .env.launchpad
mkdir -p ~/.cache/nim
code-server .env.launchpad
```

Open `.env.launchpad` and update the NGC key:

```text
NGC_API_KEY=<your-ngc-personal-api-key>
```

The LaunchPad `nvidia` user normally has UID `1000` and GID `1000`, so these defaults should stay unchanged:

```text
MODEL_DIRECTORY=/home/nvidia/.cache/nim
USERID=1000:1000
UID=1000
GID=1000
```

The rest of the defaults are already set for the 2x H100 LaunchPad layout.

## 5. Authenticate With NGC

Read the NGC key from the env file and authenticate Docker to `nvcr.io`:

```bash
NGC_API_KEY="$(grep '^NGC_API_KEY=' .env.launchpad | cut -d= -f2-)"
echo "${NGC_API_KEY}" | docker login nvcr.io -u '$oauthtoken' --password-stdin
unset NGC_API_KEY
```

If this fails, confirm that the key is an NGC personal API key and that your account has access to the NIM containers.

## 6. Start The Full Local Stack

This guide uses the existing GHCR application images tagged `nemotron3-milvus-cpu`. Those images are still valid for LaunchPad because they contain only the application services. Milvus itself, the local NIMs, the GPU allocation, and the GPU index type are selected by the Compose files and environment variables at runtime.

Pull the prebuilt application images and NIM images:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim pull
```

Start the stack:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim up -d --no-build
```

The first startup can take a while because the NIM containers download model assets into `MODEL_DIRECTORY`.

Watch progress:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim ps
```

For detailed logs:

```bash
docker logs -f nemollm-inference-microservice
docker logs -f nemo-retriever-embedding-microservice
docker logs -f nemo-retriever-ranking-microservice
docker logs -f milvus-standalone
```

## 7. Check Local Services

Run these checks after Compose shows the containers running:

```bash
curl -fsS http://127.0.0.1:8000/v1/health/ready
curl -s http://127.0.0.1:8000/v1/models | jq .
curl -fsS http://127.0.0.1:9080/v1/health/ready
curl -fsS http://127.0.0.1:1976/health
curl -fsS http://127.0.0.1:9091/healthz
```

The LLM model list should include:

```text
nvidia/nemotron-3-nano-30b-a3b
```

Check application containers:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## 8. Open The Sample UI

Return to the LaunchPad page and open the forwarded URL for port `3001`. This opens the sample AI Virtual Assistant UI.

If port `3001` is not healthy yet, wait another minute and refresh the LaunchPad port list. The app waits on local NIM and database services during startup.

## 9. Ingest The Sample Data

Before asking data-backed questions, ingest the sample data.

Open the notebook:

```text
notebooks/ingest_data.ipynb
```

Run the cells from top to bottom. The notebook loads:

- Product manuals and FAQ documents into GPU-backed Milvus collections
- Structured customer and order data into Postgres

After ingestion finishes, return to the UI on port `3001` and try the suggested customer-service questions.

## 10. Stop The Stack

Stop the containers without deleting model cache or data volumes:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim down
```

## Quick Troubleshooting

### NIM Containers Take A Long Time

The first run downloads model assets to `MODEL_DIRECTORY`. Watch the NIM logs and leave the terminal open until health checks pass.

### Nemotron 3 Nano Exits During Startup

If Compose reports `container nemollm-inference-microservice exited (0)`, inspect the LLM NIM logs before restarting:

```bash
docker logs nemollm-inference-microservice --tail=200
```

Also confirm the NGC key was updated and that the model cache is writable:

```bash
grep -E '^(NGC_API_KEY|MODEL_DIRECTORY|USERID|NEMOTRON3_NANO_NIM_TAG|LLM_MS_GPU_ID)=' .env.launchpad
ls -ld /home/nvidia/.cache/nim
df -h /home/nvidia/.cache/nim
nvidia-smi
```

Do not paste the full `NGC_API_KEY` into chat or screenshots. If the logs show an auth or entitlement error, replace `NGC_API_KEY` with an NGC personal API key that can access NIM containers and model assets. If the logs show another process using GPU memory, stop only workloads that belong to your lab session or ask staff for help.

After correcting the issue, restart the LLM NIM first:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim up -d nemollm-inference
```

When the LLM health check passes, rerun the full `up -d --no-build` command.

### NGC Login Fails

Use an NGC personal API key, not a hosted API Catalog key. The key must have access to NIM containers and model assets.

### The UI Is Up But Answers Are Not Data-Backed

Run `notebooks/ingest_data.ipynb` and wait for ingestion to finish. The application UI can open before Milvus and Postgres contain the sample data.

### Milvus Fails After Switching From CPU To GPU

CPU and GPU index choices are stored with the Milvus collections. If you previously used the CPU Compose path, reset the Milvus data and re-ingest.

This deletes local vector data:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim down

rm -rf deploy/compose/volumes/milvus \
  deploy/compose/volumes/minio \
  deploy/compose/volumes/etcd
```

Then start Compose again and rerun ingestion.

### GPU Out Of Memory

Confirm the split layout:

```bash
docker inspect nemollm-inference-microservice \
  --format '{{json .HostConfig.DeviceRequests}}' | jq .
docker inspect milvus-standalone \
  --format '{{json .HostConfig.DeviceRequests}}' | jq .
```

If another process is using GPU memory, stop it or ask staff to reset the instance.

### Build Locally Instead Of Using GHCR

The lab defaults to prebuilt GHCR app images for faster startup. Rebuild and push new images only if the application source, Dockerfiles, or Python/Node dependencies change, or if you want a clearer LaunchPad-specific GHCR tag.

To build app containers locally, omit `deploy/compose/docker-compose.ghcr.yaml` and remove `--no-build` from the `up` command.

## References

- [Nemotron 3 Nano NIM support matrix](https://docs.nvidia.com/nim/large-language-models/latest/support-matrix.html)
- [NeMo Retriever Embedding NIM getting started](https://docs.nvidia.com/nim/nemo-retriever/text-embedding/1.13.0/getting-started.html)
- [NeMo Retriever Reranking NIM support matrix](https://docs.nvidia.com/nim/nemo-retriever/text-reranking/latest/support-matrix.html)
- [Milvus GPU index overview](https://milvus.io/docs/gpu-index-overview.md)
