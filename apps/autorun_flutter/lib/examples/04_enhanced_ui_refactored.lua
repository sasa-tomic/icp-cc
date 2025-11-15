-- Enhanced UI Example - Refactored for Clarity
-- This script demonstrates advanced UI features with better organization
-- Based on the original enhanced_output_demo.lua but with improved structure

--==============================================================================
-- INITIALIZATION
-- Set up the application state
--==============================================================================
function init(arg)
  return {
    -- Data storage
    transactions = {},

    -- Filtering and sorting
    filters = {
      type = "",
      amount_min = nil,
      amount_max = nil
    },
    sort_config = {
      field = "timestamp",
      ascending = false
    },

    -- UI state
    last_action = "Ready",
    showing_details = false,
    selected_transaction = nil
  }, {}
end

--==============================================================================
-- MAIN UI RENDERER
-- Creates the complete user interface
--==============================================================================
function view(state)
  return {
    type = "column",
    children = {
      render_header_section(),
      render_controls_section(state),
      render_status_section(state),
      render_transactions_section(state),
      render_statistics_section(state)
    }
  }
end

--==============================================================================
-- UI SECTION RENDERERS
-- Each function renders a specific part of the interface
--==============================================================================

function render_header_section()
  return {
    type = "section",
    props = { title = "Enhanced UI Demo" },
    children = {
      {
        type = "text",
        props = {
          text = "Advanced data management with filtering, sorting, and statistics",
          style = "subtitle"
        }
      }
    }
  }
end

function render_controls_section(state)
  return {
    type = "section",
    props = { title = "Controls" },
    children = {
      -- Data Loading Controls
      {
        type = "text",
        props = {
          text = "Data Management",
          style = "strong"
        }
      },
      {
        type = "row",
        children = {
          {
            type = "button",
            props = {
              label = "Load Sample Data",
              on_press = { type = "load_sample_data" }
            }
          },
          {
            type = "button",
            props = {
              label = "Clear All",
              on_press = { type = "clear_all" }
            }
          }
        }
      },

      -- Filter Controls
      render_filter_controls(state),

      -- Sort Controls
      render_sort_controls(state)
    }
  }
end

function render_filter_controls(state)
  return {
    type = "column",
    children = {
      {
        type = "text",
        props = {
          text = "Filters",
          style = "strong"
        }
      },
      {
        type = "row",
        children = {
          -- Type Filter
          {
            type = "text_field",
            props = {
              label = "Transaction Type",
              placeholder = "e.g., transfer, stake",
              value = state.filters.type,
              on_change = { type = "set_filter", field = "type" }
            }
          },

          -- Amount Range Filter
          {
            type = "text_field",
            props = {
              label = "Min Amount (ICP)",
              placeholder = "0.1",
              value = state.filters.amount_min or "",
              on_change = { type = "set_filter", field = "amount_min" }
            }
          }
        }
      }
    }
  }
end

function render_sort_controls(state)
  return {
    type = "column",
    children = {
      {
        type = "text",
        props = {
          text = "Sorting",
          style = "strong"
        }
      },
      {
        type = "row",
        children = {
          -- Sort Field Selection
          {
            type = "select",
            props = {
              label = "Sort By",
              value = state.sort_config.field,
              options = {
                { value = "timestamp", label = "Time" },
                { value = "amount", label = "Amount" },
                { value = "type", label = "Type" }
              },
              on_change = { type = "set_sort", field = "field" }
            }
          },

          -- Sort Direction Toggle
          {
            type = "toggle",
            props = {
              label = "Ascending",
              value = state.sort_config.ascending,
              on_change = { type = "set_sort", field = "ascending" }
            }
          }
        }
      }
    }
  }
end

function render_status_section(state)
  return {
    type = "section",
    props = { title = "Status" },
    children = {
      {
        type = "text",
        props = {
          text = "Last Action: " .. state.last_action,
          style = "small"
        }
      }
    }
  }
end

function render_transactions_section(state)
  local filtered_transactions = get_filtered_transactions(state)

  if #filtered_transactions == 0 then
    return {
      type = "section",
      props = { title = "Transactions" },
      children = {
        {
          type = "text",
          props = {
            text = "No transactions to display. Load sample data to begin.",
            style = "muted"
          }
        }
      }
    }
  end

  return {
    type = "section",
    props = {
      title = string.format("Transactions (%d items)", #filtered_transactions)
    },
    children = {
      -- Use the enhanced list component for rich display
      icp_enhanced_list({
        items = format_transactions_for_display(filtered_transactions),
        title = "Transaction List",
        searchable = true,
        on_item_select = { type = "select_transaction" }
      })
    ]
  }
end

function render_statistics_section(state)
  local filtered_transactions = get_filtered_transactions(state)

  if #filtered_transactions == 0 then
    return nil  -- Don't show stats section if no data
  end

  local stats = calculate_statistics(filtered_transactions)

  return {
    type = "section",
    props = { title = "Statistics" },
    children = {
      {
        type = "result_display",
        props = {
          data = stats,
          title = "Transaction Summary",
          expandable = true,
          expanded = false
        }
      }
    ]
  }
end

--==============================================================================
-- DATA PROCESSING FUNCTIONS
-- Handle filtering, sorting, and formatting
--==============================================================================

function get_filtered_transactions(state)
  local transactions = state.transactions

  -- Apply type filter
  if state.filters.type and state.filters.type ~= "" then
    transactions = filter_by_type(transactions, state.filters.type)
  end

  -- Apply amount filters
  if state.filters.amount_min or state.filters.amount_max then
    transactions = filter_by_amount_range(
      transactions,
      state.filters.amount_min,
      state.filters.amount_max
    )
  end

  -- Apply sorting
  transactions = sort_transactions(transactions, state.sort_config)

  return transactions
end

function filter_by_type(transactions, filter_type)
  local filtered = {}
  local filter_lower = filter_type:lower()

  for _, transaction in ipairs(transactions) do
    if transaction.type:lower():find(filter_lower) then
      table.insert(filtered, transaction)
    end
  end

  return filtered
end

function filter_by_amount_range(transactions, min_amount, max_amount)
  local filtered = {}

  for _, transaction in ipairs(transactions) do
    local amount_icp = transaction.amount / 100000000  -- Convert from e8s

    local meets_min = not min_amount or amount_icp >= tonumber(min_amount)
    local meets_max = not max_amount or amount_icp <= tonumber(max_amount)

    if meets_min and meets_max then
      table.insert(filtered, transaction)
    end
  end

  return filtered
end

function sort_transactions(transactions, sort_config)
  return icp_sort_items(transactions, sort_config.field, sort_config.ascending)
end

function format_transactions_for_display(transactions)
  local formatted_items = {}

  for i, transaction in ipairs(transactions) do
    table.insert(formatted_items, {
      title = transaction.title,
      subtitle = format_transaction_subtitle(transaction),
      data = transaction  -- Full data for detail view
    })
  end

  return formatted_items
end

function format_transaction_subtitle(transaction)
  return string.format("%s • %s • %s",
    icp_format_timestamp(transaction.timestamp),
    transaction.type,
    icp_format_icp(transaction.amount)
  )
end

function calculate_statistics(transactions)
  local total_amount = 0
  local type_counts = {}

  -- Calculate totals and counts
  for _, transaction in ipairs(transactions) do
    total_amount = total_amount + transaction.amount

    -- Count by type
    local txn_type = transaction.type
    type_counts[txn_type] = (type_counts[txn_type] or 0) + 1
  end

  -- Calculate average
  local average_amount = total_amount / #transactions

  -- Format statistics for display
  local stats = {
    ["Total Transactions"] = #transactions,
    ["Total Amount"] = icp_format_icp(total_amount),
    ["Average Amount"] = icp_format_icp(average_amount),
    ["Date Range"] = format_date_range(transactions)
  }

  -- Add type breakdown
  for txn_type, count in pairs(type_counts) do
    stats[txn_type:upper() .. " Transactions"] = count
  end

  return stats
end

function format_date_range(transactions)
  if #transactions == 0 then
    return "No data"
  end

  local earliest = transactions[#transactions]  -- Sorted by timestamp desc
  local latest = transactions[1]

  return string.format("%s to %s",
    icp_format_timestamp(earliest.timestamp),
    icp_format_timestamp(latest.timestamp)
  )
end

--==============================================================================
-- EVENT HANDLING
-- Process all user interactions
--==============================================================================
function update(msg, state)
  local action_type = msg.type

  if action_type == "load_sample_data" then
    return handle_load_sample_data(state)

  elseif action_type == "clear_all" then
    return handle_clear_all(state)

  elseif action_type == "set_filter" then
    return handle_set_filter(msg, state)

  elseif action_type == "set_sort" then
    return handle_set_sort(msg, state)

  elseif action_type == "select_transaction" then
    return handle_select_transaction(msg, state)

  else
    state.last_action = "Unknown action: " .. action_type
    return state, {}
  end
end

--==============================================================================
-- ACTION HANDLERS
-- Specific handlers for each type of user action
--==============================================================================

function handle_load_sample_data(state)
  state.transactions = generate_sample_transactions()
  state.last_action = "Loaded " .. #state.transactions .. " sample transactions"
  return state, {}
end

function handle_clear_all(state)
  state.transactions = {}
  state.filters = { type = "", amount_min = nil, amount_max = nil }
  state.last_action = "Cleared all data and filters"
  return state, {}
end

function handle_set_filter(msg, state)
  local field = msg.field
  local value = msg.value

  if value == "" then
    value = nil
  end

  state.filters[field] = value
  state.last_action = string.format("Filter updated: %s = '%s'", field, value or "")
  return state, {}
end

function handle_set_sort(msg, state)
  local field = msg.field

  if field == "field" then
    state.sort_config.field = msg.value
    state.last_action = "Sort by: " .. msg.value
  elseif field == "ascending" then
    state.sort_config.ascending = msg.value
    state.last_action = "Sort order: " .. (msg.value and "ascending" or "descending")
  end

  return state, {}
end

function handle_select_transaction(msg, state)
  state.selected_transaction = msg.item.data
  state.showing_details = true
  state.last_action = "Selected transaction: " .. msg.item.data.title
  return state, {}
end

--==============================================================================
-- SAMPLE DATA GENERATION
-- Create realistic sample transaction data
--==============================================================================
function generate_sample_transactions()
  local sample_data = {}
  local current_time = 1704067200000000000  -- Sample timestamp (nanoseconds)

  local transaction_types = {
    { type = "transfer", description = "ICP transfer", weight = 40 },
    { type = "stake", description = "Neuron staking", weight = 25 },
    { type = "mint", description = "Token minting", weight = 10 },
    { type = "burn", description = "Token burning", weight = 5 },
    { type = "approve", description = "Spending approval", weight = 20 }
  }

  for i = 1, 20 do
    local txn_info = select_weighted_transaction_type(transaction_types)
    local amount = math.random(100000, 10000000)  -- Random amount in e8s

    table.insert(sample_data, {
      title = string.format("%s #%d",
        txn_info.type:sub(1,1):upper() .. txn_info.type:sub(2),
        i
      ),
      type = txn_info.type,
      amount = amount,
      timestamp = current_time - (i * 3600000000000),  -- 1 hour increments
      from = "principal-" .. math.random(1000, 9999),
      to = "principal-" .. math.random(1000, 9999),
      description = txn_info.description,
      memo = "Demo transaction " .. i,
      fee = 10000  -- 0.0001 ICP fee
    })
  end

  return sample_data
end

function select_weighted_transaction_type(types)
  local total_weight = 0
  for _, type_info in ipairs(types) do
    total_weight = total_weight + type_info.weight
  end

  local selection = math.random(1, total_weight)
  local current_weight = 0

  for _, type_info in ipairs(types) do
    current_weight = current_weight + type_info.weight
    if selection <= current_weight then
      return type_info
    end
  end

  return types[1]  -- Fallback
end