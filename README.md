# BigSearch Agent (Azure AI Foundry + Bing Grounding)

This sample shows how to create and run an Azure AI Foundry Agent in Python that uses the Grounding with Bing Search tool. It follows the official Microsoft docs and includes automated infrastructure provisioning.

## What it does

- Creates an `AIProjectClient` using your Azure AI Foundry project `PROJECT_ENDPOINT`.
- Creates an agent using your `MODEL_DEPLOYMENT_NAME` (e.g., `gpt-4o` or other supported model) and attaches the Bing Grounding tool using your `BING_CONNECTION_ID`.
- Starts a thread, sends a user message, runs the agent, and prints the grounded response (with optional citation annotations).
- Cleans up the agent resource when done.

## Quick Start (Automated Setup)

### 1. Prerequisites

- **Azure CLI** installed and authenticated (`az login`)
- **Bash shell** (macOS/Linux or WSL on Windows)
- **Python 3.9+**
- **jq** (for JSON processing): `brew install jq` on macOS or `sudo apt-get install jq` on Ubuntu

### 2. Run the Provision Script

The provision script automatically creates all required Azure resources:

```bash
# Make the script executable
chmod +x provision.sh

# Run the provisioning (will create new resources with timestamped names)
./provision.sh
```

**What the script creates:**
- ✅ **Resource Group**: `rg-tjx-agent-XXXX`
- ✅ **Azure OpenAI**: `aoai-tjx-agent-XXXX` with GPT-4o model deployment
- ✅ **AI Hub**: `aihub-tjx-agent-XXXX` 
- ✅ **AI Project**: `aiproj-tjx-agent-XXXX`
- ⚠️ **Bing Search**: Requires manual creation (see below)
- ⚠️ **Connections**: Require manual setup in Azure AI Foundry

### 3. Manual Steps Required

#### A. Create Bing Search Resource
When the script pauses, create the Bing Search resource:

1. **Open**: https://portal.azure.com/#create/Microsoft.CognitiveServicesBingSearch-5
2. **Fill in**:
   - **Resource Group**: Use the one shown in script output (e.g., `rg-tjx-agent-XXXX`)
   - **Name**: Use the name shown in script output (e.g., `bing-tjx-agent-XXXXX`)
   - **Pricing Tier**: `F0 (Free)` or `S1`
   - **Location**: `Global`
3. **Create** and wait for deployment
4. **Press Enter** to continue the script

#### B. Setup Connections in Azure AI Foundry
After the script completes:

1. **Open**: https://ai.azure.com
2. **Navigate** to your project (name shown in script output)
3. **Go to**: "Connected resources" or "Connections"
4. **Add Azure OpenAI Connection**:
   - Click "Add connection"
   - Select "Azure OpenAI"  
   - **Name**: Use resource name **without hyphens** (e.g., `aoaitjxagent8114`)
   - **Resource**: Select your Azure OpenAI resource
   - Save
5. **Add Bing Search Connection**:
   - Click "Add connection"
   - Select "Bing Search" or "Custom API"
   - **Name**: Use resource name **without hyphens** (e.g., `bingtjxagent22866`)
   - **Resource**: Select your Bing Search resource
   - Save

### 4. Test the Agent

```bash
# Create virtual environment
python -m venv .venv

# Activate it
source .venv/bin/activate  # macOS/Linux
# OR on Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run the agent
python src/main.py
```

## Manual Setup Alternative

If you prefer to create resources manually:

### Prerequisites

- Python 3.9+
- Azure CLI signed in (`az login`)
- An Azure AI Foundry project with:
  - A model deployment available (set `MODEL_DEPLOYMENT_NAME`)
  - A connected Grounding with Bing Search resource (use its connection ID for `BING_CONNECTION_ID`)

### Environment variables

Create a `.env` file (see `.env.example`) with:

- `PROJECT_ENDPOINT` — Your Azure AI Foundry project endpoint (e.g., `https://eastus2.api.azureml.ms/agents/v1.0/subscriptions/.../workspaces/your-project`)
- `MODEL_DEPLOYMENT_NAME` — The model deployment name (e.g., `gpt-4o`)
- `BING_CONNECTION_ID` — The connection resource ID for your Grounding with Bing connection in this format:
  `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>/providers/Microsoft.MachineLearningServices/workspaces/<workspace_name>/connections/<connection_name>`

### Install & run

```bash
python -m venv .venv
source .venv/bin/activate  # on macOS/Linux
pip install -r requirements.txt

# Ensure Azure CLI is logged in for DefaultAzureCredential
az login

# Run the sample
python src/main.py
```

## Configuration Options

### Environment Variables

The `.env` file supports these variables:

- `PROJECT_ENDPOINT` — **Required**: Azure AI Foundry project endpoint
- `MODEL_DEPLOYMENT_NAME` — **Required**: Model deployment name (e.g., `gpt-4o`)
- `BING_CONNECTION_ID` — **Required**: Bing Search connection ID  
- `QUESTION` — **Optional**: Custom question to ask the agent (default: "How does wikipedia explain Euler's Identity?")
- `KEEP_AGENT` — **Optional**: Set to `1` to keep the agent after run (default: agent is deleted)

### Customizing the Provision Script

You can modify the configuration section in `provision.sh`:

```bash
# Configuration - modify these as needed
LOCATION="eastus2"
RG="rg-tjx-agent-$(date +%H%M)"
AOAI_NAME="aoai-tjx-agent-$RANDOM"
AOAI_DEPLOYMENT_NAME="gpt-4o"
BING_NAME="bing-tjx-agent-$RANDOM"
HUB_NAME="aihub-tjx-agent-$(date +%H%M)"
PROJECT_NAME="aiproj-tjx-agent-$(date +%H%M)"
```

## Troubleshooting

### Common Issues

1. **Connection Names**: Azure AI Foundry creates connections without hyphens in the names, even if the resource names have hyphens. The provision script handles this automatically.

2. **CLI Extensions**: If you get errors about missing Azure ML extension:

   ```bash
   az extension add --name ml
   ```

3. **Bing Search Quota**: Free tier (F0) has limited queries per second. Use S1 tier for production.

4. **Authentication**: Ensure you're logged into Azure CLI:

   ```bash
   az login
   az account show  # Verify correct subscription
   ```

5. **Connection Issues**: If the agent can't find connections, check:
   - Connection names in Azure AI Foundry match those in `.env`
   - Connections are properly configured with valid API keys
   - Resource permissions are correctly set

### Debugging

To debug connection issues, you can list connections:

```bash
# List connections in your project
az ml connection list --resource-group "your-rg" --workspace-name "your-project"
```

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                     Azure AI Foundry                           │
│                                                                 │
│  ┌─────────────────┐    ┌──────────────────┐                  │
│  │   AI Project    │    │     AI Hub       │                  │
│  │                 │◄───┤                  │                  │
│  │ • Agents API    │    │ • Shared Storage │                  │
│  │ • Connections   │    │ • Key Vault      │                  │
│  └─────────────────┘    └──────────────────┘                  │
│           │                                                    │
│           ▼                                                    │
│  ┌─────────────────┐    ┌──────────────────┐                  │
│  │ Azure OpenAI    │    │   Bing Search    │                  │
│  │                 │    │                  │                  │
│  │ • GPT-4o Model  │    │ • Web Grounding  │                  │
│  │ • API Access    │    │ • Search API     │                  │
│  └─────────────────┘    └──────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │ Python Agent    │
                  │                 │
                  │ • Azure SDK     │
                  │ • Agent Logic   │
                  └─────────────────┘
```

## Notes

- This sample prints message role and content. If text annotations contain URL citations, they are displayed inline.
- The provision script automatically discovers connection names to handle Azure's naming conventions.
- To keep the agent for reuse, export `KEEP_AGENT=1` before running; otherwise the agent is deleted at the end.
- All resources are created with timestamped names to avoid conflicts.

## License

This project is licensed under the MIT License.
