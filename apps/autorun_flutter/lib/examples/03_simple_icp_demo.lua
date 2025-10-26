-- Simple ICP Demo
-- This script demonstrates basic ICP integration in a simplified way
-- Shows how to make canister calls and display results

--==============================================================================
-- INITIALIZATION
--==============================================================================
function init(arg)
  return {
    balance = nil,
    last_action = "Ready to make ICP calls",
    show_info = false,
    counter = 0
  }, {}
end

--==============================================================================
-- UI RENDERING
--==============================================================================
function view(state)
  return {
    type = "column",
    children = {
      -- Header Section
      {
        type = "section",
        props = { title = "Simple ICP Demo" },
        children = {
          {
            type = "text",
            props = {
              text = "Demonstrates basic ICP blockchain integration",
              style = "subtitle"
            }
          },
          {
            type = "toggle",
            props = {
              label = "Show Info",
              value = state.show_info,
              on_change = { type = "toggle_info" }
            }
          }
        }
      },

      -- Info Section (conditional)
      (state.show_info and {
        type = "section",
        props = { title = "About This Demo" },
        children = {
          {
            type = "text",
            props = {
              text = "This script shows how to interact with ICP canisters. Click the buttons below to make real blockchain calls."
            }
          },
          {
            type = "text",
            props = {
              text = "Canister ID: ryjl3-tyaaa-aaaaa-aaaba-cai (ICP Ledger)",
              style = "small"
            }
          }
        }
      }) or nil,

      -- Actions Section
      {
        type = "section",
        props = { title = "Actions" },
        children = {
          {
            type = "button",
            props = {
              label = "Get Account Balance",
              on_press = { type = "get_balance" }
            }
          },
          {
            type = "button",
            props = {
              label = "Get Recent Transactions",
              on_press = { type = "get_transactions" }
            }
          },
          {
            type = "button",
            props = {
              label = "Clear Results",
              on_press = { type = "clear" }
            }
          }
        }
      },

      -- Counter Demo
      {
        type = "section",
        props = { title = "Simple Counter" },
        children = {
          {
            type = "text",
            props = {
              text = "Counter: " .. state.counter
            }
          },
          {
            type = "row",
            children = {
              {
                type = "button",
                props = {
                  label = "Increment",
                  on_press = { type = "increment" }
                }
              },
              {
                type = "button",
                props = {
                  label = "Reset",
                  on_press = { type = "reset" }
                }
              }
            }
          }
        }
      },

      -- Results Section
      render_results_section(state),

      -- Status Section
      {
        type = "section",
        props = { title = "Status" },
        children = {
          {
            type = "text",
            props = {
              text = "Last action: " .. state.last_action,
              style = "small"
            }
          }
        }
      }
    }
  }
end

--==============================================================================
-- HELPER FUNCTIONS
--==============================================================================

function render_results_section(state)
  local results = {}

  -- Show balance if available
  if state.balance then
    table.insert(results, {
      title = "Account Balance",
      subtitle = format_icp(state.balance) .. " ICP"
    })
  end

  -- Show transactions if available
  if state.transactions then
    table.insert(results, {
      title = "Transactions Found",
      subtitle = #state.transactions .. " recent transactions"
    })
  end

  if #results == 0 then
    return {
      type = "section",
      props = { title = "Results" },
      children = {
        {
          type = "text",
          props = {
            text = "No results yet. Click an action button to start.",
            style = "muted"
          }
        }
      }
    }
  end

  return {
    type = "section",
    props = { title = "Results" },
    children = {
      {
        type = "column",
        children = format_results_for_ui(results)
      }
    }
  }
end

--==============================================================================
-- EVENT HANDLING
--==============================================================================
function update(msg, state)
  local action_type = msg.type

  if action_type == "toggle_info" then
    state.show_info = msg.value
    state.last_action = msg.value and "Showed info" or "Hid info"
    return state, {}

  elseif action_type == "get_balance" then
    return make_balance_call(state)

  elseif action_type == "get_transactions" then
    return make_transaction_call(state)

  elseif action_type == "clear" then
    state.balance = nil
    state.transactions = nil
    state.last_action = "Cleared all results"
    return state, {}

  elseif action_type == "increment" then
    state.counter = state.counter + 1
    state.last_action = "Incremented counter to " .. state.counter
    return state, {}

  elseif action_type == "reset" then
    state.counter = 0
    state.last_action = "Reset counter"
    return state, {}

  -- Handle ICP call responses
  elseif action_type == "effect/result" then
    return handle_icp_response(msg, state)

  else
    state.last_action = "Unknown action: " .. action_type
    return state, {}
  end
end

--==============================================================================
-- ICP CANISTER CALLS
--==============================================================================

function make_balance_call(state)
  state.last_action = "Making balance query..."

  -- Create a simple balance query call
  local call = {
    canister_id = "ryjl3-tyaaa-aaaaa-aaaba-cai",
    method = "account_balance_dfx",
    kind = 0,  -- 0 = query call
    args = string.format([[{
      "account": "%s"
    }]], "default_account")
  }

  return state, {
    {
      kind = "icp_call",
      id = "balance_query",
      call = call
    }
  }
end

function make_transaction_call(state)
  state.last_action = "Making transaction query..."

  -- Create a simple transaction query call
  local call = {
    canister_id = "ryjl3-tyaaa-aaaaa-aaaba-cai",
    method = "query_blocks",
    kind = 0,  -- 0 = query call
    args = string.format([[{
      "start": 0,
      "length": 5
    }]])
  }

  return state, {
    {
      kind = "icp_call",
      id = "transaction_query",
      call = call
    }
  }
end

--==============================================================================
-- RESPONSE HANDLING
--==============================================================================

function handle_icp_response(msg, state)
  if msg.id == "balance_query" then
    if msg.ok then
      state.balance = msg.data.balance or 0
      state.last_action = "Balance query successful: " .. format_icp(state.balance) .. " ICP"
    else
      state.last_action = "Balance query failed: " .. (msg.error or "Unknown error")
    end
    return state, {}

  elseif msg.id == "transaction_query" then
    if msg.ok then
      local blocks = msg.data.blocks or {}
      state.transactions = blocks
      state.last_action = "Transaction query successful: " .. #blocks .. " transactions found"
    else
      state.last_action = "Transaction query failed: " .. (msg.error or "Unknown error")
    end
    return state, {}

  else
    state.last_action = "Unknown response: " .. (msg.id or "no id")
    return state, {}
  end
end

--==============================================================================
-- HELPER FUNCTIONS
-- Simple implementations for demonstration purposes
--==============================================================================

function format_icp(amount_e8s)
  -- Convert from e8s (10^-8) to ICP
  if not amount_e8s then return "0 ICP" end
  local icp = amount_e8s / 100000000
  return string.format("%.8f ICP", icp)
end

function format_results_for_ui(results)
  local ui_elements = {}
  
  for i, result in ipairs(results) do
    table.insert(ui_elements, {
      type = "section",
      props = {
        title = result.title
      },
      children = {
        {
          type = "text",
          props = {
            text = result.subtitle or "No details available",
            style = "subtitle"
          }
        }
      }
    })
  end
  
  return ui_elements
end