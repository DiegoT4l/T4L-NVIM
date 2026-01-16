#!/bin/bash

# --- Configuración ---
# Ruta a tu archivo de configuración de OpenCode. Modifícala si no es la estándar.
CONFIG_FILE="$HOME/.config/opencode/opencode.json"
# URL de la API de NagaAC para listar modelos.
API_URL="https://api.naga.ac/v1/models"

# --- Verificaciones Previas ---

# 1. Verificar si la variable de entorno de la API key está definida.
if [ -z "$AVANTE_NAGA_API_KEY" ]; then
  echo "❌ Error: La variable de entorno AVANTE_NAGA_API_KEY no está definida."
  echo "Por favor, ejecute: export AVANTE_NAGA_API_KEY=\"su_clave_de_api\""
  exit 1
fi

# 2. Verificar si jq está instalado.
if ! command -v jq &>/dev/null; then
  echo "❌ Error: La herramienta 'jq' es necesaria pero no está instalada."
  echo "Por favor, instálela para continuar (ej. 'sudo apt-get install jq' o 'brew install jq')."
  exit 1
fi

# 3. Verificar si el archivo de configuración existe.
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Error: No se encontró el archivo de configuración en: $CONFIG_FILE"
  echo "Asegúrate de que la ruta es correcta y el archivo existe."
  exit 1
fi

echo "🚀 Iniciando actualización de modelos de NagaAC para OpenCode..."

# --- Lógica Principal ---

echo "📡 Obteniendo la lista de modelos desde NagaAC..."

# Llama a la API y procesa el JSON con jq en un solo paso.
# - Filtra solo los modelos que soportan "chat.completions".
# - Mapea los modelos al formato que OpenCode necesita.
# - Convierte el array de objetos a un solo objeto JSON.
MODELS_JSON=$(curl -s -H "Authorization: Bearer $AVANTE_NAGA_API_KEY" "$API_URL" |
  jq '.data | map(select(.supported_endpoints | index("chat.completions"))) | map({key: .id, value: {name: ("Naga: " + .display_name)}}) | from_entries')

# Verificar si se obtuvieron modelos.
if [ -z "$MODELS_JSON" ] || [ "$MODELS_JSON" == "null" ] || [ "$MODELS_JSON" == "{}" ]; then
  echo "⚠️ No se encontraron modelos de chat o hubo un error al contactar la API de NagaAC."
  exit 1
fi

MODEL_COUNT=$(echo "$MODELS_JSON" | jq 'keys | length')
echo "✅ Se encontraron $MODEL_COUNT modelos de chat."

# Construir el objeto completo del proveedor "naga"
NAGA_PROVIDER_JSON=$(jq -n \
  --argjson models "$MODELS_JSON" \
  '{
    "naga": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "NagaAC Proxy",
      "options": {
        "baseURL": "https://api.naga.ac/v1"
      },
      "models": $models
    }
  }')

echo "🔄 Actualizando el archivo de configuración: $CONFIG_FILE"

# Crear un archivo temporal para la nueva configuración
TEMP_FILE=$(mktemp)

# Actualizar el JSON:
# Usa 'jq' para añadir o reemplazar la clave "naga" dentro de la clave "provider".
# El operador '+=' es ideal porque crea la clave si no existe o la sobreescribe si ya existe.
jq --argjson nagaProvider "$NAGA_PROVIDER_JSON" '.provider += $nagaProvider' "$CONFIG_FILE" >"$TEMP_FILE"

# Reemplazar el archivo de configuración original con la versión actualizada.
mv "$TEMP_FILE" "$CONFIG_FILE"

echo "🎉 ¡Configuración de OpenCode actualizada exitosamente con los modelos de NagaAC!"
