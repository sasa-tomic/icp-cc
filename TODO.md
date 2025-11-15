Live input validation for Canister Client
----------------------------------------

Status: Completed

- Real-time validation of JSON args wired into the Canister Client
- Inline error list shown beneath the arguments editor
- Special-cases implemented:
  - Big nat/int accept strings
  - Optional fields may be omitted or set to null
  - Vectors require arrays
  - Records allow object (by field name) or array (by order)
- Stretch (variant helper): not implemented in this pass

