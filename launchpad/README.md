# Participant Guide: AI Virtual Assistant on LaunchPad

Welcome. In this lab, you will deploy the NVIDIA AI Virtual Assistant blueprint on a LaunchPad instance with **2 H100 GPUs**. Lab staff should have already prepared the instance with the repository, notebook kernel, Docker images, and LaunchPad deployment notebook.

You will self-host:

- NVIDIA Nemotron 3 Nano 30B A3B NIM for response generation
- NVIDIA llama-nemotron-embed-1b-v2 NIM for embeddings
- NVIDIA llama-nemotron-rerank-1b-v2 NIM for reranking
- Milvus standalone with the GPU image and GPU vector indexes

Your instructor or lab staff will provide the temporary NGC key for the local NIM containers if the instance was not already configured with one. You do not need a hosted NVIDIA API Catalog key for inference in this LaunchPad path.

## NVIDIA LaunchPad Environment

NVIDIA LaunchPad provides a ready-to-use GPU development environment with common tools and IDE access already configured.

This participant guide assumes staff completed [SETUP.md](./SETUP.md), which prepares:

- The `~/ai-virtual-assistant` repository checkout
- The `AIVA LaunchPad` notebook kernel
- Pre-pulled Docker images, including the published LaunchPad UI image
- A copied deployment notebook at `notebooks/ai_virtual_assistant_notebook_launchpad.ipynb`
- Sample manuals, and optionally warmed local NIM model caches

Use the **Code Server IDE** for this lab. LaunchPad also exposes a **Jupyter Notebook** resource, but that resource is commonly backed by an automatically managed container such as `lp-jupyter-notebook:24.04`. Its terminal is not the host shell used by this Docker Compose lab.

## Local Model And GPU Layout

The Compose override in this folder uses a split-GPU layout:

- GPU `0`: Nemotron 3 Nano NIM
- GPU `1`: embedding NIM, reranking NIM, and GPU Milvus

Nemotron 3 Nano runs on GPU `0` and lets NIM select a compatible H100 profile from its model manifest. This keeps the full local stack on a 2x H100 LaunchPad instance while leaving the second GPU for retrieval services and Milvus.

## 1. Open The Code Server IDE

Staff will provide the LaunchPad URL for your lab environment. It will look like this:

```text
https://<uuid>.nvidialaunchpad.com/launch
```

1. Open the LaunchPad URL in your browser.
2. Sign in with your NVIDIA account.
3. Open the **Resources** menu and select **Code Server IDE**.
4. Open the `~/ai-virtual-assistant` folder if it is not already open.

The sample UI link for port `3001` will appear later in the VS Code **Ports** tab next to the **Terminal** tab.

## 2. Run The Deployment Notebook

Open this notebook:

```text
notebooks/ai_virtual_assistant_notebook_launchpad.ipynb
```

Run the cells from top to bottom. If VS Code asks you to choose a kernel, select **Select Another Kernel...** > **Jupyter Kernel...** > `AIVA LaunchPad`. If it does not appear, reload the browser tab and reopen the notebook.

The notebook will:

- Reuse the staff-prepared `.env.launchpad`, or prompt for the lab NGC key if needed
- Validate Docker, GPU, and LaunchPad Compose configuration
- Pull any missing images
- Start the local-NIM Docker Compose stack
- Download sample product manuals
- Point you to the VS Code **Ports** tab for port `3001`

The first startup can still take a while if the local NIM model cache was not fully warmed before handoff.

## 3. Ingest The Sample Data

After the deployment notebook starts the services, open:

```text
notebooks/ingest_data.ipynb
```

Use **Select Another Kernel...** > **Jupyter Kernel...** > `AIVA LaunchPad` when prompted, then run the cells from top to bottom.

The ingestion notebook loads:

- Product manuals and FAQ documents into GPU-backed Milvus collections
- Structured customer and order data into Postgres

## 4. Open The Sample UI

In the Code Server IDE, open the **Ports** tab next to the **Terminal** tab. Find port `3001` and open its forwarded URL. This opens the sample AI Virtual Assistant UI.

The LaunchPad UI image is patched to support the VS Code **Ports** tab URL, including paths like:

```text
https://<launchpad-host>/coder/proxy/3001/
```

If the page is blank and browser developer tools show `/_next/static/...` 404 errors, confirm that `agent-frontend` is using the `nemotron3-launchpad-proxy` image tag:

```bash
docker ps --filter name=agent-frontend --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

If you are using the LaunchPad browser desktop, you can also open:

```text
http://127.0.0.1:3001/
```

If port `3001` is not listed or is not healthy yet, wait another minute and refresh the **Ports** tab. The app waits on local NIM and database services during startup.

After ingestion finishes, try the suggested customer-service questions in the UI.

## Optional: Stop The Stack

Stop the containers without deleting model cache or data volumes:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim down
```

## Quick Troubleshooting

For staff setup and operator-level recovery, see [SETUP.md](./SETUP.md). The items below are the common participant-facing issues.

### Prepared Files Are Missing

This guide assumes staff completed [SETUP.md](./SETUP.md). If `~/ai-virtual-assistant`, `notebooks/ai_virtual_assistant_notebook_launchpad.ipynb`, or the `AIVA LaunchPad` kernel is missing, ask staff to rerun the setup handoff steps.

### Opened The Jupyter Notebook Resource By Mistake

Use **Resources > Code Server IDE** for this lab. The LaunchPad **Jupyter Notebook** resource is commonly backed by an automatically managed `lp-jupyter-notebook:24.04` container, so its terminal may show a root prompt such as `#` but still not be the host shell that owns Docker, GPUs, and VS Code port forwarding.

Open **Resources > Code Server IDE**, use the repo at `~/ai-virtual-assistant`, and use the VS Code **Ports** tab to open port `3001`.

### Deployment Notebook Prompts For An NGC Key

Use the temporary lab key provided by staff. It should be an NGC personal key with access to **NGC Catalog** and **NVIDIA Private Registry**. Do not use a hosted NVIDIA API Catalog key, and do not paste the key into chat or screenshots.

### Deployment Takes A Long Time

The first startup can still take a while if local NIM model assets were not fully warmed before handoff. Let the deployment notebook cell continue running. If it appears stuck for a long time, ask staff to check the NIM container logs.

### Port 3001 Is Missing Or Not Healthy

The app waits for the local NIM and database services during startup. Wait another minute, refresh the VS Code **Ports** tab, and rerun the deployment notebook status cell. If port `3001` still does not appear, ask staff to check Docker Compose status.

### UI Is Up But Answers Are Not Data-Backed

Run `notebooks/ingest_data.ipynb` and wait for ingestion to finish. The application UI can open before Milvus and Postgres contain the sample manuals, products, customers, and orders.

### UI Returns A Generic Fallback Message

If the assistant responds with a generic message such as `I wasn't able to process your input`, ask staff to check the agent logs. This usually points to a backend startup, local NIM readiness, or tool-calling configuration issue.

### Staff Checks

Staff can run these from a Code Server terminal:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim ps

docker logs agent-chain-server --tail=200
docker logs nemollm-inference-microservice --tail=200
nvidia-smi
```

If tool-calling errors mention `--enable-auto-tool-choice` or `--tool-call-parser`, confirm `.env.launchpad` still contains the default `NIM_PASSTHROUGH_ARGS` from `launchpad/.env.example` and recreate the Nemotron and agent containers.

## References

- [Nemotron 3 Nano NIM support matrix](https://docs.nvidia.com/nim/large-language-models/latest/support-matrix.html)
- [NIM LLM tool calling and MCP integration](https://docs.nvidia.com/nim/large-language-models/latest/advanced-use-cases/tool-calling-and-mcp.html)
- [NIM custom parsers and chat templates](https://docs.nvidia.com/nim/large-language-models/latest/advanced-use-cases/custom-parsers-and-templates.html)
- [NeMo Retriever Embedding NIM getting started](https://docs.nvidia.com/nim/nemo-retriever/text-embedding/1.13.0/getting-started.html)
- [NeMo Retriever Reranking NIM support matrix](https://docs.nvidia.com/nim/nemo-retriever/text-reranking/latest/support-matrix.html)
- [Milvus GPU index overview](https://milvus.io/docs/gpu-index-overview.md)
