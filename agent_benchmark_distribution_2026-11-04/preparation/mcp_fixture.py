"""Synthetic stdio MCP fixture: no credentials, repository access, or network."""
import json
import sys

for line in sys.stdin:
    request = json.loads(line)
    if "id" not in request:
        continue
    method = request.get("method")
    if method == "initialize":
        result = {
            "protocolVersion": request["params"]["protocolVersion"],
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "convoy-preparation-fixture", "version": "1"},
        }
    elif method == "tools/list":
        result = {"tools": [{
            "name": "read_sentinel",
            "description": "Return a fixed synthetic preparation sentinel.",
            "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
            "annotations": {"readOnlyHint": True},
        }]}
    elif method == "tools/call" and request["params"]["name"] == "read_sentinel":
        result = {"content": [{"type": "text", "text": "CONVOY_PREPARATION_MCP_OK"}]}
    elif method == "ping":
        result = {}
    else:
        print(json.dumps({"jsonrpc": "2.0", "id": request["id"],
                          "error": {"code": -32601, "message": "Method not found"}}), flush=True)
        continue
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
