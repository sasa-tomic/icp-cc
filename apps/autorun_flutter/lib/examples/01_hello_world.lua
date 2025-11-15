--[[
==============================================================================
HELLO WORLD EXAMPLE - BEGINNER LEVEL
==============================================================================

This is the simplest possible Lua script for ICP. It demonstrates the
fundamental concepts of building interactive applications.

LEARNING OBJECTIVES:
- Understand the basic structure of ICP Lua scripts
- Learn how to manage application state
- Create simple user interfaces with text and buttons
- Handle user interactions and update state

KEY CONCEPTS:
1. State Management - Storing and updating application data
2. UI Structure - Creating interfaces with nested components
3. Event Handling - Responding to user actions
4. Return Values - Understanding what each function should return

==============================================================================
WHAT YOU'LL SEE:
- A title section showing a welcome message
- A counter that displays the current value
- Two buttons: one to increment, one to reset the counter
- The counter value updates when you click buttons

Try modifying the message, adding new state variables, or creating new
buttons to see how the application changes!
==============================================================================

SCRIPT STRUCTURE:
Every ICP Lua script has three required functions:

1. init(arg) - Runs once when the script starts
   * Returns: (initial_state, initial_commands)

2. view(state) - Creates the UI based on current state
   * Returns: UI description table

3. update(msg, state) - Handles user interactions
   * Returns: (updated_state, new_commands)

]]--

--==============================================================================
-- INITIALIZATION
-- This function runs once when the script starts
-- Sets up the initial state of our application
--==============================================================================
function init(arg)
  return {
    -- State variables: data that can change over time
    message = "Hello, ICP!",
    counter = 0,
    clicks = 0
  }, {}  -- Initial commands (empty for now)
end

--==============================================================================
-- UI RENDERING
-- This function creates the user interface based on current state
-- It runs whenever the state changes and rebuilds the entire UI
--==============================================================================
function view(state)
  return {
    type = "column",  -- Main layout container (vertical)
    children = {
      -- Title Section: Shows welcome message and counter
      {
        type = "section",  -- Grouped UI area with border
        props = {
          title = "Hello World Example"  -- Section header
        },
        children = {
          {
            type = "text",  -- Display text content
            props = {
              text = state.message,  -- Dynamic text from state
              style = "title"  -- Large, bold text style
            }
          },
          {
            type = "text",
            props = {
              text = "Counter: " .. state.counter,  -- Concatenate text with state
              style = "subtitle"  -- Medium text style
            }
          }
        }
      },

      -- Button Section: Interactive controls
      {
        type = "section",
        props = { title = "Actions" },
        children = {
          {
            type = "button",  -- Clickable button
            props = {
              label = "Increment Counter",  -- Button text
              on_press = {
                type = "increment"  -- Action to send when clicked
              }
            }
          },
          {
            type = "button",
            props = {
              label = "Reset Counter",
              on_press = {
                type = "reset"  -- Different action type
              }
            }
          }
        }
      }
    }
  }
end

--==============================================================================
-- EVENT HANDLING
-- This function handles user interactions from buttons and other UI elements
-- It receives messages and updates the state accordingly
--==============================================================================
function update(msg, state)
  local action_type = msg.type  -- Get the action type from the message

  -- Handle different action types
  if action_type == "increment" then
    -- Increment both counter values
    state.counter = state.counter + 1
    state.clicks = state.clicks + 1
    return state, {}  -- Return updated state, no new commands

  elseif action_type == "reset" then
    -- Reset counter to zero, keep click count for stats
    state.counter = 0
    return state, {}

  else
    -- Handle unknown actions (good practice for debugging)
    return state, {}
  end
end

--[[
==============================================================================
TRY THESE EXPERIMENTS:

1. Change the initial message in init()
2. Add a new button that decrements the counter
3. Display the total clicks in the UI
4. Add colors or styles to the text elements
5. Create a maximum value for the counter

TIPS:
- State variables can be any Lua value (string, number, table, boolean)
- UI components are nested: column → section → text/button
- Message types must match between UI (on_press) and update() function
- Always return both state and commands from update()

NEXT STEPS:
Try the "02_simple_data.lua" example to learn about managing lists of data!
==============================================================================
]]--