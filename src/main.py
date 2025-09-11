import os
import sys
from typing import Optional

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from azure.ai.agents.models import BingGroundingTool
from dotenv import load_dotenv


def get_env(name: str, required: bool = True) -> Optional[str]:
    value = os.environ.get(name)
    if not value and required:
        print(f"Missing required environment variable: {name}", file=sys.stderr)
        sys.exit(1)
    return value


def main():
    # Load .env if present
    load_dotenv()

    project_endpoint = get_env("PROJECT_ENDPOINT")
    model_name = get_env("MODEL_DEPLOYMENT_NAME")
    bing_connection_id = get_env("BING_CONNECTION_ID")

    # Create project client using DefaultAzureCredential (supports az login, managed identity, etc.)
    project_client = AIProjectClient(
        endpoint=project_endpoint, credential=DefaultAzureCredential()
    )

    # Initialize the Bing Grounding tool
    bing_tool = BingGroundingTool(connection_id=bing_connection_id)

    with project_client:
        # Create the Agent with the Bing Grounding tool
        agent = project_client.agents.create_agent(
            model=model_name,
            name="bigsearch-agent",
            instructions="You are a helpful agent. Use Grounding with Bing Search to cite sources.",
            tools=bing_tool.definitions,
        )
        print(f"Created agent, ID: {agent.id}")

        # Create a thread and a user message
        thread = project_client.agents.threads.create()
        print(f"Created thread, ID: {thread.id}")

        question = os.environ.get(
            "QUESTION", "How does wikipedia explain Euler's Identity?"
        )
        message = project_client.agents.messages.create(
            thread_id=thread.id,
            role="user",
            content=question,
        )
        print(f"Created message, ID: {message['id']}")

        # Create and process a run
        run = project_client.agents.runs.create_and_process(
            thread_id=thread.id,
            agent_id=agent.id,
        )
        print(f"Run finished with status: {run.status}")
        if run.status == "failed":
            print(f"Run failed: {run.last_error}")

        # Fetch messages and print results, with simple handling for URL citations if present
        print("Messages:")
        messages = project_client.agents.messages.list(thread_id=thread.id)
        for m in messages:
            role = m.get("role") if isinstance(m, dict) else getattr(m, "role", None)
            content = (
                m.get("content") if isinstance(m, dict) else getattr(m, "content", None)
            )
            print(f" - {role}: {content}")

        # Optionally print run steps to observe tool calls
        print("\nRun steps:")
        run_steps = project_client.agents.run_steps.list(
            thread_id=thread.id, run_id=run.id
        )
        for step in run_steps:
            step_id = (
                step.get("id") if isinstance(step, dict) else getattr(step, "id", None)
            )
            status = (
                step.get("status")
                if isinstance(step, dict)
                else getattr(step, "status", None)
            )
            print(f" Step {step_id} status: {status}")

        # Cleanup unless KEEP_AGENT is set
        if not os.environ.get("KEEP_AGENT"):
            project_client.agents.delete_agent(agent.id)
            print("Deleted agent")


if __name__ == "__main__":
    main()
