vim.filetype.add({
  extension = {
    ["http"] = "http",
  },
})

return {
  "mistweaverco/kulala.nvim",
  keys = {
    { "<leader>Rs", "<cmd>lua require('kulala').run()<cr>", desc = "Send request" },
    { "<leader>Rt", "<cmd>lua require('kulala').toggle_view()<cr>", desc = "Toggle headers/body" },
    { "<leader>Ra", "<cmd>lua require('kulala').run_all()<cr>", desc = "Send all requests" },
    { "<leader>Ri", "<cmd>lua require('kulala').inspect()<cr>", desc = "Inspect current request" },
    { "<leader>Rc", "<cmd>lua require('kulala').copy()<cr>", desc = "Copy as cURL" },
    { "<leader>Rb", "<cmd>lua require('kulala').scratchpad()<cr>", desc = "Open scratchpad" },
    { "<leader>Rp", "<cmd>lua require('kulala').jump_prev()<cr>", desc = "Jump to previous request" },
    { "<leader>Rn", "<cmd>lua require('kulala').jump_next()<cr>", desc = "Jump to next request" },
  },
  ft = { "http", "rest" },
  opts = {
    -- Default formatters/pathsearch
    default_view = "body", -- body|headers|headers_body
    default_env = "dev", -- environment to use by default
    debug = false, -- enable debug mode

    -- Icons
    icons = {
      inlay = {
        loading = "⏳",
        done = "✅",
        error = "❌",
      },
      lualine = "🐼",
    },

    -- Scratchpad default contents
    scratchpad_default_contents = {
      "@MY_TOKEN_NAME=my_token_value",
      "",
      "# @name scratchpad",
      "POST https://httpbin.org/post HTTP/1.1",
      "accept: application/json",
      "content-type: application/json",
      "",
      "{",
      '  "foo": "bar"',
      "}",
    },

    -- Enable winbar
    winbar = false,

    -- Additional cURL options
    additional_curl_options = {},
  },
}
