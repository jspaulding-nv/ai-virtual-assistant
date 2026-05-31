# Brev Launchable Lab Guide

This guide walks you through starting the no-GPU NVIDIA Brev Launchable for the AI Virtual Assistant lab. The Launchable uses NVIDIA-hosted NIMs, public GHCR app images, and CPU Milvus, so you do not need a GPU or an NGC Docker key.

You will need an NVIDIA API key for hosted NIM inference. You will enter it inside Jupyter after the VM starts.

## 1. Wait For The Launchable

After clicking **Deploy Launchable**, wait until the instance page shows:

- **Running** in the top status area
- **VM Mode** with a green **Built** tag
- **script** with a green **Completed** tag

The startup script prepares Docker, JupyterLab, and the repository. It does not start the Docker Compose app until you enter your NVIDIA API key in the notebook.

## 2. Open Jupyter

Use either path:

- Click the green **jupyter** button if Brev shows one.
- Or scroll to **Using Secure Links** and open the shareable URL for port `8889`. The port health should show **Healthy**.

Jupyter should open directly to:

```text
notebooks/deploy_hosted_nims.ipynb
```

If Jupyter opens to the launcher instead, open the file browser and select:

```text
ai-virtual-assistant/notebooks/deploy_hosted_nims.ipynb
```

## 3. Deploy The App From The Notebook

Run the cells in `deploy_hosted_nims.ipynb` from top to bottom.

The first cell asks for your `NVIDIA_API_KEY`. Paste your NVIDIA hosted NIM API key when prompted.

The notebook then:

- Writes `.env.launchable` locally on the VM
- Validates Docker Compose is using Nemotron 3 Nano and CPU Milvus
- Pulls the public GHCR app images
- Starts Docker Compose with `--no-build`
- Downloads the sample manuals for the ingestion notebook

The Docker cell may take several minutes on a fresh VM while images are pulled and containers start. Full Docker output is written to:

```text
logs/deploy_hosted_nims.log
```

To watch progress, open a Jupyter terminal and run:

```bash
tail -f ~/ai-virtual-assistant/logs/deploy_hosted_nims.log
```

## 4. Open The Sample UI

After the deploy notebook starts the services, return to the Brev instance page and scroll to **Using Secure Links**.

Open the shareable URL for port `3001` when its health shows **Healthy**. This opens the sample AI Virtual Assistant UI.

If port `3001` is not healthy yet, wait another minute and refresh the Brev page. The app containers may still be starting.

## 5. Ingest The Sample Data

Before asking data-backed questions in the UI, run:

```text
notebooks/ingest_data.ipynb
```

This loads:

- Product manuals and FAQs into Milvus
- Structured customer/order data into Postgres

After ingestion finishes, return to the UI on port `3001` and try the suggested customer-service questions.

## Troubleshooting

### Jupyter Opens To The Launcher

Open this notebook manually:

```text
ai-virtual-assistant/notebooks/deploy_hosted_nims.ipynb
```

### A Notebook Cell Shows `[*]` For A Long Time

The cell is still running. For Docker deploy progress, open a Jupyter terminal and run:

```bash
tail -f ~/ai-virtual-assistant/logs/deploy_hosted_nims.log
```

### The UI Link Is Not Healthy

In a Jupyter terminal, check container status:

```bash
cd ~/ai-virtual-assistant
docker compose --env-file .env.launchable \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml ps
```

If containers are still starting, wait and refresh the Brev **Using Secure Links** section.

### Do Not Use The Local NIM Profile

This lab path uses NVIDIA-hosted NIMs and public GHCR images. Do not start Compose with `--profile local-nim`; that profile is for self-hosted NIMs and requires GPUs.
