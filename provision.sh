#!/bin/bash

# BigSearch Agent - Azure Infrastructure Provisioning Script
# This script creates all required Azure resources and populates the .env file

set -e  # Exit on any error

echo "🚀 Starting BigSearch Agent infrastructure provisioning..."
echo
echo "🏗️  Architecture Overview:"
echo "   • Azure AI Foundry Hub/Project: Orchestrates agents and manages connections"
echo "   • Azure OpenAI: Hosts the GPT model that powers your agent's responses"
echo "   • Bing Search v7: Provides web search API for grounding agent responses"
echo "   • Connections: Links OpenAI and Bing Search to your AI Foundry project securely"
echo

# Configuration - modify these as needed
LOCATION="eastus2"
RG="rg-tjx-agent-1517"
AOAI_NAME="aoai-tjx-agent-8114"
AOAI_DEPLOYMENT_NAME="gpt-4o"
BING_NAME="bing-tjx-agent-22866" 
HUB_NAME="aihub-tjx-agent-1517"
PROJECT_NAME="aiproj-tjx-agent-1517"

echo "📋 Configuration:"
echo "  Location: $LOCATION"
echo "  Resource Group: $RG"
echo "  Azure OpenAI: $AOAI_NAME"
echo "  Model Deployment: $AOAI_DEPLOYMENT_NAME"
echo "  Bing Search: $BING_NAME"
echo "  AI Hub: $HUB_NAME"
echo "  AI Project: $PROJECT_NAME"
echo

# Check if logged into Azure
echo "🔐 Checking Azure login status..."
if ! az account show >/dev/null 2>&1; then
    echo "❌ Not logged into Azure. Please run 'az login' first."
    exit 1
fi

SUB_ID=$(az account show --query id -o tsv)
echo "✅ Logged in to subscription: $SUB_ID"
echo

# Create resource group
echo "📦 Creating resource group..."
if az group show --name "$RG" >/dev/null 2>&1; then
    echo "✅ Resource group '$RG' already exists"
else
    az group create --name "$RG" --location "$LOCATION"
    echo "✅ Created resource group '$RG'"
fi
echo

# Create Azure OpenAI resource (hosts the actual GPT model that powers the agent)
echo "🧠 Creating Azure OpenAI resource..."
echo "   Note: AI Foundry orchestrates agents, but Azure OpenAI hosts the actual GPT models"
if az cognitiveservices account show --name "$AOAI_NAME" --resource-group "$RG" >/dev/null 2>&1; then
    echo "✅ Azure OpenAI resource '$AOAI_NAME' already exists"
else
    az cognitiveservices account create \
        --name "$AOAI_NAME" \
        --resource-group "$RG" \
        --location "$LOCATION" \
        --kind OpenAI \
        --sku S0 \
        --yes
    echo "✅ Created Azure OpenAI resource '$AOAI_NAME'"
fi
echo

# Deploy model
echo "🤖 Deploying model '$AOAI_DEPLOYMENT_NAME'..."
if az cognitiveservices account deployment show \
    --resource-group "$RG" \
    --name "$AOAI_NAME" \
    --deployment-name "$AOAI_DEPLOYMENT_NAME" >/dev/null 2>&1; then
    echo "✅ Model deployment '$AOAI_DEPLOYMENT_NAME' already exists"
else
    az cognitiveservices account deployment create \
        --resource-group "$RG" \
        --name "$AOAI_NAME" \
        --deployment-name "$AOAI_DEPLOYMENT_NAME" \
        --model-format OpenAI \
        --model-name gpt-4o \
        --model-version 2024-08-06 \
        --capacity 10
    echo "✅ Created model deployment '$AOAI_DEPLOYMENT_NAME'"
fi
echo

# Create Bing Search resource (provides web search capabilities for grounding)
echo "🔍 Creating Bing Search resource..."
echo "   Note: This provides authenticated access to Bing's search index for your agent"
if az resource show --name "$BING_NAME" --resource-group "$RG" --resource-type Microsoft.Bing/accounts >/dev/null 2>&1; then
    echo "✅ Bing Search resource '$BING_NAME' already exists"
else
    echo "⚠️  Creating Bing Search resource manually via portal..."
    echo "   The CLI approach has limitations. Please create manually:"
    echo "   1. Go to: https://portal.azure.com/#create/Microsoft.CognitiveServicesBingSearch-5"
    echo "   2. Resource group: $RG"
    echo "   3. Name: $BING_NAME"
    echo "   4. Pricing tier: F0 (Free) or S1"
    echo "   5. Location: Global"
    echo "   Press Enter to continue after creating the resource..."
    read -p "Press Enter after creating Bing Search resource in portal..."
    
    # Verify the resource was created
    if az resource show --name "$BING_NAME" --resource-group "$RG" --resource-type Microsoft.Bing/accounts >/dev/null 2>&1; then
        echo "✅ Bing Search resource '$BING_NAME' confirmed"
    else
        echo "❌ Bing Search resource not found. Please create it manually before continuing."
        exit 1
    fi
fi
echo

# Install Azure AI extension if not present
echo "🔧 Ensuring Azure AI CLI extension is available..."
if ! az extension list --query "[?name=='ai']" -o tsv | grep -q ai; then
    echo "Installing Azure AI CLI extension..."
    az extension add -n ai -y || {
        echo "⚠️  Failed to install 'ai' extension, trying 'ml'..."
        az extension add -n ml -y || {
            echo "❌ Could not install AI extensions. You'll need to create the Hub/Project manually."
            echo "   Go to https://ai.azure.com and create a Hub and Project."
            exit 1
        }
    }
fi
echo

# Create AI Hub
echo "🏢 Creating AI Hub..."
if az ml workspace show --name "$HUB_NAME" --resource-group "$RG" >/dev/null 2>&1; then
    echo "✅ AI Hub '$HUB_NAME' already exists"
else
    # Create with ml extension (more widely available than ai extension)
    az ml workspace create \
        --name "$HUB_NAME" \
        --resource-group "$RG" \
        --location "$LOCATION" \
        --kind hub
    echo "✅ Created AI Hub '$HUB_NAME'"
fi
echo

# Create AI Project
echo "📊 Creating AI Project..."
if az ml workspace show --name "$PROJECT_NAME" --resource-group "$RG" >/dev/null 2>&1; then
    echo "✅ AI Project '$PROJECT_NAME' already exists"
else
    echo "Creating AI Project linked to Hub..."
    az ml workspace create \
        --name "$PROJECT_NAME" \
        --resource-group "$RG" \
        --location "$LOCATION" \
        --kind project \
        --hub-id "/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.MachineLearningServices/workspaces/$HUB_NAME"
    echo "✅ Created AI Project '$PROJECT_NAME'"
fi

# Get the correct agents endpoint
echo "🔗 Getting project endpoint..."
PROJECT_ENDPOINT=$(az resource show \
    --resource-group "$RG" \
    --name "$PROJECT_NAME" \
    --resource-type "Microsoft.MachineLearningServices/workspaces" \
    --query "properties.agentsEndpointUri" -o tsv)

if [[ -z "$PROJECT_ENDPOINT" ]]; then
    echo "❌ Could not get agents endpoint. Project may still be provisioning."
    echo "   Please wait a few minutes and check the project in https://ai.azure.com"
    exit 1
fi

echo "✅ Got project endpoint: $PROJECT_ENDPOINT"
echo

# Get resource IDs for connections
echo "🔗 Preparing connection information..."
AOAI_ID=$(az resource show -g "$RG" -n "$AOAI_NAME" --resource-type Microsoft.CognitiveServices/accounts --query id -o tsv)
BING_ID=$(az resource show -g "$RG" -n "$BING_NAME" --resource-type Microsoft.Bing/accounts --query id -o tsv)

# Create connections in the AI project
echo "🔌 Creating connections in AI project..."

# Try to create Azure OpenAI connection
if az ml connection list --resource-group "$RG" --workspace-name "$PROJECT_NAME" --query "[?name=='$AOAI_NAME']" -o tsv | grep -q "$AOAI_NAME"; then
    echo "✅ Azure OpenAI connection '$AOAI_NAME' already exists"
else
    echo "Creating Azure OpenAI connection..."
    cat > /tmp/aoai_connection.yml <<EOF
name: $AOAI_NAME
type: azure_open_ai
target: $AOAI_ID
auth_type: api_key
EOF
    if az ml connection create --resource-group "$RG" --workspace-name "$PROJECT_NAME" --file /tmp/aoai_connection.yml >/dev/null 2>&1; then
        echo "✅ Created Azure OpenAI connection '$AOAI_NAME'"
        rm -f /tmp/aoai_connection.yml
    else
        echo "⚠️  Failed to create Azure OpenAI connection via CLI. Manual setup required."
        rm -f /tmp/aoai_connection.yml
    fi
fi

# Try to create Bing Search connection
if az ml connection list --resource-group "$RG" --workspace-name "$PROJECT_NAME" --query "[?name=='$BING_NAME']" -o tsv | grep -q "$BING_NAME"; then
    echo "✅ Bing Search connection '$BING_NAME' already exists"
else
    echo "Creating Bing Search connection..."
    cat > /tmp/bing_connection.yml <<EOF
name: $BING_NAME
type: custom
target: https://api.bing.microsoft.com/
auth_type: api_key
credentials:
  key: placeholder
EOF
    if az ml connection create --resource-group "$RG" --workspace-name "$PROJECT_NAME" --file /tmp/bing_connection.yml >/dev/null 2>&1; then
        echo "✅ Created Bing Search connection '$BING_NAME'"
        rm -f /tmp/bing_connection.yml
    else
        echo "⚠️  Failed to create Bing Search connection via CLI. Manual setup required."
        rm -f /tmp/bing_connection.yml
    fi
fi

# Get actual connection names from the project (they may differ from resource names)
echo "🔍 Discovering actual connection names..."
ACTUAL_CONNECTIONS=$(az ml connection list --resource-group "$RG" --workspace-name "$PROJECT_NAME" --query "[].name" -o json 2>/dev/null || echo "[]")

# Find the Bing connection (look for 'bing' in the name)
ACTUAL_BING_CONNECTION=$(echo "$ACTUAL_CONNECTIONS" | jq -r '.[] | select(test("bing"; "i"))' 2>/dev/null || echo "")

if [[ -n "$ACTUAL_BING_CONNECTION" ]]; then
    echo "✅ Found Bing connection: $ACTUAL_BING_CONNECTION"
    BING_CONNECTION_ID="/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.MachineLearningServices/workspaces/$PROJECT_NAME/connections/$ACTUAL_BING_CONNECTION"
else
    echo "⚠️  Using fallback Bing connection name: $BING_NAME"
    BING_CONNECTION_ID="/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.MachineLearningServices/workspaces/$PROJECT_NAME/connections/$BING_NAME"
fi

echo "✅ Connections configured"
echo

# Update .env file
echo "📝 Updating .env file..."
cat > .env <<EOF
PROJECT_ENDPOINT=$PROJECT_ENDPOINT
MODEL_DEPLOYMENT_NAME=$AOAI_DEPLOYMENT_NAME
BING_CONNECTION_ID=$BING_CONNECTION_ID
# Optional: override the default question asked to the agent
# QUESTION=What is the weather in Seattle today?
# Optional: set to keep the agent resource after run
# KEEP_AGENT=1
EOF

echo "✅ Updated .env file with provisioned values"
echo

# Display summary
echo "🎉 Provisioning complete! Summary:"
echo "  PROJECT_ENDPOINT=$PROJECT_ENDPOINT"
echo "  MODEL_DEPLOYMENT_NAME=$AOAI_DEPLOYMENT_NAME"
echo "  BING_CONNECTION_ID=$BING_CONNECTION_ID"
echo

# Check if connections need manual setup
MANUAL_STEPS_NEEDED=false

if ! az ml connection list --resource-group "$RG" --workspace-name "$PROJECT_NAME" --query "[?name=='$AOAI_NAME']" -o tsv | grep -q "$AOAI_NAME"; then
    MANUAL_STEPS_NEEDED=true
fi

if ! az ml connection list --resource-group "$RG" --workspace-name "$PROJECT_NAME" --query "[?name=='$BING_NAME']" -o tsv | grep -q "$BING_NAME"; then
    MANUAL_STEPS_NEEDED=true
fi

if [ "$MANUAL_STEPS_NEEDED" = true ]; then
    echo "📌 Manual connection setup required:"
    echo "1. Go to https://ai.azure.com and navigate to your project '$PROJECT_NAME'"
    echo "2. Go to 'Connected resources' and add connections for:"
    echo "   - Azure OpenAI resource: '$AOAI_NAME' (name the connection '$AOAI_NAME')"
    echo "   - Bing Search resource: '$BING_NAME' (name the connection '$BING_NAME')"
    echo "3. Once connections are created, test the agent:"
else
    echo "✅ All connections created automatically!"
    echo "🚀 Ready to test the agent:"
fi

echo "   python -m venv .venv"
echo "   source .venv/bin/activate"
echo "   pip install -r requirements.txt"
echo "   python src/main.py"
echo
echo "💡 The .env file has been populated with the correct values!"

# Validate the setup
echo
echo "🔍 Validation:"
echo "✅ Resource Group: $(az group show --name "$RG" --query "name" -o tsv 2>/dev/null || echo "❌ Missing")"
echo "✅ Azure OpenAI: $(az cognitiveservices account show --name "$AOAI_NAME" --resource-group "$RG" --query "name" -o tsv 2>/dev/null || echo "❌ Missing")"
echo "✅ Model Deployment: $(az cognitiveservices account deployment show --resource-group "$RG" --name "$AOAI_NAME" --deployment-name "$AOAI_DEPLOYMENT_NAME" --query "name" -o tsv 2>/dev/null || echo "❌ Missing")"
echo "✅ AI Hub: $(az ml workspace show --name "$HUB_NAME" --resource-group "$RG" --query "name" -o tsv 2>/dev/null || echo "❌ Missing")"
echo "✅ AI Project: $(az ml workspace show --name "$PROJECT_NAME" --resource-group "$RG" --query "name" -o tsv 2>/dev/null || echo "❌ Missing")"
echo "$(az resource show --name "$BING_NAME" --resource-group "$RG" --resource-type Microsoft.Bing/accounts --query "name" -o tsv 2>/dev/null && echo "✅ Bing Search: $BING_NAME" || echo "⚠️  Bing Search: Needs manual creation")"