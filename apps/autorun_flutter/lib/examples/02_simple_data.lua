--[[
==============================================================================
SIMPLE DATA MANAGEMENT EXAMPLE - BEGINNER LEVEL
==============================================================================

This script builds on the Hello World example and demonstrates how to work
with lists of data, implement filtering, and handle user input.

LEARNING OBJECTIVES:
- Manage collections of items in application state
- Implement search and filtering functionality
- Create reusable UI helper functions
- Handle text input from users
- Delete items from a list

KEY CONCEPTS:
1. Data Collections - Working with arrays/tables of items
2. Text Input - Handling user input from text fields
3. Data Filtering - Showing/hiding items based on criteria
4. Helper Functions - Organizing code into reusable parts
5. Dynamic UI - Creating UI elements based on data

==============================================================================
WHAT YOU'LL SEE:
- A section to load sample data (grocery items with categories)
- A text field to filter items by typing
- A list of items that updates as you filter
- Delete buttons next to each item
- Item count showing filtered vs total results

Try typing "fruit" in the filter field to see only fruit items!
==============================================================================

NEW UI COMPONENTS INTRODUCED:
- text_field: User input for text
- row: Horizontal layout container

NEW PROGRAMMING PATTERNS:
- Helper functions for reusable UI parts
- Loop-based UI generation from data
- Conditional UI rendering
- String matching for filtering

]]--

--==============================================================================
-- INITIALIZATION
-- Set up initial state for data management
--==============================================================================
function init(arg)
  return {
    items = {},        -- Empty list to store our data
    filter_text = "",  -- Current filter text (empty = show all)
    show_all = true    -- Whether to show all items or filter them
  }, {}
end

--==============================================================================
-- UI RENDERING
-- Create a clean, organized interface
--==============================================================================
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
          },

          -- Toggle Show All
          {
            type = "toggle",
            props = {
              label = "Show All Items",
              value = state.show_all,
              on_change = { type = "toggle_show_all" }
            }
          }
        }
      },

      -- Results Section
      render_results_section(state)
    }
  }
end

--==============================================================================
-- HELPER FUNCTIONS
-- Break down complex UI into smaller, reusable parts
--==============================================================================

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

--==============================================================================
-- EVENT HANDLING
-- Process user actions
--==============================================================================
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

  elseif action_type == "toggle_show_all" then
    state.show_all = msg.value
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

--==============================================================================
-- DATA GENERATION
-- Create sample data for demonstration
--==============================================================================
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
end

--[[
==============================================================================
TRY THESE EXPERIMENTS:

1. Add new items to the generate_sample_data() function
2. Create a button to add new items manually
3. Add more categories and filter by category
4. Sort the items alphabetically
5. Add a "Clear Filter" button
6. Count items by category and show statistics
7. Add edit functionality to change item names

TIPS:
- Use string.lower() for case-insensitive filtering
- table.remove() shifts all subsequent items
- Helper functions make code more readable
- State changes trigger automatic UI updates

DATA STRUCTURES:
- items: List of tables with name and category
- filter_text: String for search input
- show_all: Boolean to control filtering behavior

NEXT STEPS:
Try the "03_simple_icp_demo.lua" example to learn about blockchain integration!
==============================================================================
]]--