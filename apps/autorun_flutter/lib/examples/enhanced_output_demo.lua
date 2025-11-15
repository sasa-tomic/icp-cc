-- Enhanced Output Actions Demo
-- This script demonstrates the new output formatting and data transformation capabilities

function init(arg)
  return {
    results = {},
    filters = {},
    sort_field = "timestamp",
    sort_ascending = false,
    last_action = nil,
  }, {}
end

function view(state)
  local children = {
    { type = "section", props = { title = "Enhanced Output Actions Demo" }, children = {
      { type = "text", props = { text = "This demo shows enhanced result display, data transformation, and filtering capabilities." } },
      { type = "row", children = {
        { type = "button", props = { label = "Load Sample Data", on_press = { type = "load_sample" } } },
        { type = "button", props = { label = "Clear Results", on_press = { type = "clear" } } },
      } }
    } }
  }

  -- Show last action
  if state.last_action then
    table.insert(children, { type = "text", props = { text = "Last action: " .. state.last_action } })
  end

  -- Show results if available
  if state.results and #state.results > 0 then
    -- Filter controls
    table.insert(children, { type = "section", props = { title = "Filter & Sort Controls" }, children = {
      { type = "row", children = {
        { type = "text_field", props = {
          label = "Filter by type",
          placeholder = "e.g., transfer, stake",
          value = state.filters.type or "",
          on_change = { type = "set_filter", field = "type" }
        }},
        { type = "select", props = {
          label = "Sort by",
          value = state.sort_field or "timestamp",
          options = {
            { value = "timestamp", label = "Timestamp" },
            { value = "amount", label = "Amount" },
            { value = "type", label = "Type" }
          },
          on_change = { type = "set_sort", field = "sort_field" }
        }}
      } },
      { type = "toggle", props = {
        label = "Sort Ascending",
        value = state.sort_ascending == true,
        on_change = { type = "set_sort", field = "ascending" }
      }}
    } })

    -- Apply filters and sorting
    local filtered = state.results
    if state.filters.type and state.filters.type ~= "" then
      filtered = icp_filter_items(filtered, "type", state.filters.type)
    end

    filtered = icp_sort_items(filtered, state.sort_field, state.sort_ascending)

    -- Show enhanced list with results
    local enhanced_items = {}
    for i, item in ipairs(filtered) do
      local subtitle = string.format("%s • %s • %s",
        icp_format_timestamp(item.timestamp),
        item.type or "unknown",
        icp_format_icp(item.amount or 0)
      )

      table.insert(enhanced_items, {
        title = item.title or ("Item " .. i),
        subtitle = subtitle,
        data = item -- Include full data for detail view
      })
    end

    table.insert(children, icp_enhanced_list({
      items = enhanced_items,
      title = string.format("Filtered Results (%d items)", #enhanced_items),
      searchable = true
    }))

    -- Show statistics
    if #filtered > 0 then
      local amounts = {}
      for _, item in ipairs(filtered) do
        table.insert(amounts, item.amount or 0)
      end

      local stats = {
        count = #filtered,
        total = amounts[1] or 0
      }

      -- Calculate total (simplified - in real implementation would sum all amounts)
      for i = 2, #amounts do
        stats.total = stats.total + amounts[i]
      end

      table.insert(children, { type = "section", props = { title = "Statistics" }, children = {
        { type = "result_display", props = {
          data = {
            ["Total Transactions"] = stats.count,
            ["Total Amount"] = icp_format_icp(stats.total),
            ["Average"] = stats.count > 0 and icp_format_icp(stats.total / stats.count) or "0 ICP",
            ["Date Range"] = icp_format_timestamp((filtered[1] and filtered[1].timestamp) or 0) .. " to " .. icp_format_timestamp((filtered[#filtered] and filtered[#filtered].timestamp) or 0)
          },
          title = "Transaction Statistics",
          expandable = false
        }}
      }})
    end
  else
    table.insert(children, { type = "section", props = { title = "No Data" }, children = {
      { type = "text", props = { text = "Click 'Load Sample Data' to see enhanced output actions in action." } }
    }})
  end

  return { type = "column", children = children }
end

function update(msg, state)
  local t = (msg and msg.type) or ""

  if t == "load_sample" then
    -- Generate sample transaction data
    local sample_data = {}
    local current_time = 1704067200000000000 -- Sample timestamp (nanoseconds)

    local types = {"transfer", "stake", "mint", "burn", "approve"}
    local descriptions = {
      transfer = "ICP transfer to wallet",
      stake = "Neuron staking",
      mint = "Token minting",
      burn = "Token burning",
      approve = "Spending approval"
    }

    for i = 1, 20 do
      local txn_type = types[math.random(1, #types)]
      local amount = math.random(100000, 10000000) -- Random amount in e8s

      table.insert(sample_data, {
        title = string.format("%s #%d", txn_type:sub(1,1):upper() .. txn_type:sub(2), i),
        type = txn_type,
        amount = amount,
        timestamp = current_time - (i * 3600000000000), -- 1 hour increments
        from = "principal-" .. math.random(1000, 9999),
        to = "principal-" .. math.random(1000, 9999),
        description = descriptions[txn_type] or "Transaction",
        memo = "Demo transaction " .. i,
        fee = 10000 -- 0.0001 ICP fee
      })
    end

    state.results = sample_data
    state.last_action = "Loaded sample data (" .. #sample_data .. " items)"
    return state, {}
  end

  if t == "clear" then
    state.results = {}
    state.filters = {}
    state.last_action = "Cleared all results"
    return state, {}
  end

  if t == "set_filter" then
    local field = msg.field
    local value = msg.value or ""
    state.filters[field] = value
    state.last_action = string.format("Filter updated: %s = '%s'", field, value)
    return state, {}
  end

  if t == "set_sort" then
    local field = msg.field
    if field == "sort_field" then
      state.sort_field = msg.value
      state.last_action = string.format("Sort field changed to: %s", msg.value)
    elseif field == "ascending" then
      state.sort_ascending = msg.value
      state.last_action = string.format("Sort order: %s", msg.value and "ascending" or "descending")
    end
    return state, {}
  end

  -- Handle follow-up actions from enhanced list items
  if t == "view_details" then
    -- This would show detailed view of a specific transaction
    state.last_action = "Viewing details for transaction"
    return state, {}
  end

  state.last_action = "Unknown action: " .. t
  return state, {}
end