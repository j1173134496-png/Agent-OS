#!/bin/sh
set -eu

brand_version='v0.3.14'

# Inject the V0.3 runtime into the pinned LibreChat image. The source image is
# immutable from the host; these idempotent patches are reapplied on recreate.
server_index='/app/api/server/index.js'
agents_chat='/app/api/server/routes/agents/chat.js'
tools_index='/app/api/app/clients/tools/index.js'
tools_loader='/app/api/app/clients/tools/util/handleTools.js'

if [ -f "$server_index" ] && ! grep -Fq "agentosPluginRouter" "$server_index"; then
  sed -i "/const routes = require('.\\/routes');/a const agentosPluginRouter = require('/app/agentos/runtime/pluginRouter');" "$server_index"
  sed -i "/app.use('\\/api\\/config'/i\\  app.use('/api/agentos', agentosPluginRouter);" "$server_index"
fi

if [ -f "$agents_chat" ] && ! grep -Fq "agentosCapabilityGate" "$agents_chat"; then
  sed -i "/const { getRoleByName } = require('~\\/models');/a const agentosCapabilityGate = require('/app/agentos/runtime/capabilityGate');" "$agents_chat"
  sed -i "/router.use(buildEndpointOption);/a router.use(agentosCapabilityGate);" "$agents_chat"
fi

if [ -f "$tools_index" ] && ! grep -Fq "AgentOSDemo" "$tools_index"; then
  sed -i "/const manifest = require('.\\/manifest');/a const AgentOSDemo = require('/app/agentos/runtime/AgentOSDemo');" "$tools_index"
  sed -i "/  createGeminiImageTool,/a\\  AgentOSDemo," "$tools_index"
fi

if [ -f "$tools_loader" ] && ! grep -Fq "agentos_demo: async" "$tools_loader"; then
  sed -i "/  const customConstructors = {/a\\    agentos_demo: async () => new AgentOSDemo({ req: options.req, userId: user })," "$tools_loader"
  sed -i "/  createOpenAIImageTools,/a\\  AgentOSDemo," "$tools_loader"
fi

for bundle in /app/client/dist/assets/*.js; do
  if [ -f "$bundle" ] && [ "${bundle##*/}" != 'agentos-plugins.js' ]; then
    sed -i 's|src:\`assets/logo.svg?agentos=v0.2.1\`|src:\`assets/logo.svg\`|g' "$bundle"
    sed -i 's|src:\`assets/logo.svg\`|src:\`assets/logo.svg?v0.3.14\`|g' "$bundle"
    # Keep provider fallback icons on the company mark when an endpoint does not supply iconURL.
    sed -i 's|assets/openai.svg|assets/logo-mark.png|g' "$bundle"
    sed -i 's|assets/openai.png|assets/logo-mark.png|g' "$bundle"
    sed -i -E 's#assets/(anthropic|claude|google|gemini|azure|mistral|meta|deepseek|qwen|ollama)\.(svg|png)#assets/logo-mark.png#g' "$bundle"
  fi
done

# Reuse the configured relay key for the native image toolkit. LibreChat's
# manifest gate must know about the fallback field before the tool can appear.
tool_manifest='/app/api/app/clients/tools/manifest.json'
if [ -f "$tool_manifest" ]; then
  if ! grep -Fq '"pluginKey": "agentos_demo"' "$tool_manifest"; then
    sed -i '2i\\  { "name": "AgentOS Demo", "pluginKey": "agentos_demo", "description": "AgentOS V0.3 read-only demonstration capability", "icon": "assets/logo-mark.png", "authConfig": [] },' "$tool_manifest"
  fi
  sed -i 's#"authField": "IMAGE_GEN_OAI_API_KEY"#"authField": "IMAGE_GEN_OAI_API_KEY||AGENTOS_LLM_API_KEY"#g' "$tool_manifest"
  sed -i 's#"icon": "assets/image_gen_oai.png"#"icon": "assets/logo-mark.png"#g' "$tool_manifest"
  sed -i 's#"icon": "assets/openai.svg"#"icon": "assets/logo-mark.png"#g' "$tool_manifest"
fi

for compressed in /app/client/dist/assets/index*.js.br /app/client/dist/assets/index*.js.gz; do
  if [ -f "$compressed" ]; then
    rm -f "$compressed"
  fi
done

if [ -f /app/client/dist/index.html ]; then
  sed -i 's|<html lang="[^"]*">|<html lang="zh-Hans">|g' /app/client/dist/index.html
  sed -i 's|<meta name="theme-color" content="[^"]*" />|<meta name="theme-color" content="#ff6a00" />|g' /app/client/dist/index.html
  sed -i 's|<meta name="description" content="[^"]*" />|<meta name="description" content="立能派 Agent OS - 企业智能工作台" />|g' /app/client/dist/index.html
  sed -i 's|<title>[^<]*</title>|<title>立能派 Agent OS</title>|g' /app/client/dist/index.html
  sed -i "s|assets/favicon-32x32.png?$brand_version|assets/favicon-32x32.png|g" /app/client/dist/index.html
  sed -i "s|assets/favicon-32x32.png\"|assets/favicon-32x32.png?$brand_version\"|g" /app/client/dist/index.html
  sed -i "s|assets/favicon-16x16.png?$brand_version|assets/favicon-16x16.png|g" /app/client/dist/index.html
  sed -i "s|assets/favicon-16x16.png\"|assets/favicon-16x16.png?$brand_version\"|g" /app/client/dist/index.html
  sed -i "s|assets/apple-touch-icon-180x180.png?$brand_version|assets/apple-touch-icon-180x180.png|g" /app/client/dist/index.html
  sed -i "s|assets/apple-touch-icon-180x180.png\"|assets/apple-touch-icon-180x180.png?$brand_version\"|g" /app/client/dist/index.html
  if ! grep -Fq 'agentos-theme.css' /app/client/dist/index.html; then
    sed -i "s|</head>|<link rel=\"stylesheet\" href=\"/assets/agentos-theme.css?$brand_version\" /></head>|g" /app/client/dist/index.html
  fi
  if ! grep -Fq 'agentos-plugins.js' /app/client/dist/index.html; then
    sed -i "s|</body>|<script src=\"/assets/agentos-plugins.js?$brand_version\"></script></body>|g" /app/client/dist/index.html
  else
    sed -i -E "s|/assets/agentos-plugins.js\?v0\.3\.[0-9]+|/assets/agentos-plugins.js?$brand_version|g" /app/client/dist/index.html
    sed -i -E "s|/assets/agentos-theme.css\?v0\.3\.[0-9]+|/assets/agentos-theme.css?$brand_version|g" /app/client/dist/index.html
  fi
  for entry in /app/client/dist/assets/index*.js; do
    if [ -f "$entry" ]; then
      asset_name=${entry##*/}
      sed -i "s|./assets/${asset_name}?agentos=v0.2.1|./assets/${asset_name}|g" /app/client/dist/index.html
      sed -i "s|./assets/${asset_name}|./assets/${asset_name}?$brand_version|g" /app/client/dist/index.html
    fi
  done
fi

if [ -f /app/api/server/index.js ] && grep -Fq 'const lang = req.cookies.lang' /app/api/server/index.js; then
  sed -i "/const lang = req.cookies.lang/c\    const lang = req.cookies.lang || req.headers['accept-language']?.split(',')[0] || process.env.AGENTOS_DEFAULT_LOCALE || 'en-US';" /app/api/server/index.js
fi

if [ "$#" -eq 0 ]; then
  echo 'AgentOS entrypoint requires a server command.' >&2
  exit 64
fi

exec "$@"
