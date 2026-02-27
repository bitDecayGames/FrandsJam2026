#!/usr/bin/env bash
# Build and serve the game with the LLM debug bridge enabled.
# Navigate Playwright to http://localhost:8080 after this starts.

set -e

echo "Building with LLM debug bridge..."
lime build html5 -Dplay -Dllm_bridge

echo "Serving on http://localhost:8080 ..."
exec python3 -m http.server -d export/html5/bin 8080
