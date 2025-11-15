/// Model for a script template that users can select when creating new scripts
class ScriptTemplate {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final String level; // beginner, intermediate, advanced
  final String luaSource;
  final List<String> tags;
  final bool isRecommended;

  const ScriptTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.level,
    required this.luaSource,
    required this.tags,
    this.isRecommended = false,
  });
}

/// Built-in script templates available to users
class ScriptTemplates {
  static const List<ScriptTemplate> templates = [
    ScriptTemplate(
      id: 'hello_world',
      title: 'Hello World',
      description: 'Simple introduction to Lua scripting with basic UI components and state management.',
      emoji: '👋',
      level: 'beginner',
      luaSource: '''-- Hello World Example
-- This is the simplest possible Lua script for ICP
-- It demonstrates basic state management and UI creation

function init(arg)
  return {
    message = "Hello, ICP!",
    counter = 0,
    clicks = 0
  }, {}
end

function view(state)
  return {
    type = "column",
    children = {
      -- Title Section
      {
        type = "section",
        props = { title = "Hello World Example" },
        children = {
          {
            type = "text",
            props = {
              text = state.message,
              style = "title"
            }
          },
          {
            type = "text",
            props = {
              text = "Counter: " .. state.counter,
              style = "subtitle"
            }
          }
        }
      },

      -- Button Section
      {
        type = "section",
        props = { title = "Actions" },
        children = {
          {
            type = "button",
            props = {
              label = "Increment Counter",
              on_press = { type = "increment" }
            }
          },
          {
            type = "button",
            props = {
              label = "Reset Counter",
              on_press = { type = "reset" }
            }
          }
        }
      }
    }
  }
end

function update(msg, state)
  local action_type = msg.type

  if action_type == "increment" then
    state.counter = state.counter + 1
    state.clicks = state.clicks + 1
    return state, {}

  elseif action_type == "reset" then
    state.counter = 0
    return state, {}

  else
    -- Handle unknown actions
    return state, {}
  end
end''',
      tags: ['basic', 'ui', 'state'],
      isRecommended: true,
    ),

    ScriptTemplate(
      id: 'data_management',
      title: 'Simple Data Management',
      description: 'Learn how to manage lists of data, implement filtering, and work with user input.',
      emoji: '📋',
      level: 'beginner',
      luaSource: '''-- Simple Data Management Example
-- This script demonstrates basic data operations and filtering
-- Shows how to work with lists of items

function init(arg)
  return {
    items = {},
    filter_text = "",
    show_all = true
  }, {}
end

function view(state)
  return {
    type = "column",
    children = {
      -- Header Section
      {
        type = "section",
        props = { title = "Simple Data Management" },
        children = {
          {
            type = "text",
            props = {
              text = "Manage and filter a list of items",
              style = "subtitle"
            }
          }
        }
      },

      -- Controls Section
      {
        type = "section",
        props = { title = "Controls" },
        children = {
          -- Load Data Button
          {
            type = "button",
            props = {
              label = "Load Sample Data",
              on_press = { type = "load_data" }
            }
          },

          -- Clear Data Button
          {
            type = "button",
            props = {
              label = "Clear Data",
              on_press = { type = "clear_data" }
            }
          },

          -- Filter Input
          {
            type = "text_field",
            props = {
              label = "Filter Items",
              placeholder = "Type to filter...",
              value = state.filter_text,
              on_change = { type = "set_filter" }
            }
          }
        }
      },

      -- Results Section
      render_results_section(state)
    }
  }
end

function render_results_section(state)
  local visible_items = get_filtered_items(state)

  if #visible_items == 0 then
    return {
      type = "section",
      props = { title = "No Items" },
      children = {
        {
          type = "text",
          props = {
            text = "No items to display. Click 'Load Sample Data' to begin.",
            style = "muted"
          }
        }
      }
    }
  end

  return {
    type = "section",
    props = {
      title = "Results (" .. #visible_items .. " items)"
    },
    children = {
      -- Item Count
      {
        type = "text",
        props = {
          text = "Showing " .. #visible_items .. " of " .. #state.items .. " items",
          style = "small"
        }
      },

      -- Render Each Item
      render_item_list(visible_items)
    }
  }
end

function render_item_list(items)
  local item_elements = {}

  for i, item in ipairs(items) do
    table.insert(item_elements, {
      type = "row",
      children = {
        {
          type = "text",
          props = {
            text = item.name,
            style = "strong"
          }
        },
        {
          type = "text",
          props = {
            text = item.category,
            style = "tag"
          }
        },
        {
          type = "button",
          props = {
            label = "Delete",
            style = "small",
            on_press = {
              type = "delete_item",
              index = i
            }
          }
        }
      }
    })
  end

  return {
    type = "column",
    children = item_elements
  }
end

function get_filtered_items(state)
  local items = state.items or {}

  -- Apply text filter
  if not state.show_all and state.filter_text and state.filter_text ~= "" then
    local filtered = {}
    local filter_lower = state.filter_text:lower()

    for _, item in ipairs(items) do
      if item.name:lower():find(filter_lower) or
         item.category:lower():find(filter_lower) then
        table.insert(filtered, item)
      end
    end

    items = filtered
  end

  return items
end

function update(msg, state)
  local action_type = msg.type

  if action_type == "load_data" then
    state.items = generate_sample_data()
    return state, {}

  elseif action_type == "clear_data" then
    state.items = {}
    state.filter_text = ""
    return state, {}

  elseif action_type == "set_filter" then
    state.filter_text = msg.value or ""
    return state, {}

  elseif action_type == "delete_item" then
    local index = msg.index
    if index and index >= 1 and index <= #state.items then
      table.remove(state.items, index)
    end
    return state, {}

  else
    return state, {}
  end
end

function generate_sample_data()
  return {
    { name = "Apple", category = "Fruit" },
    { name = "Banana", category = "Fruit" },
    { name = "Carrot", category = "Vegetable" },
    { name = "Bread", category = "Grain" },
    { name = "Milk", category = "Dairy" },
    { name = "Cheese", category = "Dairy" },
    { name = "Chicken", category = "Protein" },
    { name = "Rice", category = "Grain" },
    { name = "Orange", category = "Fruit" },
    { name = "Broccoli", category = "Vegetable" }
  }
end''',
      tags: ['data', 'filtering', 'ui'],
      isRecommended: false,
    ),

    ScriptTemplate(
      id: 'icp_demo',
      title: 'Simple ICP Demo',
      description: 'Make real calls to ICP blockchain canisters and display the results.',
      emoji: '🌐',
      level: 'intermediate',
      luaSource: '''-- Simple ICP Demo
-- This script demonstrates basic ICP integration in a simplified way
-- Shows how to make canister calls and display results

function init(arg)
  return {
    balance = nil,
    last_action = "Ready to make ICP calls",
    show_info = false,
    counter = 0
  }, {}
end

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

function render_results_section(state)
  local results = {}

  -- Show balance if available
  if state.balance then
    table.insert(results, {
      title = "Account Balance",
      subtitle = icp_format_icp(state.balance) .. " ICP"
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
      icp_enhanced_list({
        items = results,
        title = "Query Results",
        searchable = false
      })
    }
  }
end

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

  -- Handle ICP call responses
  elseif action_type == "effect_result" then
    return handle_icp_response(msg, state)

  else
    state.last_action = "Unknown action: " .. action_type
    return state, {}
  end
end

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

function handle_icp_response(msg, state)
  if msg.id == "balance_query" then
    if msg.ok then
      state.balance = msg.data.balance or 0
      state.last_action = "Balance query successful: " .. icp_format_icp(state.balance) .. " ICP"
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
end''',
      tags: ['icp', 'blockchain', 'canister', 'advanced'],
      isRecommended: false,
    ),

    ScriptTemplate(
      id: 'enhanced_ui',
      title: 'Enhanced UI Demo',
      description: 'Advanced UI with filtering, sorting, statistics, and complex data visualization.',
      emoji: '🎨',
      level: 'advanced',
      luaSource: '''-- Enhanced UI Example - Refactored for Clarity
-- This script demonstrates advanced UI features with better organization
-- Shows advanced data filtering, sorting, and statistics calculation

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
        type = "text_field",
        props = {
          label = "Transaction Type",
          placeholder = "e.g., transfer, stake",
          value = state.filters.type,
          on_change = { type = "set_filter", field = "type" }
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
        searchable = true
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
    }
  }
end

function get_filtered_transactions(state)
  local transactions = state.transactions

  -- Apply type filter
  if state.filters.type and state.filters.type ~= "" then
    transactions = filter_by_type(transactions, state.filters.type)
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

  else
    state.last_action = "Unknown action: " .. action_type
    return state, {}
  end
end

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
end''',
      tags: ['ui', 'advanced', 'filtering', 'sorting', 'statistics'],
      isRecommended: false,
    ),
  ];

  static ScriptTemplate? getById(String id) {
    try {
      return templates.firstWhere((template) => template.id == id);
    } catch (e) {
      return null;
    }
  }

  static List<ScriptTemplate> getByLevel(String level) {
    return templates.where((template) => template.level == level).toList();
  }

  static List<ScriptTemplate> getRecommended() {
    return templates.where((template) => template.isRecommended).toList();
  }

  static List<ScriptTemplate> search(String query) {
    final lowerQuery = query.toLowerCase();
    return templates.where((template) {
      return template.title.toLowerCase().contains(lowerQuery) ||
          template.description.toLowerCase().contains(lowerQuery) ||
          template.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }
}