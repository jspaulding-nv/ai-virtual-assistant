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

## Optional Automation For Repeated Instance Prep

The rest of this guide stays as the manual setup process. If you are preparing many LaunchPad instances, run the helper script after cloning or refreshing the repo. It automates steps 3 through 9: copying the notebook, preparing the kernel, writing `.env.launchpad`, logging in to `nvcr.io`, pulling images, optionally warming the full stack, and downloading sample manuals.

The LaunchPad path uses local NIM containers, so the temporary NVIDIA personal key is written to `.env.launchpad` as `NGC_API_KEY`.

Minimum prep, which copies files, configures the kernel, writes `.env.launchpad`, logs in to `nvcr.io`, pulls images, and downloads manuals:

```bash
cd ~/ai-virtual-assistant
bash launchpad/prepare-launchpad-instance.sh \
  --api-key '<temporary-nvidia-personal-key>'
```

Full prep, which also starts the stack once so local NIM model assets can download into `/home/nvidia/.cache/nim`:

```bash
cd ~/ai-virtual-assistant
bash launchpad/prepare-launchpad-instance.sh \
  --warm \
  --api-key '<temporary-nvidia-personal-key>'
```

If you want to warm the model cache but hand participants a stopped stack, add `--stop-after-warm`:

```bash
bash launchpad/prepare-launchpad-instance.sh \
  --warm \
  --stop-after-warm \
  --api-key '<temporary-nvidia-personal-key>'
```

Run `bash launchpad/prepare-launchpad-instance.sh --help` for all options, including `--skip-pull`, `--skip-manuals`, and `--timeout`.

The helper verifies that the pulled `agent-chain-server` image contains the LaunchPad product-guide routing fix. If it reports a stale agent image, rebuild and push the GHCR app images from the current source or update `GHCR_TAG` to a freshly published tag before preparing participant instances.

If a later notebook run fails with a host-port bind error, a previous stack is still running or partially running. Stop it before rerunning the notebook:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim down --remove-orphans
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

The script also stamps the copied `notebooks/ai_virtual_assistant_notebook_launchpad.ipynb` metadata with the `AIVA LaunchPad` kernelspec so VS Code can auto-select it when possible.

The global `jupyter` command may not be installed on LaunchPad, even when the kernel is registered correctly. Verify the user kernelspec directly:

```bash
test -f ~/.local/share/jupyter/kernels/aiva-launchpad/kernel.json
```

If VS Code still asks for a kernel on first open, choose `AIVA LaunchPad` when it appears. Depending on the VS Code/kernel picker state, it may be under **Select Another Kernel...** > **Jupyter Kernel...** or under **Python Environments...**. VS Code stores kernel choices in its own UI state; the notebook metadata lets it auto-select the kernel when its cache can match the installed kernelspec, but a first-open prompt is still possible. If no Python or Jupyter kernel options are available, install or enable the suggested **Python + Jupyter** extensions, then reload the browser tab or run **Developer: Reload Window**.

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
  --profile local-nim pull --policy always
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

The sample UI is available from the Code Server **Ports** tab next to the **Terminal** tab. If port `3001` is not listed automatically, click **Add Port**, enter `3001`, and open the forwarded URL.

## 11. Teardown / Reset After The Lab

Recommended automated teardown from the repo root:

```bash
cd ~/ai-virtual-assistant
bash launchpad/teardown-launchpad-instance.sh --yes
```

This stops the LaunchPad Compose stack, removes participant-ingested service data, removes the copied participant notebook, restores `.env.launchpad` from `launchpad/.env.example`, and logs out of `nvcr.io`.

To also reclaim NIM model cache and Docker image disk space:

```bash
cd ~/ai-virtual-assistant
bash launchpad/teardown-launchpad-instance.sh \
  --yes \
  --remove-nim-cache \
  --remove-images
```

To return an instance to a near-stock LaunchPad state, remove the repo clone last:

```bash
cd ~/ai-virtual-assistant
bash launchpad/teardown-launchpad-instance.sh \
  --yes \
  --remove-nim-cache \
  --remove-images \
  --remove-repo
```

Preview actions without changing the instance:

```bash
bash launchpad/teardown-launchpad-instance.sh --dry-run --remove-nim-cache --remove-images
```

Manual teardown commands are below for reference.

If the stack is running with a staff NGC key, stop the containers before resetting `.env.launchpad`. Running containers retain their environment values until they are recreated.

Stop the lab stack while keeping pulled Docker images, warmed NIM model assets, and bind-mounted service data:

```bash
docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim down --remove-orphans
```

To reset participant data and local secrets, remove the bind-mounted service data directories and restore the template env file. Use `sudo` for the service data directories because Postgres, pgAdmin, Redis, MinIO, etcd, and Milvus may create files owned by container users instead of the `nvidia` user:

```bash
sudo rm -rf deploy/compose/volumes/postgres_data \
  deploy/compose/volumes/pgadmin \
  deploy/compose/volumes/redis-data \
  deploy/compose/volumes/etcd \
  deploy/compose/volumes/minio \
  deploy/compose/volumes/milvus

rm -f notebooks/ai_virtual_assistant_notebook_launchpad.ipynb
cp launchpad/.env.example .env.launchpad
chmod 600 .env.launchpad
docker logout nvcr.io
```

This removes participant-ingested Postgres, Redis, MinIO, Milvus, and related state. `docker compose down -v` is not enough for this stack because these paths are bind-mounted directories.

Verify the reset:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
test -f deploy/ai_virtual_assistant_notebook_launchpad.ipynb
test -f notebooks/ingest_data.ipynb
test ! -f notebooks/ai_virtual_assistant_notebook_launchpad.ipynb
```

Optional deeper cleanup, only if the instance is being retired or disk space matters more than the next lab startup time:

```bash
rm -rf ~/.cache/nim

docker compose --env-file .env.launchpad \
  -f deploy/compose/docker-compose.yaml \
  -f deploy/compose/docker-compose.ghcr.yaml \
  -f launchpad/docker-compose.launchpad.yaml \
  --profile local-nim config --images | sort -u > /tmp/aiva-launchpad-images.txt

cat /tmp/aiva-launchpad-images.txt
xargs -r docker image rm < /tmp/aiva-launchpad-images.txt
rm -f /tmp/aiva-launchpad-images.txt
```

This removes the Docker images referenced by the LaunchPad Compose configuration plus known AIVA legacy/local app image names, including the GHCR application images, original `nvcr.io/nvidia/blueprint/aiva-customer-service-*` app images, local NIM images, Milvus, MinIO, Postgres, Redis, pgAdmin, etcd, nginx, and redis-commander images. It does not remove unrelated LaunchPad images such as `lp-jupyter-notebook:24.04` or unrelated CUDA/base images. Removing these images means the next staff setup will need to pull them again.

If the instance should be returned to a near-stock LaunchPad state, remove the repo clone last:

```bash
cd ~
sudo rm -rf ~/ai-virtual-assistant
```

## Notes On Secrets

If the staff NGC key must not be shared with participants, do not leave the stack running with that key and do not leave the real key in `.env.launchpad`. The deployment notebook reuses a prepared `.env.launchpad` key when present; if `.env.launchpad` has the template placeholder instead, participants will be prompted for their own key.
