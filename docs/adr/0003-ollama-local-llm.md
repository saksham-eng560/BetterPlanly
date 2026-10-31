# Ollama is the only LLM runtime

The agent talks to a local Ollama server through `langchain-ollama`'s `ChatOllama`; there is no hosted-LLM path. Planly is meant to be private and offline-first, and Ollama has the most reliable tool-calling support among local runtimes. The model name is configuration (`OLLAMA_MODEL`, default `qwen2.5:7b`), not code. Adding an OpenAI-compatible provider later means replacing one factory function in `app/agent/llm.py`.
