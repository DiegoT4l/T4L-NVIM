return {
  {
    "yetone/avante.nvim",
    -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
    -- ⚠️ must add this setting! ! !
    build = function()
      -- conditionally use the correct build system for the current OS
      if vim.fn.has("win32") == 1 then
        return "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false"
      else
        return "make"
      end
    end,
    event = "VeryLazy",
    version = false, -- Never set this value to "*"! Never!
    ---@module 'avante'
    ---@type avante.Config
    opts = function(_, opts)
      -- =======================================================================
      -- --- INICIO DE LA LÓGICA PARA OBTENER MODELOS DINÁMICAMENTE ---
      -- =======================================================================
      local function get_dynamic_models()
        local api_key = vim.env.AVANTE_OPENAI_API_KEY or vim.env.OPENAI_API_KEY or vim.env.NAGA_API_KEY

        if not api_key or api_key == "" then
          vim.notify(
            "Avante: No hay API key para el proxy (usa AVANTE_OPENAI_API_KEY / OPENAI_API_KEY).",
            vim.log.levels.WARN
          )
          return {}
        end

        local url = "https://api.naga.ac/v1/models"
        local command = {
          "curl",
          "-sS",
          "-m",
          "8", -- timeout
          "-H",
          "Authorization: Bearer " .. api_key,
          "-H",
          "Accept: application/json",
          url,
        }

        local body = vim.fn.system(command)
        if body == nil or body == "" then
          vim.notify("Avante: respuesta vacía desde " .. url, vim.log.levels.WARN)
          return {}
        end

        -- Remover BOM si viniera
        body = body:gsub("^\239\187\191", "")

        local ok, data = pcall(vim.json.decode, body)
        if not ok then
          vim.notify("Avante: error parseando JSON de /models: " .. tostring(data), vim.log.levels.ERROR)
          return {}
        end

        -- El proxy devuelve un array raíz de objetos { id, supported_endpoints, ... }
        local models = {}

        local function supports_chat(item)
          if type(item) ~= "table" then
            return false
          end
          local se = item.supported_endpoints
          if type(se) ~= "table" then
            return true
          end -- si no especifica, asumimos que sí
          for _, ep in ipairs(se) do
            if ep == "chat.completions" then
              return true
            end
          end
          return false
        end

        if type(data) == "table" and #data > 0 then
          for _, item in ipairs(data) do
            if type(item) == "table" and item.id and supports_chat(item) then
              -- Formato requerido por Avante: { id = "...", name = "..." }
              table.insert(models, {
                id = item.id,
                name = item.id,
                display_name = item.id,
              })
            end
          end
        elseif type(data) == "table" and type(data.data) == "table" then
          -- Soporte alternativo si viniera en { data = [...] }
          for _, item in ipairs(data.data) do
            if type(item) == "table" and item.id and supports_chat(item) then
              table.insert(models, {
                id = item.id,
                name = item.id,
                display_name = item.id,
              })
            end
          end
        end

        if #models == 0 then
          vim.notify(
            "Avante: no se encontraron modelos en " .. url .. " (¿token/permiso correcto?).",
            vim.log.levels.WARN
          )
        else
          vim.notify("Avante: " .. #models .. " modelos cargados correctamente", vim.log.levels.INFO)
          -- Para debug, descomenta la siguiente línea:
          -- vim.notify("Modelos cargados: " .. vim.inspect(vim.tbl_map(function(m) return m.id end, models)), vim.log.levels.INFO)
        end

        return models
      end

      local dynamic_models_list = get_dynamic_models()
      -- =======================================================================
      -- --- FIN DE LA LÓGICA ---
      -- =======================================================================

      -- Track avante's internal state during resize (Tu lógica original)
      local in_resize = false
      local original_cursor_win = nil
      local avante_filetypes = { "Avante", "AvanteInput", "AvanteAsk", "AvanteSelectedFiles" }

      -- Check if current window is avante
      local function is_in_avante_window()
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.api.nvim_buf_get_option(buf, "filetype")

        for _, avante_ft in ipairs(avante_filetypes) do
          if ft == avante_ft then
            return true, win, ft
          end
        end
        return false
      end

      -- Temporarily move cursor away from avante during resize
      local function temporarily_leave_avante()
        local is_avante, avante_win, avante_ft = is_in_avante_window()
        if is_avante and not in_resize then
          in_resize = true
          original_cursor_win = avante_win

          local target_win = nil
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            local ft = vim.api.nvim_buf_get_option(buf, "filetype")
            local is_avante_ft = false
            for _, aft in ipairs(avante_filetypes) do
              if ft == aft then
                is_avante_ft = true
                break
              end
            end
            if not is_avante_ft and vim.api.nvim_win_is_valid(win) then
              target_win = win
              break
            end
          end

          if target_win then
            vim.api.nvim_set_current_win(target_win)
            return true
          end
        end
        return false
      end

      -- Restore cursor to original avante window
      local function restore_cursor_to_avante()
        if in_resize and original_cursor_win and vim.api.nvim_win_is_valid(original_cursor_win) then
          vim.defer_fn(function()
            pcall(vim.api.nvim_set_current_win, original_cursor_win)
            in_resize = false
            original_cursor_win = nil
          end, 50)
        end
      end

      -- Prevent duplicate windows cleanup
      local function cleanup_duplicate_avante_windows()
        local seen_filetypes = {}
        local windows_to_close = {}
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf = vim.api.nvim_win_get_buf(win)
          local ft = vim.api.nvim_buf_get_option(buf, "filetype")

          if ft == "AvanteAsk" or ft == "AvanteSelectedFiles" then
            if seen_filetypes[ft] then
              table.insert(windows_to_close, win)
            else
              seen_filetypes[ft] = win
            end
          end
        end
        for _, win in ipairs(windows_to_close) do
          if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
          end
        end
      end

      vim.api.nvim_create_augroup("AvanteResizeFix", { clear = true })

      vim.api.nvim_create_autocmd({ "VimResized" }, {
        group = "AvanteResizeFix",
        callback = function()
          local moved = temporarily_leave_avante()
          if moved then
            vim.defer_fn(function()
              restore_cursor_to_avante()
              vim.cmd("redraw!")
            end, 100)
          end
          vim.defer_fn(cleanup_duplicate_avante_windows, 150)
        end,
      })

      vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
        group = "AvanteResizeFix",
        pattern = "*",
        callback = function(args)
          local buf = args.buf
          if buf and vim.api.nvim_buf_is_valid(buf) then
            local ft = vim.api.nvim_buf_get_option(buf, "filetype")
            for _, avante_ft in ipairs(avante_filetypes) do
              if ft == avante_ft then
                if in_resize then
                  return true
                end
                break
              end
            end
          end
        end,
      })

      vim.api.nvim_create_autocmd("FocusGained", {
        group = "AvanteResizeFix",
        callback = function()
          in_resize = false
          original_cursor_win = nil
          vim.defer_fn(cleanup_duplicate_avante_windows, 100)
        end,
      })

      -- Configuración final con modelos dinámicos
      local config = {
        provider = "deepseek",
        providers = {
          openai = {
            endpoint = "https://api.naga.ac/v1",
            model = "claude-sonnet-4.5",
            -- Lista dinámica de modelos desde el proxy (list_models es el campo correcto para Avante)
            list_models = dynamic_models_list,
          },
          deepseek = {
            __inherited_from = "openai",
            endpoint = "https://api.deepseek.com",
            api_key_name = "DEEPSEEK_API_KEY",
            model = "deepseek-coder", -- deepseek-chat / deepseek-coder / deepseek-reasoner
          },
        },
        cursor_applying_provider = "openai",
        auto_suggestions_provider = "deepseek",
        behaviour = {
          enable_cursor_planning_mode = true,
        },
        file_selector = {
          provider = "snacks", -- Avoid native provider issues
          provider_opts = {},
        },
        windows = {
          position = "left",
          wrap = true,
          width = 30,
          sidebar_header = {
            enabled = true,
            align = "center",
            rounded = false,
          },
          input = {
            prefix = "> ",
            height = 8,
          },
          edit = {
            start_insert = true,
          },
          ask = {
            floating = false,
            start_insert = true,
            focus_on_apply = "ours",
          },
        },
        system_prompt = "Este GPT es un clon del usuario, un arquitecto líder frontend especializado en React, con experiencia en arquitectura limpia, arquitectura hexagonal y separación de lógica en aplicaciones escalables. Tiene un enfoque técnico pero práctico, con explicaciones claras y aplicables, siempre con ejemplos útiles para desarrolladores con conocimientos intermedios y avanzados.\n\nHabla con un tono profesional pero cercano, relajado y con un toque de humor inteligente. Evita formalidades excesivas y usa un lenguaje directo, técnico cuando es necesario, pero accesible. Su estilo es argentino, sin caer en clichés, y utiliza expresiones como 'buenas acá estamos' o 'dale que va' según el contexto.\n\nSus principales áreas de conocimiento incluyen:\n- Desarrollo frontend con React y gestión de estado avanzada (Redux, Signals, State Managers propios como Gentleman State Manager y GPX-Store).\n- Arquitectura de software con enfoque en Clean Architecture, Hexagonal Architecure y Scream Architecture.\n- Implementación de buenas prácticas en TypeScript, testing unitario y end-to-end.\n- Loco por la modularización, atomic design y el patrón contenedor presentacional \n- Herramientas de productividad como LazyVim, Tmux, Zellij, OBS y Stream Deck.\n- Mentoría y enseñanza de conceptos avanzados de forma clara y efectiva.\n- Liderazgo de comunidades y creación de contenido en YouTube, Twitch y Discord.\n\nA la hora de explicar un concepto técnico:\n1. Explica el problema que el usuario enfrenta.\n2. Propone una solución clara y directa, con ejemplos si aplica.\n3. Menciona herramientas o recursos que pueden ayudar.\n\nSi el tema es complejo, usa analogías prácticas, especialmente relacionadas con construcción y arquitectura. Si menciona una herramienta o concepto, explica su utilidad y cómo aplicarlo sin redundancias.\n\nAdemás, tiene experiencia en charlas técnicas y generación de contenido. Puede hablar sobre la importancia de la introspección, có...",
      }

      return config
    end,
    dependencies = {
      "MunifTanjim/nui.nvim",
      {
        -- support for image pasting
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          -- recommended settings
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            -- required for Windows users
            use_absolute_path = true,
          },
        },
      },
    },
  },
}
