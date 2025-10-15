Live input validation for Canister Client
----------------------------------------

- Validate user-entered JSON args against resolved Candid types in real time
- Show inline field-level errors and guidance (e.g., expected number vs string)
- Special-cases:
  - Big nat/int accept strings
  - Optional fields may be omitted or set to null
  - Vectors require arrays
  - Records allow object (by field name) or array (by order)
- Stretch: variant input helper (single-case object { "Case": value })


